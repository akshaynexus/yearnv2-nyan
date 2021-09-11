// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/ISynthetixRewards.sol";

interface IERC20Extended {
    function decimals() external view returns (uint8);
}

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint) external;
}

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    //Remove the assignment to fix deployment issue
    uint256 public minProfit;
    uint256 public minCredit;

    //Spookyswap as default
    IUniswapV2Router02 public router = IUniswapV2Router02(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    address weth = router.WETH();

    ISynthetixRewards public pool;
    IERC20 public reward;
    event Cloned(address indexed clone);

    constructor(address _vault, address _ethStakePool) public BaseStrategy(_vault) {
        _initializeStrat(_ethStakePool);
    }

    //Allow eth to be sent
    receive() external payable {}

    function _initializeStrat(address _ethStakePool) internal {
        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 6300;
        profitFactor = 1500;
        debtThreshold = 1_000_000 * 1e18;
        pool = ISynthetixRewards(_ethStakePool);
        reward = IERC20(pool.rewardToken());
        reward.approve(address(router), type(uint256).max);
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _ethStakePool
    ) external {
        //note: initialise can only be called once. in _initialize in BaseStrategy we have: require(address(want) == address(0), "Strategy already initialized");
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_ethStakePool);
    }

    function cloneStrategy(address _vault, address _ethStakePool) external returns (address newStrategy) {
        newStrategy = this.cloneStrategy(_vault, msg.sender, msg.sender, msg.sender, _ethStakePool);
    }

    function cloneStrategy(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _ethStakePool
    ) external returns (address payable newStrategy) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));

        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(clone_code, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(add(clone_code, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            newStrategy := create(0, clone_code, 0x37)
        }

        Strategy(newStrategy).initialize(_vault, _strategist, _rewards, _keeper, _ethStakePool);

        emit Cloned(newStrategy);
    }

    function name() external view override returns (string memory) {
        return "StrategyETHNyanFarm";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    //Returns staked value
    function balanceOfStake() public view returns (uint256) {
        return uint256(pool.balanceOf(address(this)));
    }

    function pendingReward() public view returns (uint256) {
        return uint256(pool.earned(address(this)));
    }

    function pendingRewardInWant() public view returns (uint256) {
        return quote(address(reward), address(weth), pendingReward());
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        //Add the want balance and staked balance
        return balanceOfWant().add(balanceOfStake());
    }

    function tendTrigger(uint256 callCostInWei) public view virtual override returns (bool) {
        return balanceOfWant() > minCredit;
    }

    function harvestTrigger(uint256 callCostInWei) public view virtual override returns (bool) {
        return pendingRewardInWant() > minProfit || vault.creditAvailable() > minCredit;
    }

    function _depositToWETH(uint256 _amountETH) internal {
        IWETH(weth).deposit{value: _amountETH}();
    }

    function _withdrawETH(uint256 _amountETH) internal {
        IWETH(weth).withdraw(_amountETH);
    }

    function _deposit(uint _depositAmount) internal {
        _withdrawETH(_depositAmount);
        pool.stake{value: address(this).balance}(0);
    }

    function _withdrawAll() internal {
        pool.withdraw(uint128(balanceOfStake()));
        _depositToWETH(address(this).balance);
    }

    function _withdraw(uint128 _withdrawAmount) internal {
        pool.withdraw(_withdrawAmount);
        _depositToWETH(address(this).balance);
    }

    function returnDebtOutstanding(uint256 _debtOutstanding) internal returns (uint256 _debtPayment, uint256 _loss) {
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }
    }

    function swapRewards() internal {
        pool.getReward();
        uint256 rBal = reward.balanceOf(address(this));
        if (rBal > 0)
            router.swapExactTokensForTokens(
                reward.balanceOf(address(this)),
                0,
                getTokenOutPath(address(reward), weth),
                address(this),
                block.timestamp
            );
    }

    function handleProfit() internal returns (uint256 _profit) {
        uint256 balanceOfWantBefore = balanceOfWant();
        swapRewards();
        _profit = balanceOfWant().sub(balanceOfWantBefore);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        (_debtPayment, _loss) = returnDebtOutstanding(_debtOutstanding);
        _profit = handleProfit();
        uint256 balanceAfter = balanceOfWant();
        uint256 requiredWantBal = _profit + _debtPayment;
        if (balanceAfter < requiredWantBal) {
            //Withdraw enough to satisfy profit check
            _withdraw(uint128(requiredWantBal.sub(balanceAfter)));
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _wantAvailable = balanceOfWant();

        if (_debtOutstanding >= _wantAvailable) {
            return;
        }

        uint256 toInvest = _wantAvailable.sub(_debtOutstanding);

        if (toInvest > 0) {
            _deposit(toInvest);
        }
    }

    function liquidatePosition(uint256 _amountNeeded) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 balanceWant = balanceOfWant();
        uint256 balanceStaked = balanceOfStake();
        if (_amountNeeded > balanceWant) {
            uint256 amountToWithdraw = (Math.min(balanceStaked, _amountNeeded - balanceWant));
            _withdraw(uint128(amountToWithdraw));
        }
        // Since we might free more than needed, let's send back the min
        _liquidatedAmount = Math.min(balanceOfWant(), _amountNeeded);
    }

    function getTokenOutPath(address _token_in, address _token_out) internal view returns (address[] memory _path) {
        bool is_weth = _token_in == address(weth) || _token_out == address(weth);
        _path = new address[](is_weth ? 2 : 3);
        _path[0] = _token_in;
        if (is_weth) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(weth);
            _path[2] = _token_out;
        }
    }

    function quote(
        address _in,
        address _out,
        uint256 _amtIn
    ) internal view returns (uint256) {
        if(_amtIn ==0) return 0;
        address[] memory path = getTokenOutPath(_in, _out);
        return router.getAmountsOut(_amtIn, path)[path.length - 1];
    }

    function prepareMigration(address _newStrategy) internal override {
        _withdrawAll();
    }

    function liquidateAllPositions() internal virtual override returns (uint256 _amountFreed) {
        _withdrawAll();
        _amountFreed = balanceOfWant();
    }

    function ethToWant(uint256 _amtInWei) public view virtual override returns (uint256) {
        return address(want) == address(weth) ? _amtInWei : quote(weth, address(want), _amtInWei);
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    function protectedTokens() internal view override returns (address[] memory) {}
}
