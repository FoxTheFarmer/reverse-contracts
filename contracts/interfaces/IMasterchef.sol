// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IMasterchef {
    function deposit ( uint256 _pid, uint256 _amount, address _to, address referral ) external;
    function emergencyWithdraw ( uint256 _pid ) external;
    function harvest ( uint256 _pid, address _to ) external;
    function pendingReward ( uint256 _pid, address _user ) external view returns ( uint256 );
    function userInfo ( uint256, address ) external view returns ( uint256 amount, uint256 rewardDebt, uint256 nextHarvestUntil, uint256 depositTimerStart, uint firstDepositTime, uint lastDepositTime, uint lastWithdrawTime);
    function withdraw ( uint256 _pid, uint256 _amount, address _to ) external;
}