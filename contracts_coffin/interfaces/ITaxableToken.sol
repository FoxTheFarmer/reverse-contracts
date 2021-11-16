
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
interface ITaxableToken {
    function enableTax() external;

    function disableTax() external;

    function enableAutoCalculateTax() external;

    function disableAutoCalculateTax() external;

    function setTaxCollectorAddress(address _taxCollectorAddress) external;

    function setTaxThreshold(uint256 _taxThreshold) external;

    function setBurnThreshold(uint256 _burnThreshold) external;

    function setBasisTaxRate(uint16 _val) external;

    function enableTwap() external;
    
    function disablTwap() external ;

    function includeAddressInTax(address _address) external returns (bool);

    function excludeAddressFromTax(address _address) external returns (bool);

    function isExcluded(address _address) external view returns (bool);

    function setCoffinOracle(address _coffinOracle) external;

    function setStaticTaxRate(uint16 _staticTaxRate) external;

    function setTaxOffice(address _taxOffice) external;

    function setAdjustTaxRateA(uint32 _adjustTaxRate) external;
    function setAdjustTaxRateB(uint32 _adjustTaxRate) external;

    function setMaxTaxRate(uint16 _maxTaxRate) external;
    function latestTaxRate() view external returns(uint16);

}