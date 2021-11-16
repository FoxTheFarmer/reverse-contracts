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

import "./interfaces/IGate.sol";
import "./interfaces/ICollateralReserve.sol";
import "./interfaces/IWETH.sol";

contract Gate is Ownable, Initializable, IGate, ReentrancyGuard {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using Address for address;

    address public oracle;
    address public collateral;
    address public dollar;
    address public policy;
    address public share;

    address public collateralReserve;

    mapping(address => uint256) public redeem_share_balances;
    mapping(address => uint256) public redeem_collateral_balances;

    uint256 public override unclaimed_pool_collateral;
    uint256 public unclaimed_pool_share;

    mapping(address => uint256) public last_redeemed;

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;

    uint256 private constant COLLATERAL_RATIO_PRECISION = 1e6;
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;
    uint256 private constant LIMIT_SWAP_TIME = 10 minutes;
    
    // 

    // wrapped ftm
    address private wftmAddress = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;

    uint256 private missing_decimals;

    // AccessControl state variables
    bool public mint_paused = false;
    bool public redeem_paused = false;
    
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
    }

    /* ========== VIEWS ========== */

    function getCollateralPrice() public view override returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getFTMUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }

    function getDollarPrice() public view override returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getCOUSDUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }

    function getCoffinPrice() public view override returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getCOFFINUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }


    // function getCollateralTwap() public view override returns (uint256) {
    //     (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getTwapFTMUSD();
    //     return __price.mul(PRICE_PRECISION).div(10**__d);
    // }

    function getDollarTwap() public view override returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getTwapCOUSDUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }

    function getCoffinTwap() public view override returns (uint256) {
        (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getTwapCOFFINUSD();
        return __price.mul(PRICE_PRECISION).div(10**__d);
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function gateInfo()
        public
        view
        returns (
            uint256 _minting_fee,
            uint256 _redemption_fee,
            uint256 _ex_red_fee,
            uint256 _collateral_price,
            uint256 _share_price,
            uint256 _dollar_price,
            uint256 _share_twap,
            uint256 _dollar_twap,
            // uint256 _ecr,
            uint256 _tcr,
            bool _mint_paused,
            bool _redeem_paused,
            uint256 _unclaimed_pool_collateral,
            uint256 _unclaimed_pool_share
        )
    {
        _minting_fee = IGatePolicy(policy).minting_fee();
        _redemption_fee = IGatePolicy(policy).redemption_fee();
        _ex_red_fee = IGatePolicy(policy).extra_redemption_fee();
        _collateral_price = getCollateralPrice();
        _share_price = getCoffinPrice();
        _dollar_price = getDollarPrice();
        _share_twap = getCoffinTwap();
        _dollar_twap = getDollarTwap();

        _tcr = IGatePolicy(policy).target_collateral_ratio();
        // _ecr = IGatePolicy(policy).getEffectiveCollateralRatio();

        _mint_paused = mint_paused;
        _redeem_paused = redeem_paused;

        _unclaimed_pool_collateral = unclaimed_pool_collateral;
        _unclaimed_pool_share = unclaimed_pool_share;

    }

    // function setWFTMAddress(address adr) external onlyOwner {
    //     wftmAddress = adr;
    // }

    receive() external payable {}

    function rescueFund() external onlyOwner {
        uint256 amount = ERC20(collateral).balanceOf(collateralReserve);
        _requestTransferCollateralFTM(msg.sender, amount);
    }

    function redeem(
        uint256 _dollar_amount,
        uint256 _share_out_min,
        uint256 _collateral_out_min
    ) external nonReentrant {
        uint256 _share_price = 0;
        uint256 _dollar_price = 0;
        if (IGatePolicy(policy).using_twap_for_redeem()) { 
            _share_price = getCoffinTwap();
            _dollar_price = getDollarTwap();
        }
        if (_share_price==0 ) {
            _share_price = getCoffinPrice();
        }
        if (_dollar_price==0) {
            _dollar_price = getDollarPrice();
        }

        uint256 _redemption_fee = IGatePolicy(policy).redemption_fee();
        uint256 extra_redemption_fee = IGatePolicy(policy).extra_redemption_fee();
        uint256 price_target = IGatePolicy(policy).price_target();

        // uint256 _redemption_fee = redemption_fee;
        if (_dollar_price < price_target) {
            _redemption_fee += extra_redemption_fee;
        }

        uint256 _ecr = IGatePolicy(policy).getEffectiveCollateralRatio();

        uint256 _collateral_price = getCollateralPrice();
        require(_collateral_price > 0, "Invalid collateral price");
        require(_share_price > 0, "Invalid share price");
        uint256 _dollar_amount_post_fee = _dollar_amount - ((_dollar_amount * _redemption_fee) / PRICE_PRECISION);
        uint256 _collateral_output_amount = 0;
        uint256 _share_output_amount = 0;

        if (_ecr < COLLATERAL_RATIO_MAX) {
            uint256 _share_output_value 
                = _dollar_amount_post_fee - ((_dollar_amount_post_fee * _ecr) / PRICE_PRECISION);
            _share_output_amount 
                = (_share_output_value * PRICE_PRECISION) / _share_price;
        }

        if (_ecr > 0) {
            uint256 _collateral_output_value 
                = ((_dollar_amount_post_fee * _ecr) / PRICE_PRECISION) / (10**missing_decimals);
            _collateral_output_amount 
                = (_collateral_output_value * PRICE_PRECISION) / _collateral_price;
        }

        // Check if collateral balance meets and meet output expectation
        uint256 _totalCollateralBalance = globalCollateralBalance();
        require(_collateral_output_amount <= _totalCollateralBalance, "<collateralBalance");
        require(_collateral_out_min <= _collateral_output_amount , ">> slippage than expected...");
        require(_share_out_min <= _share_output_amount, ">> slippage than expected......");

        if (_collateral_output_amount > 0) {
            redeem_collateral_balances[msg.sender] = redeem_collateral_balances[msg.sender] + _collateral_output_amount;
            unclaimed_pool_collateral = unclaimed_pool_collateral + _collateral_output_amount;
        }
        
        if (_share_output_amount > 0) {
            redeem_share_balances[msg.sender] = redeem_share_balances[msg.sender] + _share_output_amount;
            unclaimed_pool_share = unclaimed_pool_share + _share_output_amount;
        }

        last_redeemed[msg.sender] = block.timestamp;

        uint256 dollar_amount = _dollar_amount;
        IPoolToken(dollar).pool_burn_from(msg.sender, dollar_amount);
        if (_share_output_amount > 0) {
            _mintShareToCollateralReserve(_share_output_amount);
        }
    }

    // mint CoUSD(dollar) by  COFFIN(share) & FTM(collateral)
    function mint(uint256 _share_amount, uint256 _dollar_out_min) external payable nonReentrant {
        require(mint_paused == false, "Minting is paused");
        require(msg.value > 0, "need FTM");

        uint256 _collateral_amount = msg.value;

        uint256 _minting_fee = IGatePolicy(policy).minting_fee();

        uint256 _share_price = 0;
        if (IGatePolicy(policy).using_twap_for_mint()) {
            _share_price = getCoffinTwap();
        }
        if (_share_price==0) {
            _share_price = getCoffinPrice();
        }
    
        uint256 _tcr = IGatePolicy(policy).target_collateral_ratio();
        uint256 _price_collateral = getCollateralPrice();
        uint256 _total_dollar_value = 0;
        uint256 _required_share_amount = 0;
        if (_tcr > 0) {
            uint256 _collateral_value 
                = ((_collateral_amount * (10**missing_decimals)) * _price_collateral) / PRICE_PRECISION;
            _total_dollar_value = (_collateral_value * COLLATERAL_RATIO_PRECISION) / _tcr;
            if (_tcr < COLLATERAL_RATIO_MAX) {
                // 0 < _tcr <100
                require(_share_price > 0, "Invalid share price");
                _required_share_amount = ((_total_dollar_value - _collateral_value) * PRICE_PRECISION) / _share_price;
            }
        } else {
            // _tcr == 0
            require(_share_price > 0, "Invalid share price");
            _total_dollar_value = (_share_amount * _share_price) / PRICE_PRECISION;
            _required_share_amount = _share_amount;
        }
        uint256 _actual_dollar_amount = _total_dollar_value - ((_total_dollar_value * _minting_fee) / PRICE_PRECISION);
        require(_dollar_out_min <= _actual_dollar_amount, 
            "_actual_dollar_amount is smaller than _dollar_out_min. slippage is bigger than you expected.  ");

        if (_required_share_amount > 0) {
            require(_required_share_amount <= _share_amount, "Not enough SHARE input");
            IPoolToken(share).pool_burn_from(msg.sender, _required_share_amount);
        }
        if (_collateral_amount > 0) {
            IWETH(wftmAddress).deposit{value: _collateral_amount}();
            _transferCollateralToReserve(_collateral_amount);
        }

        IPoolToken(dollar).pool_mint(msg.sender, _actual_dollar_amount);

    }

    function collectRedemption() external nonReentrant {
        uint256 redemption_delay = IGatePolicy(policy).redemption_delay();
        require((last_redeemed[msg.sender] + redemption_delay) <= block.timestamp, "<redemption_delay");
        
        // update 
        // IGatePolicy(policy).refreshCollateralRatio(true);

        bool _send_share = false;
        bool _send_collateral = false;
        uint256 _share_amount;
        uint256 _collateral_amount;

        // Use Checks-Effects-Interactions pattern
        if (redeem_share_balances[msg.sender] > 0) {
            _share_amount = redeem_share_balances[msg.sender];
            redeem_share_balances[msg.sender] = 0;
            unclaimed_pool_share = unclaimed_pool_share - _share_amount;
            _send_share = true;
        }

        if (redeem_collateral_balances[msg.sender] > 0) {
            _collateral_amount = redeem_collateral_balances[msg.sender];
            redeem_collateral_balances[msg.sender] = 0;
            unclaimed_pool_collateral = unclaimed_pool_collateral - _collateral_amount;
            _send_collateral = true;
        }

        if (_send_share) {
            _requestTransferShare(msg.sender, _share_amount);
        }

        if (_send_collateral) {
            _requestTransferCollateralFTM(msg.sender, _collateral_amount);
        }
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

    // transfer collateral(wftm) from reserve to a user.
    function _requestTransferCollateralWrappedFTM(address _receiver, uint256 _amount) internal {
        ICollateralReserve(collateralReserve).transferTo(collateral, _receiver, _amount);
    }

    // transfer share(ERC20) from reserve to users.
    function _requestTransferShare(address _receiver, uint256 _amount) internal {
        ICollateralReserve(collateralReserve).transferTo(share, _receiver, _amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function toggleMinting() external onlyOwner {
        mint_paused = !mint_paused;
    }

    function toggleRedeeming() external onlyOwner {
        redeem_paused = !redeem_paused;
    }


    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid address");
        oracle = _oracle;
    }


    function setPolicy(address _policy) external onlyOwner {
        require(_policy != address(0), "Invalid address");
        policy = _policy;
    }

    function getDollarSupply() public view override returns (uint256) {
        return IERC20(dollar).totalSupply();
    }

    function getCoffinSupply() public view override returns (uint256) {
        return IERC20(share).totalSupply();
    }

    function globalCollateralValue() public view override returns (uint256) {
        return (globalCollateralBalance() * getCollateralPrice() * (10**missing_decimals)) / PRICE_PRECISION;
    }

    function globalCollateralBalance() public view override returns (uint256) {
        uint256 _collateralReserveBalance = IERC20(collateral).balanceOf(collateralReserve);
        return _collateralReserveBalance - unclaimed_pool_collateral;
    }

    function setCollateralReserve(address _collateralReserve) public onlyOwner {
        require(_collateralReserve != address(0), "invalidAddress");
        collateralReserve = _collateralReserve;
    }

    function getCollateralBalance() public view override returns (uint256) {
        return IERC20(collateral).balanceOf(collateralReserve);
    }


    event ZapSwapped(uint256 indexed collateralAmount, uint256 indexed shareAmount);

}
