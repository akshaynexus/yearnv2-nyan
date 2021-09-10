// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ISynthetixRewards {
    function stake(uint256 amount) external payable;

    function exit() external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function earned(address account) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function stakeToken() external view returns (address);

    function rewardToken() external view returns (address);

    function notifyRewardAmount(uint256 newAmount) external;
}
