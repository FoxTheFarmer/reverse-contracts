// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapLP.sol";
import "./libs/FixedPoint.sol";
import "./interfaces/IBandStdReference.sol";


interface ICoffinOracle {
    function PERIOD() external view returns (uint32);
    function getCOFFINUSD() external view returns (uint256, uint8);
    function updateTwap(address token0, address token1) external ;
    function getCOUSDUSD() external view returns (uint256, uint8);
    function getTwapCOUSDUSD() external view returns (uint256, uint8);
    function getTwapCOFFINUSD() external view returns (uint256, uint8);
    function getTwapXCOFFINUSD() external view returns (uint256, uint8);
    function updateTwapDollar() external ;
    function updateTwapCoffin() external ;
    function updateTwapXCoffin() external ;
    function getXCOFFINUSD() external view returns (uint256, uint8);
    function getCOUSDFTM() external view returns (uint256, uint8);
    function getXCOFFINFTM() external view returns (uint256, uint8);
    function getCOFFINFTM() external view returns (uint256, uint8);
    function getFTMUSD() external view returns (uint256, uint8);

}

contract MockCoffinOracle is ICoffinOracle, Ownable {
    uint256 public xcoffinftm = (1 / 2) * 1 * 10**18;
    uint256 public coffinftm = 2 * 1 * 10**18;
    uint256 public ftmusd = (1 / 4) * 1 * 10**18;
    uint256 public cousdftm = (101 / 100) * 4 * 1 * 10**18;
    uint32 public override PERIOD = 600; // 10-minute TWAP 

    function updateTwap(address token0, address token1) external override {

    }
    function updateTwapDollar() external override{

    }
    function updateTwapCoffin() external override{

    }
    function updateTwapXCoffin() external override{

    }
    function setCOUSDFTM(uint256 val) external {
        cousdftm = val;
    }

    function getCOUSDFTM() public view override returns (uint256, uint8) {
        return (cousdftm, 18);
    }

    function setXCOFFINFTM(uint256 val) external {
        xcoffinftm = val;
    }

    function getXCOFFINFTM() public view override returns (uint256, uint8) {
        return (xcoffinftm, 18);
    }

    function setCOFFINFTM(uint256 val) external {
        coffinftm = val;
    }

    function getCOFFINFTM() public view override returns (uint256, uint8) {
        return (coffinftm, 18);
    }

 
    uint256 public cousdusd = 1030000000000000000;
    function setCOUSDUSD(uint256 val) external {
        cousdusd = val;// decimal 18 
    }
    function getCOUSDUSD() public view override returns(uint256,uint8){
        return (cousdusd,18);// decimal 18 
    }
    
 
    
    function setFTMUSD(uint256 val) external {
        ftmusd = val;
    }

    function getFTMUSD() public view override returns (uint256, uint8) {
        return (ftmusd, 18);
    }


    function getCOFFINUSD() public view override returns (uint256, uint8) {
        (uint256 v1, uint8 d1) = getCOFFINFTM();
        (uint256 v2, uint8 d2) = getFTMUSD();
        return ((v1 * v2) / (10**d1), d2);
    }

    function getXCOFFINUSD() public view override returns (uint256, uint8) {
        (uint256 v1, uint8 d1) = getXCOFFINFTM();
        (uint256 v2, uint8 d2) = getFTMUSD();
        return ((v1 * v2) / (10**d1), d2);
    }

    function getTwapCOUSDUSD() external view override returns (uint256, uint8){
        return getCOUSDUSD();
    }
    function getTwapCOFFINUSD() external view override returns (uint256, uint8){
        return getCOFFINUSD();
    }
    function getTwapXCOFFINUSD() external view override returns (uint256, uint8){
        return getXCOFFINUSD();
    }

}


contract CoffinOracle is ICoffinOracle, Initializable,Ownable {
    using SafeMath for uint256;
    using FixedPoint for *;

    IUniswapV2Router02 public uniswapv2router;
    address public coffin;
    address public dollar;
    address public xcoffin;
    address public wftm = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
    address public boo = 0x841FAD6EAe12c286d1Fd18d1d525DFfA75C7EFFE;
    IBandStdReference bandRef;
    uint32 public override PERIOD = 600; // 10-minute TWAP

    struct Pair {
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
        bool initialized;
    }

    mapping(address => Pair) public getPair;

    function setPeriod(uint32 _period) external onlyOwner {
        PERIOD = _period;
    }

    function init(
        address _coffinAddress,
        address _cousdAddress,
        address _xcoffinAddress
    ) external  initializer onlyOwner{
        // router address. it's spooky router by default. 
        address routerAddress = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
        setRouter(routerAddress);

        address fantomBandProtocol = 0x56E2898E0ceFF0D1222827759B56B28Ad812f92F;

        setBandOracle(fantomBandProtocol);
        setCOFFINAddress(_coffinAddress);
        setDollarAddress(_cousdAddress);
        setXCOFFINAddress(_xcoffinAddress);
    }

    function getBandRate(string memory token0, string memory token1)
        public
        view
        returns (uint256)
    {
        IBandStdReference.ReferenceData memory data = bandRef.getReferenceData(
            token0,
            token1
        );
        return data.rate;
    }


    function getFTMUSD() public view override returns (uint256, uint8) {
        return (getBandRate("FTM","USD"), 18);
    }

    



    function setCOFFINAddress(address _coffinAddress) public onlyOwner {
        coffin = _coffinAddress;
    }

    function setXCOFFINAddress(address _xcoffinAddress) public onlyOwner {
        xcoffin = _xcoffinAddress;
    }

    function setDollarAddress(address _cousdAddress) public onlyOwner {
        dollar = _cousdAddress;
    }

    function setRouter(address _uniswapv2routeraddress)
        public
        onlyOwner
    {
        uniswapv2router = IUniswapV2Router02(_uniswapv2routeraddress);
    }

    function setBandOracle(address _bandOracleAddress) public onlyOwner {
        bandRef = IBandStdReference(_bandOracleAddress);
    }


    function getCOFFINUSD() external view override returns (uint256, uint8) {
        (uint256 v1, uint8 d1) = getCOFFINFTM();
        (uint256 v2, uint8 d2) = getFTMUSD();
        return ((v1 * v2) / (10**d1), d2);
    }

    function getTwapCOFFINUSD() external view override returns (uint256, uint8) {
        (uint256 v1, uint8 d1) = getTwapCOFFINFTM();
        (uint256 v2, uint8 d2) = getFTMUSD();
        return ((v1 * v2) / (10**d1), d2);
    }
    
    function getUSDCUSD() public view  returns (uint256, uint8) {
        return (getBandRate("USDC","USD"), 18);
    }
    function getDAIUSD() public view  returns (uint256, uint8) {
        return (getBandRate("DAI","USD"), 18);
    }
    
    uint8 public oracleMode = 0; 

    function enableFTMOracle() external onlyOwner {
        oracleMode = 1;
    }
    function enableDAIOracle() external onlyOwner {
        oracleMode = 2 ;
    }
    function enableUSDCracle() external onlyOwner {
        oracleMode = 0 ;
    }

    function getCOUSDUSD() external view override returns (uint256, uint8) {
        if (oracleMode==1) {
            (uint256 v1, uint8 d1) = getCOUSDFTM();
            (uint256 v2, uint8 d2) = getFTMUSD();
            return ((v1 * v2) / (10**d1), d2);
        } else if (oracleMode==2) {
            (uint256 v1, uint8 d1) = getCOUSDDAI();
            (uint256 v2, uint8 d2) = getDAIUSD();
            return ((v1 * v2) / (10**d1), d2);
        } else {
            (uint256 v1, uint8 d1) = getCOUSDUSDC();
            (uint256 v2, uint8 d2) = getUSDCUSD();
            return ((v1 * v2) / (10**d1), d2);
        }
    }

    function getTwapCOUSDUSD() external view override returns (uint256, uint8) {
        if (oracleMode==1) {
            (uint256 v1, uint8 d1) = getTwapCOUSDFTM();
            (uint256 v2, uint8 d2) = getFTMUSD();
            return ((v1 * v2) / (10**d1), d2);
        } else if (oracleMode==2) {   
            (uint256 v1, uint8 d1) = getTwapCOUSDDAI();
            (uint256 v2, uint8 d2) = getDAIUSD();
            return ((v1 * v2) / (10**d1), d2);
        } else {
            (uint256 v1, uint8 d1) = getTwapCOUSDUSDC();
            (uint256 v2, uint8 d2) = getUSDCUSD();
            return ((v1 * v2) / (10**d1), d2);     
        }

    }

    
    


    function getXCOFFINUSD() external view override returns (uint256, uint8) {
        (uint256 v1, uint8 d1) = getXCOFFINFTM();
        (uint256 v2, uint8 d2) = getFTMUSD();
        return ((v1 * v2) / (10**d1), d2);
    }

    function getTwapXCOFFINUSD() external view override returns (uint256, uint8) {
        (uint256 v1, uint8 d1) = getTwapXCOFFINFTM();
        (uint256 v2, uint8 d2) = getFTMUSD();
        return ((v1 * v2) / (10**d1), d2);
    }

    function getTwapCOUSDFTM() public view  returns (uint256, uint8) {
        (uint256 a, uint8 b) = getTwapRate(dollar,wftm);
        if (a>0) {
            return (a,b);
        }
        return getRealtimeRate(dollar,wftm);
    }
    
    function getTwapCOUSDDAI() public view  returns (uint256, uint8) {
        (uint256 a, uint8 b) = getTwapRate(dollar,dai);
        if (a>0) {
            return (a,b);
        }
        return getRealtimeRate(dollar,usdc);
    }
    function getTwapCOUSDUSDC() public view  returns (uint256, uint8) {
        (uint256 a, uint8 b) = getTwapRate(dollar,usdc);
        if (a>0) {
            return (a,b);
        }
        return getRealtimeRate(dollar,usdc);
    }
    
    function getCOUSDFTM() public view override returns (uint256, uint8) {
        return getRealtimeRate(dollar,wftm);
    }
    function getCOUSDUSDC() public view returns (uint256, uint8) {
        return getRealtimeRate(dollar,usdc);
    }
    function getCOUSDDAI() public view returns (uint256, uint8) {
        return getRealtimeRate(dollar,dai);
    }
    

    function getTwapXCOFFINFTM() public view  returns (uint256, uint8) {
        (uint256 a, uint8 b) = getTwapRate(xcoffin,wftm);
        if (a>0) {
            return (a,b);
        }
        return getRealtimeRate(xcoffin,wftm);
    }

    function getXCOFFINFTM() public view override returns (uint256, uint8) {
        return getRealtimeRate(xcoffin,wftm);
    }

    function getTwapCOFFINFTM() public view returns (uint256, uint8) {
        (uint256 a, uint8 b) = getTwapRate(coffin,wftm);
        if (a>0) {
            return (a,b);
        }
        return getRealtimeRate(coffin,wftm);
    }
    function getCOFFINFTM() public view override returns (uint256, uint8) {
        return getRealtimeRate(coffin,wftm);
    }


    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2**32);
    }

    function currentCumulativePrices(address uniswapV2Pair)
        internal
        view
        returns (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        )
    {
        // Pair storage pairStorage = getPair[uniswapV2Pair];

        blockTimestamp = currentBlockTimestamp();
        IUniswapLP uniswapPair = IUniswapLP(uniswapV2Pair);
        price0Cumulative = uniswapPair.price0CumulativeLast();
        price1Cumulative = uniswapPair.price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 _blockTimestampLast) = uniswapPair.getReserves();
        if (_blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - _blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint256(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint256(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }


    function getTwapRate(address token0, address token1)
        public
        view
        returns (uint256 priceLatest, uint8 decimals)
    {
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        address factory = address(uniswapv2router.factory());
        address uniswapV2Pair = IUniswapV2Factory(factory).getPair(token0, token1);

        if (uniswapV2Pair== address(0)) {
            return (0,0);
        } 

        // Pair memory pair = getPair[uniswapV2Pair];
        Pair storage pairStorage = getPair[uniswapV2Pair];

        // require(pairStorage.initialized, "need to setup first");
        if (!pairStorage.initialized) {
            return getRealtimeRate(token0, token1);
            // return (0,0);
        }
        
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = currentCumulativePrices(
            address(uniswapV2Pair)
        );
        uint32 timeElapsed = blockTimestamp - pairStorage.blockTimestampLast; // Overflow is desired

        FixedPoint.uq112x112 memory price0Average 
            = FixedPoint.uq112x112(uint224((price0Cumulative - pairStorage.price0CumulativeLast) / timeElapsed));
        FixedPoint.uq112x112 memory price1Average 
            = FixedPoint.uq112x112(uint224((price1Cumulative - pairStorage.price1CumulativeLast) / timeElapsed));

        uint256 amountIn = 1e18;
        if (IUniswapLP(uniswapV2Pair).token0() == token0) {
            priceLatest = uint256(price0Average.mul(amountIn).decode144());
            decimals = ERC20(token1).decimals();
        } else {
            require(IUniswapLP(uniswapV2Pair).token0() == token1, "TwapOracle: INVALID_TOKEN");
            priceLatest = uint256(price1Average.mul(amountIn).decode144());
            decimals = ERC20(token0).decimals();
        }
    }

    function getTwapRateWithUpdate(address token0, address token1)
        external
        returns (uint256 priceLatest, uint8 decimals)
    {
        updateTwap(token0,token1);
        return getTwapRate(token0,token1);
    }
    

    function updateTwapDollarFTM() public  {
        updateTwap(dollar, wftm);
    }
    function updateTwapDollar() public override {
        updateTwap(dollar, dai);
    }
    function updateTwapDollarUSDC() public  {
        updateTwap(dollar, usdc);
    }
    function updateTwapCoffin() public override {
        updateTwap(coffin, wftm);
    }
    function updateTwapXCoffin() public override {
        updateTwap(xcoffin, wftm);
    }

    function updateTwap(address token0, address token1) public override {

        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        address factory = address(uniswapv2router.factory());
        address uniswapV2Pair = IUniswapV2Factory(factory).getPair(token0, token1);

        if (uniswapV2Pair== address(0)) {
            return;
        }
        Pair storage pairStorage = getPair[uniswapV2Pair];
        // require(pairStorage.initialized, "need to setup first");
        
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = currentCumulativePrices(
            address(uniswapV2Pair)
        );

        if (!pairStorage.initialized) {
            // first time 
            pairStorage.price0CumulativeLast = price0Cumulative;
            pairStorage.price1CumulativeLast = price1Cumulative;
            pairStorage.blockTimestampLast = blockTimestamp;
            pairStorage.initialized = true;
            return;
        }

        // Overflow is desired
        uint32 timeElapsed = blockTimestamp - pairStorage.blockTimestampLast; 
        
        // Ensure that at least one full period has passed since the last update
        if (timeElapsed < PERIOD) {
            return ;
        }
        
        pairStorage.price0Average 
            = FixedPoint.uq112x112(uint224((price0Cumulative - pairStorage.price0CumulativeLast) / timeElapsed));
        pairStorage.price1Average 
            = FixedPoint.uq112x112(uint224((price1Cumulative - pairStorage.price1CumulativeLast) / timeElapsed));
        pairStorage.price0CumulativeLast = price0Cumulative;
        pairStorage.price1CumulativeLast = price1Cumulative;
        pairStorage.blockTimestampLast = blockTimestamp;
    }

    function getRealtimeRate(address tokenA, address tokenB)
        public
        view
        returns (uint256 priceLatest, uint8 decimals)
    {

        address factory = address(uniswapv2router.factory());
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        if (pair== address(0)) {
            return (0,0);
        }
        
        (uint112 reserve0, uint112 reserve1,) =
            IUniswapLP(pair).getReserves();
        if (IUniswapLP(pair).token0()==address(tokenA)) {
            priceLatest = uint256(reserve1).mul(uint256(10**ERC20(tokenA).decimals())).div(uint256(reserve0));
            decimals = ERC20(tokenB).decimals();
        } else {
            priceLatest = uint256(reserve0).mul(uint256(10**ERC20(tokenA).decimals())).div(uint256(reserve1));
            decimals = ERC20(tokenB).decimals();
        }

        if ((18-decimals)>0) { 
            priceLatest = priceLatest.mul(10**(18-decimals));
            decimals = 18;
        }
    }
}


