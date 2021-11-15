// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
// pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "./PoolToken.sol";

contract XCoffin is ERC20, ERC20Snapshot,  Ownable, Initializable, ERC20Permit, ERC20Votes {

    uint256 public constant genesis_supply = 100_000 ether; // 100k will be mited at genesis for liq pool seeding
    // address public treasury;
    uint256 public constant COMMUNITY_REWARD_ALLOCATION = 7_000_000 ether; // 7m
    uint256 public constant DEV_FUND_ALLOCATION = 2_000_000 ether; // 2m
    uint256 public constant MARKETING_FUND_ALLOCATION = 900_000 ether; //900k
    uint256 public constant VESTING_DURATION = 1095 days; // 36 months
    uint256 public startTime; // Start time of vesting duration
    uint256 public endTime; // End of vesting duration

    address public devFund;
    uint256 public devFundLastClaimed;
    uint256 public devFundEmissionRate = DEV_FUND_ALLOCATION / VESTING_DURATION;

    address public marketingFund;
    uint256 public marketingFundLastClaimed;
    uint256 public marketingFundEmissionRate = DEV_FUND_ALLOCATION / VESTING_DURATION;

    address public communityRewardController; 
    uint256 public communityRewardClaimed;

    /* ========== MODIFIERS ========== */



    modifier onlyDevFund() {
        require(msg.sender == devFund, "Only dev fund address can trigger");
        _;
    }
    modifier onlyMarketingFundOrOwner() {
        require(msg.sender == marketingFund || msg.sender==owner(), "onwer or marketing fund address can trigger");
        _;
    }
    
    

    

    /* ========== CONSTRUCTOR ========== */

    constructor() ERC20("XCOFFIN", "XCOFFIN") ERC20Permit("XTEST") {}
    // constructor() ERC20("XCOFFIN", "XCOFFIN") ERC20Permit("XTEST") {}

    function init(
        address _devFund,
        address _marketingFund,
        address _communityRewardController,
        uint256 _startTime
    ) external initializer onlyOwner {
        devFund = _devFund;
        marketingFund = _marketingFund;
        communityRewardController = _communityRewardController;
        startTime = _startTime;
        endTime = _startTime + VESTING_DURATION;
        devFundLastClaimed = _startTime;
        _mint(msg.sender, genesis_supply);
    }

    function snapshot() public onlyOwner {
        _snapshot();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Snapshot)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }


    function claimCommunityRewards(uint256 amount) external onlyOwner {
        // check 
        require(amount > 0, "invalidAmount");
        require(communityRewardController != address(0), "!rewardController");
        uint256 _remainingRewards = COMMUNITY_REWARD_ALLOCATION - communityRewardClaimed;
        require(amount <= _remainingRewards, "exceedRewards");
        // effects
        communityRewardClaimed += amount;
        //interactions
        _mint(communityRewardController, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setDevFund(address _devFund) external onlyDevFund {
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function setMarketingFund(address _marketingFund) external onlyMarketingFundOrOwner {
        require(_marketingFund != address(0), "zero");
        marketingFund = _marketingFund;
    }

    function setCommunityRewardController(address _communityRewardController) external onlyOwner {
        require(_communityRewardController != address(0), "zero");
        communityRewardController = _communityRewardController;
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = (_now - devFundLastClaimed) * devFundEmissionRate;
    }

    function unclaimedMarketingFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (marketingFundLastClaimed >= _now) return 0;
        _pending = (_now - marketingFundLastClaimed) * marketingFundEmissionRate;
    }

    function claimDevFundRewards() external onlyDevFund {
        uint256 _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }
    function claimMarketingFundRewards() external onlyMarketingFundOrOwner {
        uint256 _pending = unclaimedMarketingFund();
        if (_pending > 0 && marketingFund != address(0)) {
            _mint(marketingFund, _pending);
            marketingFundLastClaimed = block.timestamp;
        }
    }

    /* ========== EVENTS ========== */

    event ShareBurned(address indexed from, address indexed to, uint256 amount);
    event ShareMinted(address indexed from, address indexed to, uint256 amount);


}
