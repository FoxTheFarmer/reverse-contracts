// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import './IVeERC20.sol';

/**
 * @dev Interface of the VePtp
 */
interface IVeRvrs is IVeERC20 {
    function isUser(address _addr) external view returns (bool);

    function deposit(uint256 _amount, bool _restakeRewards) external;

    function claim(bool _restakeRewards) external;

    function withdraw(uint256 _amount) external;

    function getStakedRvrs(address _addr) external view returns (uint256);

    function getVotes(address _account) external view returns (uint256);
}