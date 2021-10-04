// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IPoolToken.sol";
import "./CoffinOracle.sol";

import "./interfaces/IGatePolicy.sol";
import "./interfaces/IUniswapV2Router.sol";

// import "./interfaces/IGate.sol";
import "./interfaces/ICollateralReserve.sol";
import "./interfaces/IWETH.sol";

contract Gate2 is Ownable, Initializable, ReentrancyGuard {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using Address for address;

    address public oracle;
    address public collateral;
    address public dollar;
    address public policy;
    address public share;

    address public collateralReserve;

    // mapping(address => uint256) public redeem_share_balances;
    // mapping(address => uint256) public redeem_collateral_balances;

    // uint256 public override unclaimed_pool_collateral;
    // uint256 public unclaimed_pool_share;

    // mapping(address => uint256) public last_redeemed;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;

    uint256 private constant COLLATERAL_RATIO_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;
    uint256 private constant LIMIT_SWAP_TIME = 10 minutes;
    
    // for zapmint
    uint256 private constant ZAP_SLIPPAGE_MAX = 100000; // 10%
    uint256 public zap_slippage = 50000;
    // 
    IUniswapV2Router public router;

    // wrapped ftm
    address private wftmAddress = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;

    // Number of decimals needed to get to 18
    uint256 private missing_decimals;

    bool public zapmint_paused = true;
    
    // router address. it's spooky router by default. 
    address routerAddress = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;

        
    /* ========== MODIFIERS ========== */

    modifier notContract() {
        require(!msg.sender.isContract(), "Allow non-contract only");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    function init(
        address _oracle,
        address _dollar,
        address _share,
        address _collateral,
        address _collateralReserve,
        address _policy
    ) external initializer onlyOwner {
        oracle = _oracle;
        dollar = _dollar;
        share = _share;
        collateral = _collateral;
        missing_decimals = 18 - ERC20(_collateral).decimals();
        collateralReserve = _collateralReserve;
        policy = _policy;


        setRouter(routerAddress);
    }

    /* ========== VIEWS ========== */

    function getCollateralPrice() public view  returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getFTMUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }

    function getDollarPrice() public view  returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getCOUSDUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }

    function getCoffinPrice() public view  returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getCOFFINUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }


    /* ========== PUBLIC FUNCTIONS ========== */

    receive() external payable {}

    function rescueFund() external onlyOwner {
        uint256 amount = ERC20(collateral).balanceOf(collateralReserve);
        _requestTransferCollateralFTM(msg.sender, amount);
    }
    

    function zapMint( uint256 _dollar_out_min) external payable notContract nonReentrant {
        require(zapmint_paused == false, "ZapMinting is paused");
        require(msg.value > 0, "need FTM");

        uint256 _collateral_amount = msg.value;
        uint256 _minting_fee = IGatePolicy(policy).minting_fee();
        if (IGatePolicy(policy).using_twap_for_mint()) {
            
        }

        uint256 _share_price = getCoffinPrice();
        uint256 _tcr = IGatePolicy(policy).target_collateral_ratio();

        require(_share_price > 0, "Invalid share price");
        uint256 _price_collateral = getCollateralPrice();

        uint256 _collateral_value = (_collateral_amount * (10**missing_decimals) * _price_collateral) / PRICE_PRECISION;
        uint256 _actual_dollar_amount = _collateral_value - ((_collateral_value * _minting_fee) / PRICE_PRECISION);
        require(_actual_dollar_amount >= _dollar_out_min, "Slippage limit reached");


        // ftm to wftm 
        IWETH(wftmAddress).deposit{value: _collateral_amount}();

        // _transferCollateralToReserve( _collateral_amount);
        if (_tcr < COLLATERAL_RATIO_MAX) {
            uint256 _share_value = (_collateral_value * (RATIO_PRECISION - _tcr)) / RATIO_PRECISION;
            uint256 _min_share_amount 
                = (_share_value * PRICE_PRECISION * (RATIO_PRECISION - zap_slippage)) / _share_price / RATIO_PRECISION;
            uint256 _swap_collateral_amount 
                = (_collateral_amount * (RATIO_PRECISION - _tcr)) / RATIO_PRECISION;
            ERC20(collateral).safeApprove(address(router), 0);
            ERC20(collateral).safeApprove(address(router), _swap_collateral_amount);

            address[] memory router_path = new address[](2);
            router_path[0] = wftmAddress;
            router_path[1] = address(share);
            // uint256[] memory _received_amounts 
            //     = router.swapExactTokensForTokens(_swap_collateral_amount, 
            //         _min_share_amount, router_path, address(this), block.timestamp + LIMIT_SWAP_TIME);
            uint256[] memory _received_amounts 
                = router.swapExactTokensForTokens(_swap_collateral_amount, 
                    _min_share_amount, router_path, address(this), block.timestamp + LIMIT_SWAP_TIME);
            emit ZapSwapped(_swap_collateral_amount, _received_amounts[_received_amounts.length - 1]);
        }
    
        uint256 _balanceShare = ERC20(address(share)).balanceOf(address(this));
        uint256 _balanceCollateral = ERC20(collateral).balanceOf(address(this));
        if (_balanceShare > 0) {
            // ERC20Burnable(address(share)).burn(_balanceShare);

            IPoolToken(share).approve(address(this), _balanceShare);
            IPoolToken(share).pool_burn_from(address(this), _balanceShare);
            
        }
        if (_balanceCollateral > 0) {
            _transferCollateralToReserve( _balanceCollateral);
        }

        IPoolToken(dollar).pool_mint(msg.sender, _actual_dollar_amount);
    }

    // function setRouter(address _router, address[] calldata _path) external onlyOwner {
    function setRouter(address _router) public onlyOwner {
        require(_router != address(0), "Invalid router");
        router = IUniswapV2Router(_router);
        // router_path = _path;
    }



    /* ========== INTERNAL FUNCTIONS ========== */

    // transfer collateral(wftm) from a user to reserve directly by transferFrom.
    function _transferWFTMCollateralToReserve(address _sender, uint256 _amount) internal {
        require(collateralReserve != address(0), "Invalid reserve address");
        ERC20(collateral).safeTransferFrom(_sender, collateralReserve, _amount);
    }

    // transfer collateral(wftm) from the gate to reserve.
    function _transferCollateralToReserve(uint256 _amount) internal {
        require(collateralReserve != address(0), "Invalid reserve address");
        ERC20(collateral).safeTransfer(collateralReserve, _amount);
    }

    // mint share(ERC20) to reserve.
    function _mintShareToCollateralReserve(uint256 _amount) internal {
        require(collateralReserve != address(0), "Invalid reserve address");
        IPoolToken(share).pool_mint(collateralReserve, _amount);
    }

    // transfer collateral(wftm) from reserve to the gate.
    // then convert wftm to ftm, then transfer it to a user.
    function _requestTransferCollateralFTM(address to, uint256 amount) internal {
        require(to != address(0), "Invalid reserve address");
        ICollateralReserve(collateralReserve).transferTo(collateral, address(this), amount);
        IWETH(wftmAddress).withdraw(amount);
        payable(to).transfer(amount);
    }

    // // transfer collateral(wftm) from reserve to a user.
    // function _requestTransferCollateralWrappedFTM(address _receiver, uint256 _amount) internal {
    //     ICollateralReserve(collateralReserve).transferTo(collateral, _receiver, _amount);
    // }

    // // transfer share(ERC20) from reserve to users.
    // function _requestTransferShare(address _receiver, uint256 _amount) internal {
    //     ICollateralReserve(collateralReserve).transferTo(share, _receiver, _amount);
    // }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // function toggleMinting() external onlyOwner {
    //     mint_paused = !mint_paused;
    // }

    // function toggleRedeeming() external onlyOwner {
    //     redeem_paused = !redeem_paused;
    // }

    function toggleZapMinting() external onlyOwner {
        zapmint_paused = !zapmint_paused;
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid address");
        oracle = _oracle;
    }

    // function setTwapOracle(address _oracle_twap) external onlyOwner {
    //     require(_oracle_twap != address(0), "Invalid address");
    //     oracle_twap = _oracle_twap;
    // }

    function setPolicy(address _policy) external onlyOwner {
        require(_policy != address(0), "Invalid address");
        policy = _policy;
    }

    // function getDollarSupply() public view override returns (uint256) {
    //     return IERC20(dollar).totalSupply();
    // }

    // function getCoffinSupply() public view override returns (uint256) {
    //     return IERC20(share).totalSupply();
    // }

    // function globalCollateralValue() public view override returns (uint256) {
    //     return (globalCollateralBalance() * getCollateralPrice() * (10**missing_decimals)) / PRICE_PRECISION;
    // }

    // function globalCollateralBalance() public view override returns (uint256) {
    //     uint256 _collateralReserveBalance = IERC20(collateral).balanceOf(collateralReserve);
    //     return _collateralReserveBalance - unclaimed_pool_collateral;
    // }

    function setCollateralReserve(address _collateralReserve) public onlyOwner {
        require(_collateralReserve != address(0), "invalidAddress");
        collateralReserve = _collateralReserve;
    }

    // function getCollateralBalance() public view override returns (uint256) {
    //     return IERC20(collateral).balanceOf(collateralReserve);
    // }

    function setZapSlippage(uint256 _zap_slippage) external onlyOwner {
        require(_zap_slippage <= ZAP_SLIPPAGE_MAX, "ZAP SLIPPAGE TOO HIGH");
        zap_slippage = _zap_slippage;
    }

    event ZapSwapped(uint256 indexed collateralAmount, uint256 indexed shareAmount);

}
