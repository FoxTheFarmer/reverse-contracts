pragma solidity ^0.8.7;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import '@openzeppelin/contracts/security/Pausable.sol';

import "./ReverseToken.sol";
import "./interfaces/IConsolidatedFund.sol";

// CoffinMakerV2 ( MasterChef )

contract CoffinMakerV2 is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        int256 rewardDebt; // it's int256, not uint256. 
        uint256 nextHarvestUntil; // When can the user harvest again.
        uint256 depositTimerStart; // deposit starting timer for withdraw lockup
        uint firstDepositTime; // the last time a user deposited at.
        uint lastDepositTime;  // most recent deposit time.
        uint lastWithdrawTime; // the last time a user withdrew at.
        // address referral; // 
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. COFFINs to distribute per second.
        uint256 lastRewardTime;
        uint256 accRewardPerShare; // Accumulated COFFINs per share,nextHarvestUntil times 1e12.
        uint256 harvestInterval; // Harvest interval in seconds
        uint256 withdrawLockupTime; // withdraw lockup time
        uint startRate;
    } 

    // validates: pool exists
    modifier validatePoolByPid(uint pid) {
        require(pid < poolInfo.length, 'pool does not exist');
        _;
    }

    // fund 
    address public fund;

    // profit_sharing_fund fund: Withdrawal tax ( 14% - 0% ) 1 day 1 % decay 
    address public profit_sharing_fund; 

    // The reward TOKEN
    ReverseToken public rewardToken;
    // Dev's address 
    address public dev_fund;
    // Marketing fund address 
    address public marketing_fund;
    // address public comaddr;
    uint256 private constant ACC_REWARD_PRECISION = 1e12;

    // Max harvest interval: 14 days.
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 1 days;
    // Max lockup interval: 14 days.
    uint256 public constant MAXIMUM_LOCKUP_INTERVAL = 14 days;

    mapping(address=>address) public referrals;
    mapping(address=>uint) public referralsCount;
    mapping(address=>uint) public referralsLast;
    
    

    // address public fund;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => bool) public poolExistence;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block timestamp when reward mining starts.
    uint256 public startTime;
    uint256 public endTime;
    
    // reward tokens created per second.
    uint256 public rewardPerSecond;
    uint256 public constant STARTING_WITHIN = 30 days;

    constructor() {}

    function init(address _rewardToken, uint256 _startTime,
        uint256 _rewardPerSecond, address _fund) 
        external virtual onlyOwner  {

        require (startTime==0, "only one time.");
        require (_rewardToken != address(0),"reward token address error") ;
        
        rewardToken = ReverseToken(_rewardToken);
        
        startTime = block.timestamp;
        if (_startTime!=0) {
            require(_startTime > block.timestamp, "CoffinMakerV2: The start time must be in the future. ");
            require(_startTime - block.timestamp <= STARTING_WITHIN, "CoffinMakerV2: invalid starting time ");
            startTime = _startTime;
        }
        rewardPerSecond = _rewardPerSecond;
        if (_rewardPerSecond==0) {
            rewardPerSecond = 1 ether;
        }
        fund = _fund;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }


    modifier nonDuplicated(address _lpToken) {
        require(poolExistence[address(_lpToken)] == false, "CoffinMakerV2: duplicated");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(address(poolInfo[pid].lpToken) != _lpToken, "CoffinMakerV2: duplicated");
        }
        _;
    }

    function setStartTime(uint _startTime) external onlyOwner {
        require(startTime<block.timestamp, "already started");
        startTime = _startTime;
    }


    function addPool(
        uint256 _allocPoint,
        address _lpToken,
        uint256 _harvestInterval,
        uint256 _withdrawLockupTime,
        bool withUpdateAllPool
    ) public onlyOwner nonDuplicated(_lpToken) {
        require(startTime!=0, 'not initilized yet');
        if (withUpdateAllPool) {
            // basically should update everytime, except for starting. 
            _updateAllPools();
        }

        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "CoffinMakerV2: invalid harvest interval");
        require(_withdrawLockupTime <= MAXIMUM_LOCKUP_INTERVAL, "CoffinMakerV2: invalid lockup interval");

        totalAllocPoint += _allocPoint;
        poolExistence[_lpToken] = true;
        uint256 _lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;

        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(_lpToken),
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accRewardPerShare: 0,
                harvestInterval: _harvestInterval,
                withdrawLockupTime: _withdrawLockupTime,
                startRate: enWei(14)
            })
        );
    }

    // Update the given pool's reward allocation point.
    // Can only be called by the owner.
    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _harvestInterval,
        uint256 _withdrawLockupTime,
        uint256 _startRate,
        bool withUpdate
    ) public onlyOwner  validatePoolByPid(_pid) {
        // check

        require(startTime!=0, 'not initilized yet');
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "CoffinMakerV2: invalid harvest interval");
        require(_withdrawLockupTime <= MAXIMUM_LOCKUP_INTERVAL, "CoffinMakerV2: invalid lockup interval");
        require(_startRate<=100, "too much");

        if (withUpdate) { _updateAllPools(); } // updates all pools

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].harvestInterval = _harvestInterval;
        poolInfo[_pid].withdrawLockupTime = _withdrawLockupTime;
        poolInfo[_pid].startRate = enWei(_startRate);

        emit PoolSet(_pid, _allocPoint, _harvestInterval, _withdrawLockupTime, _startRate );
        
    }


    // View function to see pending reward tokens on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
    // function pendingReward(uint256 _pid, address _user) external view returns (int256) {
        require(startTime!=0, 'not initilized yet');
        if (block.timestamp<startTime) {
            return uint256(0);
        }
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 delta = block.timestamp - pool.lastRewardTime;
            uint256 addedReward = (delta.mul(rewardPerSecond).mul(pool.allocPoint)).div(totalAllocPoint);
            accRewardPerShare += (addedReward.mul(ACC_REWARD_PRECISION)).div(lpSupply);
        }

        return uint256(int256((user.amount.mul(accRewardPerShare)).div(ACC_REWARD_PRECISION)) - (user.rewardDebt));
    }

    // View function to see if user can harvest .
    function canHarvest(uint256 _pid, address _user) public view returns (bool) {
        if (untilHarvest(_pid,_user)==0) {
            return true;
        } 
        return false;
    }

    function untilHarvest(uint256 _pid, address _user) public view returns (uint) {
        require(startTime!=0, 'not initilized yet');
        UserInfo storage user = userInfo[_pid][_user];
        if (user.nextHarvestUntil>block.timestamp) {
            return user.nextHarvestUntil - block.timestamp ;
        } else {
            return 0;
        }
    }

    function canWithdraw(uint256 _pid, address _user) public view returns (bool) {
        if (untilWithdraw(_pid, _user)==0) {
            return true;
        }
        return false;
    }

    function untilWithdraw(uint256 _pid, address _user) public view returns (uint) {
        require(startTime!=0, 'not initilized yet');
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        if ((user.depositTimerStart + pool.withdrawLockupTime) > block.timestamp) {
            return (user.depositTimerStart + pool.withdrawLockupTime) - block.timestamp;
        }
        return 0;
    }


    function updatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() external {
        _updateAllPools();
    }

    function _updateAllPools() internal {
        uint256 len = poolInfo.length;
        for (uint256 i = 0; i < len; i++) {
            updatePool(i);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public returns (PoolInfo memory pool) {
        require(startTime!=0, 'not initilized yet');
        pool = poolInfo[_pid];
        
        if( pool.allocPoint==0) {
            // require(pool.allocPoint>0 , "cannot update this pool for now");
            return pool;
        }
        if (block.timestamp <= pool.lastRewardTime) {
            return pool;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            poolInfo[_pid] = pool;
            pool.lastRewardTime = block.timestamp; 
            return pool;
        } 

        int256 delta = int256(block.timestamp - pool.lastRewardTime);
        uint256 reward = (uint256(delta).mul(rewardPerSecond).mul(pool.allocPoint)) / totalAllocPoint;
        
        uint256 dev_reward = 0;
        uint256 marketing_reward = 0;
        uint256 farmingReward = 0;
        
        // 
        if (dev_fund!=address(0)) {
            // 12% for dev fund.
            dev_reward = reward.div(100).mul(12);
            rewardToken.mint(dev_fund, dev_reward);
        }
        if (marketing_fund!=address(0)) {
            // 8% for marketing fund. airdrop, listing, audit, partner reward, etc.
            marketing_reward = reward.div(100).mul(8);
            rewardToken.mint(marketing_fund, marketing_reward);
        }
        // farming reward
        farmingReward = reward.sub(marketing_reward).sub(dev_reward);
        rewardToken.mint(fund, farmingReward);

        pool.accRewardPerShare += (farmingReward.mul( ACC_REWARD_PRECISION)) / lpSupply;

        pool.lastRewardTime = block.timestamp;
        poolInfo[_pid] = pool;
    }

    function poolTokenBalance(uint256 _pid) view public returns(uint256){
        PoolInfo storage pool = poolInfo[_pid];
        return pool.lpToken.balanceOf(msg.sender);
    }

    // Deposit LP tokens to CoffinMaker for reward token allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _to,
        address referral
    )  external nonReentrant validatePoolByPid(_pid) whenNotPaused {
        // check
        require(startTime!=0, 'not initilized yet');
        require(_amount > 0, "deposit should be more than 0");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_to];
        require(pool.allocPoint>0 , "cannot deposit this token for now");
        updatePool(_pid);
        require(pool.lpToken.balanceOf(msg.sender)>= _amount , "you don't have enough balance in your wallet.");

        // effect
        if(_to==msg.sender||user.amount==0) {
            user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
            user.depositTimerStart = block.timestamp;

            user.lastDepositTime = block.timestamp;
            // marks timestamp for first deposit
            user.firstDepositTime = 
                user.firstDepositTime > 0 
                    ? user.firstDepositTime
                    : block.timestamp;
        }
        // check balance before transfer. 
        uint256 bal1 = pool.lpToken.balanceOf(address(this));

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        
        // check balance after transfer. 
        uint256 bal2 = pool.lpToken.balanceOf(address(this));

        // check the diff , it's income value. 
        uint256 actual_amount = bal2-bal1;
        
        require(actual_amount<=_amount, " income value should be smaller than argument value. " );

        user.amount += actual_amount;
        user.rewardDebt += int256((actual_amount.mul( pool.accRewardPerShare)).div( ACC_REWARD_PRECISION));
        
        if (referral!=address(0) && msg.sender!=referral && referrals[msg.sender]==address(0)) {
            // For airdrop, nftdrop, etc. 
            // It’s one of reference for random selection 
            referrals[msg.sender] = referral;
            referralsCount[referral]++;
            referralsLast[referral] = block.timestamp;
        }

        emit EventDeposit(msg.sender, _pid, _amount, _to);
    }


    function withdrawLockup(uint256 pid) view public returns(uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        return user.depositTimerStart.add(pool.withdrawLockupTime).sub(block.timestamp);
    }
    // Withdraw LP tokens from CoffinMaker.
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) public nonReentrant validatePoolByPid(_pid) {
        require(startTime!=0, 'not initilized yet');
        require(_to != address(0), "cannot withdraw to zero address");

        //PoolInfo memory pool = updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // check
        require(user.amount >= _amount, "CoffinMakerV2: withdraw request greater than staked amount");
        updatePool(_pid);
        require(_amount > 0, "CoffinMakerV2: withdraw amount should be more than 0");
        require(
            (user.depositTimerStart + pool.withdrawLockupTime) <= block.timestamp,
            "CoffinMakerV2: still in withdraw lockup time"
        );
        uint256 bal1 = pool.lpToken.balanceOf(address(this));

        //
        user.rewardDebt -= int256((_amount.mul( pool.accRewardPerShare)) .div( ACC_REWARD_PRECISION));
        user.amount -= _amount;
        user.lastWithdrawTime = block.timestamp;

        // tax calc. tax decay. 1 day 1 %. 
        uint timeDelta = 0;
        uint feeAmount = 0;
        uint withdrawable = 0;
        if (profit_sharing_fund!=address(0)) {
            timeDelta = block.timestamp.sub(user.lastDepositTime);
            (feeAmount, withdrawable) = getWithdrawable(pool.startRate, timeDelta, _amount); 
        }
        //
        if (feeAmount>0) {
            pool.lpToken.transfer(address(profit_sharing_fund), feeAmount);
            // pool.lpToken.transfer(address(msg.sender), withdrawable);
            pool.lpToken.transfer(address(_to), withdrawable);
        } else {
            // pool.lpToken.transfer(address(msg.sender), _amount);
            pool.lpToken.transfer(address(_to), _amount);
        }
        // check again. just in case. 
        uint256 bal2 = pool.lpToken.balanceOf(address(this));
        assert((bal1 - bal2) == _amount);

        emit EventWithdraw(msg.sender, _pid, _amount, _to);
    }

    // returns: decay rate 
    function getFeeRate(uint _startRate, uint timeDelta) public pure returns (uint feeRate) {
        uint daysPassed = timeDelta < 1 days ? 0 : timeDelta / 1 days;
        uint rateDecayed = enWei(daysPassed);
        uint _rate = rateDecayed >= _startRate ? 0 : _startRate - rateDecayed;
        return _rate;
    }

    // manual override to reassign the first & last deposit time for a given (pid, account)
    // it's only testing purpose. 
    function reviseDepositTime(uint _pid, address _user, uint256 _first, uint256 _last) public onlyOwner {
        UserInfo storage user = userInfo[_pid][_user];
        user.firstDepositTime = _first;
        user.lastDepositTime = _last;

        emit DepositTimeRevised(_pid, _user, _first, _last);
	}

    // returns: feeAmount and with withdrawableAmount for a given _startRate and amount
    function getWithdrawable(uint _startRate, uint _timeDelta, uint _amount)
        public pure returns (uint _feeAmount, uint _withdrawable) {
        uint feeRate = fromWei(getFeeRate(_startRate, _timeDelta));
        uint feeAmount = (_amount * feeRate) / 100;
        uint withdrawable = _amount - feeAmount;
        return (feeAmount, withdrawable);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // still you need to pay tax if not enough time to deposit. 
    function emergencyWithdraw(uint256 _pid) public nonReentrant validatePoolByPid(_pid) {
        require(startTime!=0, 'not initilized yet');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // effect
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.nextHarvestUntil = 0;
        user.depositTimerStart = 0;
        user.firstDepositTime = 0;
        user.lastDepositTime = 0;
        user.lastWithdrawTime = 0;

        // tax calc. tax decay. 1 day 1 %. 
        uint timeDelta = 0;
        uint feeAmount = 0;
        uint withdrawable = 0;
        if (profit_sharing_fund!=address(0)) {
            timeDelta = block.timestamp.sub(user.lastDepositTime);
            (feeAmount, withdrawable) = getWithdrawable(pool.startRate, timeDelta, amount); 
        }
        //
        if (feeAmount>0) {
            pool.lpToken.transfer(address(profit_sharing_fund), feeAmount);
            pool.lpToken.transfer(address(msg.sender), withdrawable);
        } else {
            pool.lpToken.transfer(address(msg.sender), amount);
        }

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }


    function harvest(uint256 _pid, address _to) public nonReentrant validatePoolByPid(_pid) {
        require(startTime!=0, 'not initilized yet');
        require(_to != address(0), "cannot withdraw to zero address");
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(block.timestamp >= user.nextHarvestUntil, "CoffinMakerV2: need to wait for next harvest time");

        int256 accumulatedReward = int256((user.amount.mul(pool.accRewardPerShare)) .div( ACC_REWARD_PRECISION));
        uint256 pending = uint256(accumulatedReward - user.rewardDebt);
        require(pending > 0, "CoffinMakerV2: no pending reward ");

        // Effects
        user.rewardDebt = accumulatedReward;
        user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
        // Interactions
        safeRewardTransfer(_to, pending);
        emit EventHarvest(msg.sender, _pid, pending, _to);
    }


    // Safe rewward token transfer function, 
    // just in case if rounding error causes pool to not have enough reward tokens.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        IConsolidatedFund(fund).transferTo(address(rewardToken), _to, _amount);
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        require(startTime!=0, 'not initilized yet');
        _updateAllPools();
        rewardPerSecond = _rewardPerSecond;
    }
    function setDevFund(address _dev_fund) public {
        require(msg.sender==owner() || msg.sender == dev_fund, "CoffinMakerV2: only from dev");
        dev_fund = _dev_fund;
        emit EventSetDev( _dev_fund);
    }

    function setProfitSharingFund(address _profit_sharing_fund) public {
        require(msg.sender==owner() || msg.sender == profit_sharing_fund,
            "CoffinMakerV2: only from profit_sharing_fund");
        profit_sharing_fund = _profit_sharing_fund;
        emit EventSetProfitSharingFund( _profit_sharing_fund);

    }
    function setMarketingFund(address _marketing_fund) public {
        require(msg.sender==owner() || msg.sender == _marketing_fund, "CoffinMakerV2: only from marketing_fund");
        marketing_fund = _marketing_fund;
        emit EventSetMarketingFund( _marketing_fund);
    }
    
    function enWei(uint amount) public pure returns (uint) {  return amount * 1e18; }
    function fromWei(uint amount) public pure returns (uint) { return amount / 1e18; }
    
    event EventSetProfitSharingFund(address indexed profit_sharing_fund);
    event EventSetDev(address indexed dev_fund);
    event EventSetMarketingFund(address indexed _marketing_fund);
    event EventHarvest(address indexed user, uint256 indexed pid, uint256 amount, address _to);
    
    event EventDeposit(address indexed user, uint256 indexed pid, uint256 amount, address to);
    event EventWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolSet(uint pid, uint allocPoint, uint _harvestInterval, uint _withdrawLockupTime, uint _startRate);

    event DepositTimeRevised(uint _pid, address account, uint _first, uint _last);
}
