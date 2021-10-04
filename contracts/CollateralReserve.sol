// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ICollateralReserve.sol";

contract CollateralReserve is Ownable, ICollateralReserve {
    using SafeERC20 for IERC20;

    // CONTRACTS
    address public gate;
    
    //wftm
    address wftm = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;

    /* ========== MODIFIER ========== */

    modifier onlyOwnerOrGate() {
        require(owner() == msg.sender || gate == msg.sender, "Only gate or owner can trigger this function");
        _;
    }
    
    /* ========== VIEWS ================ */

    function fundBalance(address _token) public view override returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function transferWftmTO(
        address _receiver,
        uint256 _amount
    ) public onlyOwnerOrGate {
        transferTo(wftm, _receiver, _amount);
    }

    function transferTo(
        address _token,
        address _receiver,
        uint256 _amount
    ) public override onlyOwnerOrGate {
        require(_receiver != address(0), "Invalid address");
        require(_amount > 0, "Cannot transfer zero amount");
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit Transfer(msg.sender, _token, _receiver, _amount);
    }

    function setGate(address _gate) public onlyOwner {
        require(_gate != address(0), "Invalid address");
        gate = _gate;
        emit GateChanged(_gate);
    }
    event GateChanged(address indexed _gate);
    event Transfer(address se, address indexed token, address indexed receiver, uint256 amount);
}
