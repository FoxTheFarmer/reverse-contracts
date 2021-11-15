// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./PoolToken.sol";

contract Dollar is PoolToken, Initializable {
    using SafeMath for uint256;

    // uint256 public constant genesis_supply = 5000 ether; // for initial calculation.
    uint256 public constant genesis_supply = 10 ether; // for initial calculation.

    /* ========== Initialize ========== */
    // constructor() PoolToken("coUSD", "Coffin Dollar") {}
    // constructor() PoolToken("testDollar", "testDollar") {}
    constructor() PoolToken("CoffinDollar", "CoUSD") {}

    function init(address _gate) external initializer onlyOwner {
        // same with addPool
        coffin_pools_array.push(_gate);
        coffin_pools[_gate] = true;
        if (genesis_supply > 0) {
            _mint(msg.sender, genesis_supply);
        }
    }
}
