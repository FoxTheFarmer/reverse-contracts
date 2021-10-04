// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;


interface IGate {

    function unclaimed_pool_collateral() external view returns (uint256);


    function globalCollateralValue() external view returns (uint256) ;

    function getCollateralPrice() external view returns (uint256);
    function getDollarPrice() external view returns (uint256) ;
    function getCoffinPrice() external view returns (uint256) ;

    // function getCollateralTwap() external view returns (uint256);
    function getDollarTwap() external view returns (uint256) ;
    function getCoffinTwap() external view returns (uint256) ;

    
    function getDollarSupply() external view returns (uint256) ;

    function getCoffinSupply() external view returns (uint256) ;

    function globalCollateralBalance() external view returns (uint256);

    function getCollateralBalance() external view returns (uint256);

}