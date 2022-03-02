// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MultiSend is Ownable {
    using SafeERC20 for IERC20;

    function sendAll(
        address tokenAddress,
        address[] memory userAddresses,
        uint256[] memory userAmounts
    ) public onlyOwner {
        uint256 len = userAddresses.length;
        require (len == userAmounts.length, 'Length mismatch');
        for (uint256 i = 0; i < len; i++) {
            IERC20(tokenAddress).safeTransfer(userAddresses[i], userAmounts[i]);
        }
    }

    function recoverToken(address tokenAddress) public onlyOwner {
        IERC20(tokenAddress).transfer(owner(), IERC20(tokenAddress).balanceOf(address(this)));
    }

}