// SPDX-License-Identifier: MIT
// coffin finance
pragma solidity ^0.8.7;
// pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./CoffinOracle.sol";
import "./PoolToken.sol";
import "./libs/Babylonian.sol";
import './interfaces/ITaxableTokenPolicy.sol';

contract TaxableToken is PoolToken {
    using SafeMath for uint256;
    address public coffinOracle;
    // fixed tax rate
    uint16 public staticTaxRate = 0;
    // latest tax rate
    uint16 public latestTaxRate = 0;
    // Address of the Tax Office
    address public taxOffice;
    // Address of the tax collector wallet
    address public taxCollectorAddress;
    // Tax Policy
    address public policy; 
    // 
    bool public using_twap;
    // Dollar Price threshold below which taxes will get burned
    uint256 public burnThreshold = 0.98e18;
    uint256 public taxThreshold = 1e18;
    //
    bool public taxActivated = false;
    bool public autoCalculateTax = false;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint16 public maxTaxRate = 2000;

    // basis tax rate. 0.05% by default.
    // believe it should be bigger than flashloan fee.
    //  C.R.E.A.M => 0.03% , AAVE => 0.09%.
    uint16 public basisTaxRate = 5;
    uint32 public adjustTaxRateA = 2000000;
    uint32 public adjustTaxRateB = 4;

    mapping(address => bool) private _isExcluded;
    address[] private _excluded;

    // modifier
    modifier onlyOwnerOrTaxOffice() {
        require(
            owner() == msg.sender || taxOffice == msg.sender,
            "Caller is not the owner or the tax office"
        );
        _;
    }

    // constructor
    constructor(string memory _name, string memory _symbol)
        PoolToken(_name, _symbol)
    {}

    // internal

    // get current coUSD price
    function _getCoUSDPrice() public view returns (uint256 _price) {
        if (using_twap) {
            (uint256 __price, uint8 __d) = ICoffinOracle(coffinOracle)
                .getTwapCOUSDUSD();
            _price = __price * (10**(18 - __d));
        } else {
            (uint256 __price, uint8 __d) = ICoffinOracle(coffinOracle)
                .getCOUSDUSD();
            _price = __price * (10**(18 - __d));
        }
    }
    function setTaxPolicy(address _policy) external onlyOwner {
        require(_policy!=address(0), 'wrong tax policy' );
        policy = _policy;
    }
    function calcAutoTaxRate(uint256 _cousdPrice) public view returns (uint16) {
        if (policy==address(0)) {
            return 0;
        }

        return ITaxableTokenPolicy(policy).calcTaxRate(
            _cousdPrice, 
            taxThreshold, 
            adjustTaxRateA, 
            adjustTaxRateB, 
            basisTaxRate,
            maxTaxRate
        );
    }

    function getTaxInfo()
        private
        view
        returns (
            uint16 _currentTaxRate,
            uint16 _staticTaxRate,
            uint256 _burnThreshold,
            uint256 _taxThreshold,
            bool _taxActivated,
            bool _autoCalculateTax,
            uint16 _maxTaxRate,
            uint32 _adjustTaxRateA,
            bool _burnTax,
            uint256 _currentCoUSDPrice,
            uint256 __rawPrice,
            uint8 __rawDecimal,
            uint32 _adjustTaxRateB
        )
    {
        _burnThreshold = burnThreshold;
        _taxThreshold = taxThreshold;
        _taxActivated = taxActivated;
        _autoCalculateTax = autoCalculateTax;
        _maxTaxRate = maxTaxRate;
        _adjustTaxRateA = adjustTaxRateA;
        _staticTaxRate = staticTaxRate;
        (_currentTaxRate, _burnTax, _currentCoUSDPrice) = _getTaxInfo();
        (__rawPrice, __rawDecimal) = ICoffinOracle(coffinOracle).getCOUSDUSD();
        _adjustTaxRateB = adjustTaxRateB;
    }

    function _getTaxInfo()
        private
        view
        returns (
            uint16 currentTaxRate,
            bool burnTax,
            uint256 currentCoUSDPrice
        )
    {
        if (taxActivated) {
            (currentCoUSDPrice) = _getCoUSDPrice();
            if (currentCoUSDPrice > 0 && currentCoUSDPrice < taxThreshold) {
                if (currentCoUSDPrice < burnThreshold) {
                    burnTax = true;
                }
                if (autoCalculateTax) {
                    currentTaxRate = calcAutoTaxRate(currentCoUSDPrice);
                } else {
                    currentTaxRate = staticTaxRate;
                }
            }
        }
    }
    
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        
        (uint16 currentTaxRate, bool burnTax, ) = _getTaxInfo();

        latestTaxRate = currentTaxRate;
        if (
            currentTaxRate == 0 ||
            coffin_pools[sender] ||
            coffin_pools[recipient] ||
            _isExcluded[sender] ||
            _isExcluded[recipient]
        ) {
            super._transfer(sender, recipient, amount);
        } else {
            _transferWithTax(
                sender,
                recipient,
                amount,
                currentTaxRate,
                burnTax
            );
        }
        
    }


    function _transferWithTax(
        address sender,
        address recipient,
        uint256 amount,
        uint16 _taxRate,
        bool burnTax
    ) internal returns (bool) {

        if (_taxRate>maxTaxRate) {
            _taxRate = maxTaxRate;
        }

        uint256 taxAmount = amount.mul(_taxRate).div(10000);
        uint256 amountAfterTax = amount.sub(taxAmount);

        require(taxAmount < amount, "the tax amount should be less than the transferred amount.");

        if (burnTax) {
            // Burn tax
            if (taxAmount>0) {
                super._burn(sender, taxAmount);
            }
        } else {
            // Transfer tax to tax collector
            if (taxAmount>0) {
                super._transfer(sender, taxCollectorAddress, taxAmount);
            }   
        }

        // Transfer amount after tax to recipient
        if (amountAfterTax>0) {
            super._transfer(sender, recipient, amountAfterTax);
        }
        
        return true;
    }

    /********** onlyOwnerOrTaxOffice ************/
    // set coffinOracle
    function setCoffinOracle(address _coffinOracle)
        public
        onlyOwnerOrTaxOffice
    {
        require(
            _coffinOracle != address(0),
            "oracle address cannot be 0 address"
        );
        coffinOracle = _coffinOracle;
    }

    function enableAutoCalculateTax() public onlyOwnerOrTaxOffice {
        autoCalculateTax = true;
    }

    function disableAutoCalculateTax() public onlyOwnerOrTaxOffice {
        autoCalculateTax = false;
    }
    
    function enableTwap() public onlyOwnerOrTaxOffice {
        using_twap = true;
    }

    function disablTwap() public onlyOwnerOrTaxOffice {
        using_twap = false;
    }

    function enableTax() public onlyOwnerOrTaxOffice {
        taxActivated = true;
    }

    function disableTax() public onlyOwnerOrTaxOffice {
        taxActivated = false;
    }

    function setTaxOffice(address _taxOffice) public onlyOwnerOrTaxOffice {
        require(
            _taxOffice != address(0),
            "tax office address cannot be 0 address"
        );
        emit TaxOfficeTransferred(taxOffice, _taxOffice);
        taxOffice = _taxOffice;
    }

    function setTaxCollectorAddress(address _taxCollectorAddress)
        public
        onlyOwnerOrTaxOffice
    {
        require(
            _taxCollectorAddress != address(0),
            "tax collector address must be non-zero address"
        );
        taxCollectorAddress = _taxCollectorAddress;
    }



    function excludeAddressFromTax(address account)
        external
        onlyOwnerOrTaxOffice
        returns (bool)
    {
        require(!_isExcluded[account], "Account is already excluded");
        _isExcluded[account] = true;
        return true;
    }

    function includeAddressInTax(address account)
        external
        onlyOwnerOrTaxOffice
        returns (bool)
    {
        require(_isExcluded[account], "Account is already included");
        _isExcluded[account] = false;
        return true;
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function setTaxThreshold(uint256 _taxThreshold)
        public
        onlyOwnerOrTaxOffice
        returns (bool)
    {
        taxThreshold = _taxThreshold;
        return true;
    }

    function setBurnThreshold(uint256 _burnThreshold)
        public
        onlyOwnerOrTaxOffice
        returns (bool)
    {
        burnThreshold = _burnThreshold;
        return true;
    }

    function setStaticTaxRate(uint16 _staticTaxRate)
        public
        onlyOwnerOrTaxOffice
    {
        require(staticTaxRate < 2500, "Tax rates are too high. ");
        staticTaxRate = _staticTaxRate;
    }

    function setBasisTaxRate(uint16 _basisTaxRate) public onlyOwnerOrTaxOffice {
        require(basisTaxRate < 300, "basis tax rates should be only few. ");
        basisTaxRate = _basisTaxRate;
    }

    function setMaxTaxRate(uint16 _maxTaxRate) public onlyOwnerOrTaxOffice {
        require(_maxTaxRate < 5000, "Tax rates are too high.");
        maxTaxRate = _maxTaxRate;
    }

    function setAdjustTaxRateA(uint32 _adjustTaxRate)
        public
        onlyOwnerOrTaxOffice
    {
        // for adjustmentA
        adjustTaxRateA = _adjustTaxRate;
    }

    function setAdjustTaxRateB(uint32 _adjustTaxRate)
        public
        onlyOwnerOrTaxOffice
    {
        // for adjustmentB
        adjustTaxRateB = _adjustTaxRate;
    }

    event TaxOfficeTransferred(address oldAddress, address newAddress);
}
