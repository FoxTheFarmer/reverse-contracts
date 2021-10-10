pragma solidity ^0.8.7;
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./Coffin.sol";

// MasterChef

contract CoffinMaker is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        int256 rewardDebt; // it's int256, not uint256. 
        uint256 nextHarvestUntil; // When can the user harvest again.
        uint256 depositTimerStart; // deposit starting timer for withdraw lockup
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. COFFINs to distribute per second.
        uint256 lastRewardTime;
        uint256 accRewardPerShare; // Accumulated COFFINs per share, times 1e12.
        uint256 harvestInterval; // Harvest interval in seconds
        uint256 withdrawLockupTime; // withdraw lockup time
    }
    // The reward TOKEN
    Coffin public rewardToken;
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
    uint256 public totalMintedReward;
    uint256 public constant STARTING_WITHIN = 30 days;
    uint256 public DEFAULT_VESTING_DRATION = 1095 days ; // 365 * 3 
    uint256 public TOTAL_SUPPLY = 100_000_000 ether; // 100 million.

    constructor() {}


    function init(address _rewardToken, uint256 _startTime, uint256 _rewardPerSecond) external virtual onlyOwner  {
        require (startTime==0, "only one time.");
        require (_rewardToken != address(0),"reward token address error") ;
        
        rewardToken = Coffin(_rewardToken);
        
        startTime = block.timestamp;
        if (_startTime!=0) {
            require(_startTime > block.timestamp, "CoffinMaker: The start time must be in the future. ");
            require(_startTime - block.timestamp <= STARTING_WITHIN, "CoffinMaker: invalid starting time ");
            startTime = _startTime;
        }
        rewardPerSecond = _rewardPerSecond;
        if (_rewardPerSecond==0) {
            // rewardPerSecond = totalReward / vestingDuration;
            rewardPerSecond = 1 ether;
        }
        totalMintedReward = totalMintedReward.add(rewardToken.genesis_supply());
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }


    modifier nonDuplicated(address _lpToken) {
        require(poolExistence[address(_lpToken)] == false, "CoffinMaker: duplicated");
        require(_lpToken!=address(rewardToken), "CoffinMaker: cannot use reward token as lpToken");

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(address(poolInfo[pid].lpToken) != _lpToken, "CoffinMaker: duplicated");
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

        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "CoffinMaker: invalid harvest interval");
        require(_withdrawLockupTime <= MAXIMUM_LOCKUP_INTERVAL, "CoffinMaker: invalid lockup interval");

        totalAllocPoint += _allocPoint;
        poolExistence[_lpToken] = true;
        uint256 _lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        //uint256 _lastRewardTime = block.timestamp;

        poolInfo.push(
            PoolInfo({
                lpToken: IERC20(_lpToken),
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                // lastRewardTime: block.timestamp,
                accRewardPerShare: 0,
                harvestInterval: _harvestInterval,
                withdrawLockupTime: _withdrawLockupTime
            })
        );
    }

    // Update the given pool's reward allocation point. Can only be called by the owner.
    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _harvestInterval,
        uint256 _withdrawLockupTime
    ) public onlyOwner {
        // check
        require(startTime!=0, 'not initilized yet');
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "CoffinMaker: invalid harvest interval");
        require(_withdrawLockupTime <= MAXIMUM_LOCKUP_INTERVAL, "CoffinMaker: invalid lockup interval");
        _updateAllPools();

        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].harvestInterval = _harvestInterval;
        poolInfo[_pid].withdrawLockupTime = _withdrawLockupTime;

        
    }



    // View function to see pending reward tokens on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
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
        require(startTime!=0, 'not initilized yet');
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }

    function canWithdraw(uint256 _pid, address _user) external view returns (bool) {
        require(startTime!=0, 'not initilized yet');
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        return (user.depositTimerStart + pool.withdrawLockupTime) <= block.timestamp;
    }

    function updatePools(uint256[] calldata pids) external {
        // require(startTime!=0, 'not initilized yet');
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
        require(pool.allocPoint>0 , "cannot update this pool for now");

        if (totalMintedReward < TOTAL_SUPPLY) {
                
            if (block.timestamp > pool.lastRewardTime) {
                uint256 lpSupply = pool.lpToken.balanceOf(address(this));
                if (lpSupply > 0) {
                    int256 delta = int256(block.timestamp - pool.lastRewardTime);
                    uint256 reward = (uint256(delta).mul(rewardPerSecond).mul(pool.allocPoint)) / totalAllocPoint;
                
                    if (totalMintedReward + reward > TOTAL_SUPPLY) {

                        reward = TOTAL_SUPPLY - totalMintedReward;
                    }
                    


                    pool.accRewardPerShare += (reward.mul( ACC_REWARD_PRECISION)) / lpSupply;
                    
                    uint256 devreward = 0;
                    uint256 marketing_amount = 0;
                    
                    // 
                    if (dev_fund!=address(0)) {
                        // ( 100 % total - 3 % initial ) / 97 * 12 => 12 % 
                        devreward = reward.div(97).mul(12);
                        //
                        rewardToken.reward_mint(dev_fund, devreward);
                        // rewardToken.pool_mint(dev_fund, devreward);
                        
                    }
                    if (marketing_fund!=address(0)) {
                        // ( 100 % total - 3 % initial ) / 97 * 8 => 8 % 
                        marketing_amount = reward.div(97).mul(8);
                        rewardToken.reward_mint(marketing_fund, marketing_amount);
                        // rewardToken.pool_mint(marketing_fund, marketing_amount);
                    }
                    rewardToken.reward_mint(address(this), reward.sub(devreward).sub(marketing_amount) );
                    // rewardToken.pool_mint(address(this), reward.sub(devreward).sub(marketing_amount) );
                    // totalMintedReward += totalMintedReward.add(reward);
                    totalMintedReward = totalMintedReward.add(reward);
                }
                pool.lastRewardTime = block.timestamp;
                poolInfo[_pid] = pool;
            }
        }

    }
    function poolTokenBalance(uint256 _pid) view public returns(uint256){
        PoolInfo storage pool = poolInfo[_pid];
        return pool.lpToken.balanceOf(msg.sender);
    }


    // Deposit LP tokens to CoffinMaker for reward token allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _to
    ) public nonReentrant {
        // check
        require(startTime!=0, 'not initilized yet');
        require(_amount > 0, "deposit should be more than 0");
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][_to];
        require (_pid < poolInfo.length, "no exist");
        require(pool.allocPoint>0 , "cannot deposit this token for now");
        require(pool.lpToken.balanceOf(msg.sender)>= _amount , "you don't have enough balance in your wallet.");
        
        // effect
        if(_to==msg.sender||user.amount==0) {
            user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
            user.depositTimerStart = block.timestamp;
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
    ) public nonReentrant {
        require(startTime!=0, 'not initilized yet');
        require(_to != address(0), "cannot withdraw to zero address");

        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        // check
        require(user.amount >= _amount, "CoffinMaker: withdraw request greater than staked amount");
        require(_amount > 0, "CoffinMaker: withdraw amount should be more than 0");
        require(
            (user.depositTimerStart + pool.withdrawLockupTime) <= block.timestamp,
            "CoffinMaker: still in withdraw lockup time"
        );
        uint256 bal1 = pool.lpToken.balanceOf(address(this));

        //effect
        user.rewardDebt -= int256((_amount.mul( pool.accRewardPerShare)) .div( ACC_REWARD_PRECISION));
        user.amount -= _amount;

        //interaction
        pool.lpToken.safeTransfer(_to, _amount);

        uint256 bal2 = pool.lpToken.balanceOf(address(this));
        assert((bal1 - bal2) == _amount);

        emit EventWithdraw(msg.sender, _pid, _amount, _to);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        require(startTime!=0, 'not initilized yet');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // effect
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.nextHarvestUntil = 0;
        user.depositTimerStart = 0;
        // interaction
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }


    function harvest(uint256 _pid, address _to) public nonReentrant {
        // require(startTime!=0, 'not initilized yet');
        require(_to != address(0), "cannot withdraw to zero address");
        PoolInfo memory pool = updatePool(_pid);
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(block.timestamp >= user.nextHarvestUntil, "CoffinMaker: need to wait for next harvest time");

        int256 accumulatedReward = int256((user.amount.mul(pool.accRewardPerShare)) .div( ACC_REWARD_PRECISION));
        uint256 pending = uint256(accumulatedReward - user.rewardDebt);
        require(pending > 0, "CoffinMaker: no pending reward ");

        // Effects
        user.rewardDebt = accumulatedReward;
        user.nextHarvestUntil = block.timestamp + pool.harvestInterval;
        // Interactions
        safeRewardTransfer(_to, pending);
        emit EventHarvest(msg.sender, _pid, pending, _to);
    }



    // Safe reward transfer function, just in case if rounding error causes pool to not have enough rewards.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        require(startTime!=0, 'not initilized yet');
        uint256 bal = rewardToken.balanceOf(address(this));
        if (bal > 0) {
            if (_amount > bal) {
                IERC20(rewardToken).safeTransfer(_to, bal);
                emit EventSafeRewardTransfer(_to, bal);
            } else {
                IERC20(rewardToken).safeTransfer(_to, _amount);
                emit EventSafeRewardTransfer(_to, _amount);
            }
        }
    }

    function setRewardPerSecond(uint256 _rewardPerSecond) external onlyOwner {
        require(startTime!=0, 'not initilized yet');
        _updateAllPools();
        rewardPerSecond = _rewardPerSecond;
    }
    function setDevFund(address _dev_fund) public {
        require(msg.sender==owner() || msg.sender == dev_fund, "CoffinMaker: only from dev");
        dev_fund = _dev_fund;
        emit EventSetDev( _dev_fund);
    }
    function setMarketingFund(address _marketing_fund) public {
        require(msg.sender==owner() || msg.sender == _marketing_fund, "CoffinMaker: only from dev");
        marketing_fund = _marketing_fund;
        emit EventSetMarketingFund( _marketing_fund);
    }
    
    
    event EventSetDev(address indexed dev_fund);
    event EventSetMarketingFund(address indexed _marketing_fund);
    event EventHarvest(address indexed user, uint256 indexed pid, uint256 amount, address _to);
    
    event EventDeposit(address indexed user, uint256 indexed pid, uint256 amount, address to);
    event EventWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    
    event EventSafeRewardTransfer(address indexed to, uint256 amount);
}
