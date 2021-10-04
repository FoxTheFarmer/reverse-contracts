// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./TaxableToken.sol";

contract Coffin is TaxableToken, Initializable {
    using SafeMath for uint256;
    uint256 public constant genesis_supply = 3_000_000 ether; // for initial liquidity. 
    // 
    uint256 public constant REWARD_ALLOCATION = 97_000_000 ether; // 
    uint256 public rewardClaimed;
    function init(
        address _maker
    ) external initializer onlyOwner {
        coffin_pools[_maker] = true;
        coffin_pools_array.push(_maker);

        // coffin_pools[msg.sender] = true;
        // coffin_pools_array.push(msg.sender);
        
        _mint(msg.sender, genesis_supply);
    }

    function reward_mint(address recipient, uint256 amount) public onlyPools {
        require(amount > 0, "invalidAmount");
        require(recipient != address(0), "!rewardController");
        uint256 _remainingRewards = REWARD_ALLOCATION - rewardClaimed;
        require(amount <= _remainingRewards, "exceedRewards");
        rewardClaimed = rewardClaimed + amount;
        super._mint(recipient, amount);
        emit Minted(msg.sender, recipient, amount);
    }
    
    // constructor() TaxableToken("TestToken", "testSHARE") {}
    constructor() TaxableToken("CoffinToken", "COFFIN") {}

    event MaxTotalSupplyUpdated(uint256 _newCap);
}
