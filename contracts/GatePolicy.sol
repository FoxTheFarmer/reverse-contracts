// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IGate.sol";
import "./interfaces/IGatePolicy.sol";
import "./interfaces/ITwapOracle.sol";
import "./CoffinOracle.sol";


contract GatePolicy is Ownable, IGatePolicy, Initializable {
    using SafeMath for uint256;

    // address public coffinOracle;
    address public gate;
    address public dollar;
    address public collateral;
    // address public treasury;

    // wrapped ftm
    address private wftmAddress = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;

    uint256 public override redemption_fee; // 6 decimals of precision, divide by 1000000 in calculations for fee
    uint256 public override extra_redemption_fee; // 6 decimals of precision, divide by 1000000 in calculations for fee
    uint256 public override minting_fee; // 6 decimals of precision, divide by 1000000 in calculations for fee

    // Constants for various precisions
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant RATIO_PRECISION = 1e6;

    // collateral_ratio
    uint256 public override target_collateral_ratio; // 6 decimals of precision
    // uint256 public override effective_collateral_ratio; // 6 decimals of precision
    uint256 public last_refresh_cr_timestamp;
    uint256 public refresh_cooldown; // Seconds to wait before being able to run refreshCollateralRatio() again
    uint256 public ratio_step; // Amount to change the collateralization ratio by upon refreshCollateralRatio()
    // The price of DOLLAR; this value is only used for 
    // the collateral ratio mechanism and not for minting and redeeming which are hardcoded at $1
    uint256 public override price_target; 
    // The bound above and below the price target at which the Collateral 
    // ratio is allowed to drop
    uint256 public price_band; 
    bool public collateral_ratio_paused = false; // during bootstraping phase, collateral_ratio will be fixed at 100%
    // bool public using_effective_collateral_ratio = true; 
    uint256 private constant COLLATERAL_RATIO_MAX = 1e6;

    bool public override using_twap_for_tcr = false;
    bool public override using_twap_for_redeem = false;
    bool public override using_twap_for_mint = false;
    
    // address public oracle_twap;
    address public oracle;


    // Number of blocks to wait before being able to collectRedemption()
    uint256 public override redemption_delay = 120;
    /* ========== EVENTS ============= */

    event TreasuryChanged(address indexed newTreasury);

    /* ========== CONSTRUCTOR ========== */

    constructor() {
        ratio_step = 2500; // = 0.25% at 6 decimals of precision
        target_collateral_ratio = 800000;
        // effective_collateral_ratio = 1000000;
        // Refresh cooldown period is set to 1 hour (3600 seconds) at genesis
        refresh_cooldown = 3600; 
        // = $1. (6 decimals of precision). 
        // Collateral ratio will adjust according to the $1 price target at genesis
        price_target = 1000000; 
        price_band = 5000;

        minting_fee = 3000; // 0.3 % by defalt
        redemption_fee = 4000; // 0.4% by default
        extra_redemption_fee = 4000; // 0.4% by default

    }

    function init(address _gate, address _dollar, address _collateral) external onlyOwner initializer {
        setGate(_gate);
        setDollar(_dollar);
        setCollateral(_collateral);
    }

    /* ========== VIEWS ========== */


    function getEffectiveCollateralRatio() public view override returns   (uint256) {
        // if (!using_effective_collateral_ratio) {
        //     return target_collateral_ratio;
        // }
        uint256 total_collateral_value = IGate(gate).globalCollateralValue();
        uint256 total_supply_dollar = IERC20(dollar).totalSupply();
        if (total_supply_dollar == 0) {
            return COLLATERAL_RATIO_MAX;
        }
        if (total_collateral_value == 0) {
            return 0;
        }
        uint256 ecr = total_collateral_value.mul(PRICE_PRECISION).div(total_supply_dollar);
        if (ecr > COLLATERAL_RATIO_MAX) {
            return COLLATERAL_RATIO_MAX;
        }
        return ecr;
    }


    /* ========== PUBLIC FUNCTIONS ========== */

    function canRefresh() view public returns(bool){
        if (collateral_ratio_paused) {
            return false;
        }
        if (block.timestamp - last_refresh_cr_timestamp >= refresh_cooldown) {
            return true;
        }
        return false;
    }
    

    function refreshCollateralRatio(bool noerror) external override {
        if (!noerror) {
            require(collateral_ratio_paused == false, "Collateral Ratio has been paused");
            require(
                block.timestamp - last_refresh_cr_timestamp >= refresh_cooldown,
                "Must wait for the refresh cooldown since last refresh"
            );
        } else {
            if (collateral_ratio_paused) {
                //Collateral Ratio has been paused
                return ;
            }
            if (block.timestamp - last_refresh_cr_timestamp < refresh_cooldown) {
                return ;
            }
        }
        uint256 current_dollar_price = 0;

        if (using_twap_for_tcr) {
            (uint256 __price, uint8 __d) = ICoffinOracle(oracle).getTwapCOUSDUSD();
            current_dollar_price = __price.mul(PRICE_PRECISION).div(10**__d);
        }
        if (current_dollar_price==0) {
            // use corrent COUSD price instaed of TWAP
            current_dollar_price =IGate(gate).getDollarPrice();
        }

        // Step increments are 0.25% (upon genesis, changable by setRatioStep())
        if (current_dollar_price > price_target.add(price_band)) {
            // decrease collateral ratio
            if (target_collateral_ratio <= ratio_step) {
                // if within a step of 0, go to 0
                target_collateral_ratio = 0;
            } else {
                target_collateral_ratio = target_collateral_ratio.sub(ratio_step);
            }
        }
        //  price is below $1 - `price_band`. Need to increase `collateral_ratio`
        else if (current_dollar_price < price_target.sub(price_band)) {
            // increase collateral ratio
            if (target_collateral_ratio.add(ratio_step) >= COLLATERAL_RATIO_MAX) {
                target_collateral_ratio = COLLATERAL_RATIO_MAX; // cap collateral ratio at 1.000000
            } else {
                target_collateral_ratio = target_collateral_ratio.add(ratio_step);
            }
        }

        // // If using ECR, then calcECR. If not, update ECR = TCR
        // if (using_effective_collateral_ratio) {
        //     effective_collateral_ratio = getEffectiveCollateralRatio();
        // } else {
        //     effective_collateral_ratio = target_collateral_ratio;
        // }

        last_refresh_cr_timestamp = block.timestamp;
        // emit CollateralRatioRefreshed(effective_collateral_ratio, target_collateral_ratio);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRatioStep(uint256 _ratio_step) public onlyOwner {
        ratio_step = _ratio_step;
    }

    function setPriceTarget(uint256 _price_target) public onlyOwner {
        price_target = _price_target;
    }

    function setRefreshCooldown(uint256 _refresh_cooldown) public onlyOwner {
        refresh_cooldown = _refresh_cooldown;
    }

    function setPriceBand(uint256 _price_band) external onlyOwner {
        price_band = _price_band;
    }



    function setDollar(address _dollar) public onlyOwner {
        require(_dollar != address(0), "invalidAddress");
        dollar = _dollar;
    }
    function setCollateral(address _addr) public onlyOwner {
        require(_addr != address(0), "invalidAddress");
        collateral = _addr;
    }

    // use to retstore CRs incase of using new Treasury
    function reset(uint256 _target_collateral_ratio) external onlyOwner {
        require(
            _target_collateral_ratio <= COLLATERAL_RATIO_MAX,
            "invalid Ratio"
        );
        target_collateral_ratio = _target_collateral_ratio;
        // effective_collateral_ratio = _effective_collateral_ratio;
    }

    function toggleCollateralRatio() public onlyOwner {
        collateral_ratio_paused = !collateral_ratio_paused;
        emit CollateralRatioToggled(collateral_ratio_paused);
    }

    function enableTwapForTCR() public onlyOwner {
        using_twap_for_tcr = true;
        emit TwapTCRToggled(true);
    }

    function disableTwapForTCR() public onlyOwner {
        using_twap_for_tcr = false;
        emit TwapTCRToggled(false);
    }

    function enableTwapForRedeem() public onlyOwner {
        using_twap_for_redeem = true;
        emit TwapTCRToggled(true);
    }

    function disableTwapForRedeem() public onlyOwner {
        using_twap_for_redeem = false;
        emit TwapRedeemToggled(false);
    }

    function enableTwapForMint() public onlyOwner {
        using_twap_for_mint = true;
        emit TwapRedeemToggled(true);
    }

    function disableTwapForMint() public onlyOwner {
        using_twap_for_mint = false;
        emit TwapMintToggled(false);
    }


    function setOracle(address _oracle) public onlyOwner {
        require(_oracle!=address(0), "_oracle address ");
        oracle = _oracle;
    }

    // function toggleEffectiveCollateralRatio() public onlyOwner {
    //     using_effective_collateral_ratio = !using_effective_collateral_ratio;
    // }

    function setGate(address _gate) public onlyOwner {
        require(_gate != address(0), "invalidAddress");
        gate = _gate;
    }

    function setMintingFee(uint256 min_fee) public onlyOwner {
        minting_fee = min_fee;

        // emit MintingFeeSet(min_fee);
    }

    function setRedemptionFee(uint256 red_fee) public onlyOwner {
        redemption_fee = red_fee;
        // emit RedemptionFeeSet(red_fee);
    }
    function setExtraRedemptionFee(uint256 ex_red_fee) public onlyOwner {
        extra_redemption_fee = ex_red_fee;
        // emit ExtraRedemptionFeeSet(ex_red_fee);
    }
    

    function setRedemptionDelay(uint256 _redemption_delay) external onlyOwner {
        redemption_delay = _redemption_delay;
    }
    event CollateralRatioToggled(bool collateral_ratio_paused);
    event TwapTCRToggled(bool using_twap_for_tcr);
    event TwapRedeemToggled(bool using_twap_for_tcr);
    event TwapMintToggled(bool using_twap_for_tcr);
    

}
