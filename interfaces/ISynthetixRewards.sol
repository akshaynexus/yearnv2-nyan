// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ISynthetixRewards {
    function stake(uint128) external payable;

    function exit() external;

    function withdraw(uint128 amount) external;

    function getReward() external;

    function earned(address account) external view returns (uint128);

    function balanceOf(address account) external view returns (uint128);

    function stakeToken() external view returns (address);

    function rewardToken() external view returns (address);

    function notifyRewardAmount(uint128 newAmount) external;
}
