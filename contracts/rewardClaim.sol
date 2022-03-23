// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract RewardClaim is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public totalDistributed; // Total amount given out
    uint256 public rewardDebt; // Total amount owed to users
    address public rewardToken;
    mapping (address => uint256) public claimable;
    mapping (address => uint256) public claimed;
    mapping (address => uint256) public lastClaimTime;
    mapping (address => uint256) public lastClaimAmount;

    event ClaimReward(address from, uint256 amount);

    constructor (address _rewardToken) {
        rewardToken = _rewardToken;
    }

    function claim(address _user) external {
        require(claimable[_user] > 0, "No rewards to claim");
        require(rewardTokenBalance() > claimable[_user], "Out of rewards");

        uint256 amount = claimable[_user];
        claimable[_user] = 0;
        lastClaimTime[_user] = block.timestamp;
        claimed[_user] += amount;
        lastClaimAmount[_user] = amount;
        rewardDebt -= amount;
        IERC20(rewardToken).safeTransfer(_user, amount);

        emit ClaimReward(_user, amount);
    }

    function rewardTokenBalance() public view returns (uint256) {
        return IERC20(rewardToken).balanceOf(address(this));
    }

    function addRewardAmounts(address[] calldata users, uint256[] calldata amount) external onlyOwner {
        require(users.length == amount.length, "Arrays length don't match");
        for (uint256 k = 0; k < users.length; k++) {
            _addRewardAmount(users[k], amount[k]);
        }
    }

    function _addRewardAmount(address user, uint256 amount) internal {
        claimable[user] += amount;
        rewardDebt += amount;
        totalDistributed += amount;
    }

    function removeRewardAmounts(address[] calldata users, uint256[] calldata amount) external onlyOwner {
        require(users.length == amount.length, "Arrays length don't match");
        for (uint256 k = 0; k < users.length; k++) {
            _removeRewardAmount(users[k], amount[k]);
        }
    }

    function _removeRewardAmount(address user, uint256 amount) internal {
        require(claimable[user] >= amount);
        claimable[user] -= amount;
        rewardDebt -= amount;
    }

    function recoverToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, IERC20(tokenAddress).balanceOf(address(this)));
    }

    function addToTotalDistributed(uint256 amount) external onlyOwner {
        totalDistributed += amount;
    }
}