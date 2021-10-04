// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

    
interface ITaxableTokenPolicy  {
    function calcTaxRate(
        uint256 dollarPrice, 
        uint256 taxThreshold, 
        uint256 paramA, 
        uint256 paramB, 
        uint256 basisTaxRate,
        uint256 maxTaxRate
    ) external pure returns (uint16) ;
    }
