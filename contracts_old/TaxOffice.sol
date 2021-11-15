// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITaxableToken.sol";
import "./interfaces/IUniswapV2Router02.sol";

contract TaxOffice is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public coffin;
    address public wftm = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public uniRouter = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);
    mapping(address => bool) public taxExclusionEnabled;

    function setCoffin(address _coffin) external onlyOwner {
        require(_coffin!=address(0), "coffin address error ");
        coffin = _coffin;
    }

    function setUniRouter(address _uniRouter) external onlyOwner {
        require(_uniRouter!=address(0), "coffin address error ");
        uniRouter = _uniRouter;
    }
    

    function enableAutoCalculateTax() public onlyOwner {
        ITaxableToken(coffin).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOwner {
        ITaxableToken(coffin).disableAutoCalculateTax();
    }

    function setTaxThreshold(uint256 _taxThreshold)
        public
        onlyOwner
    {
        ITaxableToken(coffin).setTaxThreshold(_taxThreshold);
    }

    function setBurnThreshold(uint256 _burnThreshold)
        public
        onlyOwner
    {
        ITaxableToken(coffin).setBurnThreshold(_burnThreshold);
    }

    function setBasisTaxRate(uint16 _val) public onlyOwner {
        ITaxableToken(coffin).setBasisTaxRate(_val);
    }

    function setTaxCollectorAddress(
        address _taxCollectorAddress
    ) public onlyOwner {
        ITaxableToken(coffin).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address)
        external
        onlyOwner
        returns (bool)
    {
        // return ITaxableToken(coffin).excludeAddressFromTax(_address);
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxableToken(coffin).isExcluded(_address)) {
            // update 
            return ITaxableToken(coffin).excludeAddressFromTax(_address);
        }
        return false; // already 
    }
    function includeAddressInTax(address _address)
        external
        onlyOwner
        returns (bool)
    {
        // return ITaxableToken(coffin).includeAddressInTax(_address);
        return _includeAddressInTax(_address);
    }
    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxableToken(coffin).isExcluded(_address)) {
            return ITaxableToken(coffin).includeAddressInTax(_address);
        }
        return false; // already
    }

    function isExcluded(address _address)
        public
        view
        onlyOwner
        returns (bool)
    {
        return ITaxableToken(coffin).isExcluded(_address);
    }


    function taxRate() external view returns (uint16) {
        return ITaxableToken(coffin).latestTaxRate();
    }

    function enableTwap() public onlyOwner {
        ITaxableToken(coffin).enableTwap();
    }

    function disablTwap() public onlyOwner {
        ITaxableToken(coffin).disablTwap();
    }

    function enableTax() public onlyOwner {
        ITaxableToken(coffin).enableTax();
    }

    function disableTax() public onlyOwner {
        ITaxableToken(coffin).disableTax();
    }

    function setCoffinOracle(address _coffinOracle)
        external
        onlyOwner
    {
        ITaxableToken(coffin).setCoffinOracle(_coffinOracle);
    }

    function transferTaxOffice(address _newTaxOffice)
        external
        onlyOwner
    {
        ITaxableToken(coffin).setTaxOffice(_newTaxOffice);
    }

    function setAdjustTaxRateA(uint32 _adjustTaxRate)
        external
        onlyOwner
    {
        ITaxableToken(coffin).setAdjustTaxRateA(_adjustTaxRate);
    }
    function setAdjustTaxRateB(uint32 _adjustTaxRate)
        external
        onlyOwner
    {
        ITaxableToken(coffin).setAdjustTaxRateB(_adjustTaxRate);
    }

    function setStaticTaxRate(uint16 _staticTaxRate)
        external
        onlyOwner
    {
        ITaxableToken(coffin).setStaticTaxRate(_staticTaxRate);
    }

    function setMaxTaxRate(uint16 _maxTaxRate)
        external
        onlyOwner
    {
        ITaxableToken(coffin).setMaxTaxRate(_maxTaxRate);
    }

    function rescueFund(IERC20 _token, address _to) external onlyOwner {
        IERC20(_token).safeTransfer(
            _to,
            IERC20(_token).balanceOf(address(this))
        );
    }
    
    function addLiquidityTaxFree(
        address token,
        uint256 amtCoffin,
        uint256 amtToken,
        uint256 amtCoffinMin,
        uint256 amtTokenMin,
        uint256 deadline
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtCoffin != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(coffin).transferFrom(msg.sender, address(this), amtCoffin);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(coffin, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtCoffin;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtCoffin, resultAmtToken, liquidity) = IUniswapV2Router02(uniRouter).addLiquidity(
            coffin,
            token,
            amtCoffin,
            amtToken,
            amtCoffinMin,
            amtTokenMin,
            msg.sender,
            deadline // block.timestamp
        );

        if(amtCoffin.sub(resultAmtCoffin) > 0) {
            IERC20(coffin).transfer(msg.sender, amtCoffin.sub(resultAmtCoffin));
        }
        if(amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtCoffin, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtCoffin,
        uint256 amtCoffinMin,
        uint256 amtFtmMin,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtCoffin != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(coffin).transferFrom(msg.sender, address(this), amtCoffin);
        _approveTokenIfNeeded(coffin, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtCoffin;
        uint256 resultAmtFtm;
        uint256 liquidity;
        (resultAmtCoffin, resultAmtFtm, liquidity) = IUniswapV2Router02(uniRouter).addLiquidityETH{value: msg.value}(
            coffin,
            amtCoffin,
            amtCoffinMin,
            amtFtmMin,
            msg.sender,
            deadline // block.timestamp
        );

        if(amtCoffin.sub(resultAmtCoffin) > 0) {
            IERC20(coffin).transfer(msg.sender, amtCoffin.sub(resultAmtCoffin));
        }
        return (resultAmtCoffin, resultAmtFtm, liquidity);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(taxExclusionEnabled[msg.sender], "Address not approved for tax free transfers");
        _excludeAddressFromTax(_sender);
        IERC20(coffin).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded) external onlyOwner {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}
