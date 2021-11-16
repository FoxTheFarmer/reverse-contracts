// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FakeUSDC is ERC20 {
    address private _owner;

    uint8 private  __decimals;
    constructor(
    ) ERC20('FakeUSDC', 'FakeUSDC') {
        __decimals = 6;
        _owner = msg.sender;
    }

    // anyone can mint
    function mint(address dst, uint256 amt) public returns (bool) {
        _mint(dst, amt);
        return true;
    }

    function decimals() public view override returns (uint8) {
        return __decimals;
    }

    function owner() public view returns (address) {
        return _owner;
    }
}
