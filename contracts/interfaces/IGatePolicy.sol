// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

interface IGatePolicy {
    function target_collateral_ratio() external view returns (uint256);
    function redemption_delay() external view returns (uint256);
    // function effective_collateral_ratio() external view returns (uint256);
    function getEffectiveCollateralRatio() external view returns (uint256); 
    function refreshCollateralRatio(bool noerror) external  ; 
    function redemption_fee() external view returns (uint256); 
    function extra_redemption_fee() external view returns (uint256); 
    function minting_fee() external view returns (uint256); 
    function price_target() external view returns (uint256); 
    function using_twap_for_redeem() external view returns (bool); 
    function using_twap_for_mint() external view returns (bool); 
    function using_twap_for_tcr() external view returns (bool); 
    
}
