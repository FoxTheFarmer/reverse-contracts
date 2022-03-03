// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract veRvrsRewards is ERC20("veRVRS Dummy Token", "veRVRS REWARDS"), Ownable {

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

}