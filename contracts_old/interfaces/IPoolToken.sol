// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IPoolToken {
    function pool_burn_from(address _address, uint256 _amount) external;
    function approve(address a, uint256 b) external returns (bool);
    function pool_mint(address _address, uint256 m_amount) external;
}













