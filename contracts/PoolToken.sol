// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract PoolToken is ERC20Burnable , Ownable{
    using SafeMath for uint256;

    // The addresses in this array are added by the oracle and these contracts are able to mint coffin
    address[] public coffin_pools_array;

    // Mapping is also used for faster verification
    mapping(address => bool) public coffin_pools; 

    /* ========== MODIFIERS ========== */

    modifier onlyPools() {
        require(coffin_pools[msg.sender] == true, "Only coffin pools can call this function");
        _;
    }
    

    modifier onlyByOwnerOrPool() {
        require(
            msg.sender == owner()
            || coffin_pools[msg.sender] == true, 
            "You are not the owner, or a pool");
        _;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /* ========== constructor ========== */
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}
    /* ========== view ========== */
    function poolLength() view public returns(uint256) {
        return coffin_pools_array.length;
    }

    /* ========== onlyPools ========== */

    // Used by pools when user redeems
    function pool_burn_from(address addr, uint256 amount) public onlyPools {
        super.burnFrom(addr, amount);
        emit Burned(addr, msg.sender, amount);
    }
    // This function is what other pools will call to mint new token 
    function pool_mint(address addr, uint256 amount) public onlyPools {
        super._mint(addr, amount);
        emit Minted(msg.sender, addr, amount);
    }

    /* ========== onlyOwner  ========== */

    // 
    function burnFrom(address addr, uint256 amount) public override onlyOwner {
        super.burnFrom(addr, amount);
        emit Minted(msg.sender, addr, amount);
    }
    
    // pools which can mint/burn 
    function addPool(address pool_address) public onlyOwner {
        require(pool_address != address(0), "Zero address detected");

        require(coffin_pools[pool_address] == false, "Address already exists");
        coffin_pools[pool_address] = true; 
        coffin_pools_array.push(pool_address);

        emit PoolAdded(pool_address);
    }

    // Remove a pool 
    function removePool(address pool_address) public onlyOwner {
        require(pool_address != address(0), "Zero address detected");
        require(coffin_pools[pool_address] == true, "Address nonexistant");
        
        // Delete from the mapping
        delete coffin_pools[pool_address];

        // 'Delete' from the array by setting the address to 0x0
        for (uint i = 0; i < coffin_pools_array.length; i++){ 
            if (coffin_pools_array[i] == pool_address) {
                coffin_pools_array[i] = address(0); // This will leave a null in the array and keep the indices the same
                break;
            }
        }

        emit PoolRemoved(pool_address);
    }

    /* ========== EVENTS ========== */


    event Burned(address indexed from, address indexed by, uint256 amount);
    event Minted(address indexed from, address indexed to, uint256 amount);
    event PoolAdded(address pool_address);
    event PoolRemoved(address pool_address);

}
