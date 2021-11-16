// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/ITaxableTokenPolicy.sol";

contract TaxableTokenPolicy is Ownable, ITaxableTokenPolicy {
    using SafeMath for uint256;

    function calcTaxRate(
        uint256 dollarPrice, 
        uint256 taxThreshold, 
        uint256 paramA, 
        uint256 paramB, 
        uint256 basisTaxRate,
        uint256 maxTaxRate
    ) public pure override returns (uint16) {
        if (dollarPrice < taxThreshold) {
            uint256 diff = taxThreshold.sub(dollarPrice);
            // diff^2 / (paramB)^2 * paramA + basisTaxRate
            uint256 taxRate = diff.div(paramB)
                .mul(diff.div(paramB))
                .div(10**18);
            taxRate =taxRate
                .mul(paramA)
                .div(10**18)
                .add(basisTaxRate);
            if (taxRate > maxTaxRate) {
                return uint16(maxTaxRate);
            }
            return uint16(taxRate);
        }
        return 0;
    }
}
