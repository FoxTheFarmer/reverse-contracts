// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './veERC20Upgradeable.sol';
import './interfaces/IMasterchef.sol';
import './interfaces/IVeRvrs.sol';

/// @title VeRvrs
/// @notice RVRS: the staking contract for RVRS, as well as the token used for governance.
/// Here are the rules of the game:
/// If you stake RVRS, you generate veRvrs at the current `generationRate` until you reach `maxCap`
/// If you unstake any amount of rvrs, you loose all of your veRvrs.
/// Note that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once Rvrs is sufficiently
/// distributed and the community can show to govern itself.
contract VeRvrs is
Initializable,
OwnableUpgradeable,
ReentrancyGuardUpgradeable,
PausableUpgradeable,
VeERC20Upgradeable,
IVeRvrs
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // rvrs staked by user
        uint256 rewardDebt;
        uint256 rewardDebtVeRvrs;
        uint256 lastClaim; // time of last claim or first deposit if user has not claimed yet
        uint256 lastDeposit; // time of last deposit
    }

    /// @notice the rvrs token
    IERC20 public rvrs;
    address public rvrsDAO;

    /// @notice the masterchef contract
    IMasterchef public masterchef;

    /// @notice max veRvrs to staked rvrs ratio
    /// Note if user has 10 rvrs staked, they can only have a max of 10 * maxCap veRvrs in balance
    uint256 public maxCap;

    /// @notice Total reverse staked
    uint256 public totalStaked;
    uint256 public totalRewardsClaimed;
    uint256 public lastRewardTime;
    uint256 public accRewardPerShare; // for RVRS
    uint256 public accRewardPerVeShare; // for veRVRS
    uint256 private constant ACC_REWARD_PRECISION = 1e18;

    uint256 public initialDepositMint; // in bips 50 = 0.5%
    uint256 public withdrawFee; // in bips
    uint256 public constant  MAX_WITHDRAW_FEE = 2000; // 20%
    uint256 public withdrawFeeTime;
    uint256 public constant  MAX_WITHDRAW_FEE_TIME = 90 days;
    uint256 public pid; // pid for custom token masterchef pool

    /// @notice This is so we can set a warmup period with no rewards
    bool public rewardsStarted = false;

    /// @notice the rate of veRvrs generated per second, per rvrs staked
    /// @dev to figure out days to cap, the formula is:
    ///      maxCap * 1e18 / generationRate / 60 / 60 / 24
    /// @dev to reverse engineer generation rate to target a nDays to cap:
    ///      generationRate = maxCap * 1e18 / nDays / 60 / 60 / 24
    uint256 public generationRate;
    uint256 public constant MAX_GENERATION_RATE = 38580246913500;

    /// @notice invVvoteThreshold threshold.
    /// @notice voteThreshold is the percentage of cap from which votes starts to count for governance proposals.
    /// @dev inverse of the threshold to apply.
    /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
    /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
    /// Formula is invVoteThreshold = (1 / th) * 100
    uint256 public invVoteThreshold;

    /// @notice percent of rewards to veRVRS holders,
    /// @notice rest of rewards allocated by RVRS staked
    /// @dev in bips, i.e 100 = 1%
    uint256 public constant percVeRvrsReward = 3333;
    uint256 public constant TOTAL_PERC = 10000;

    /// @notice user info mapping
    mapping(address => UserInfo) public userInfo;

    /// @notice user mapping for allowing auto-stake
    mapping(address => bool) public authorized;

    /// @notice events describing staking, unstaking and claiming
    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount, uint256 fee);
    event Claimed(address indexed user, uint256 indexed amount, bool autostake);

    event RewardsStarted(address indexed user);
    event UpdateMaxCap(uint256 indexed oldCap, uint256 indexed newCap);
    event UpdateAuthorized(address indexed user, bool isAuth);
    event UpdateWithdrawFee(uint256 indexed oldFee, uint256 indexed newFee);
    event UpdateWithdrawFeeTime(uint256 indexed oldFeeTime, uint256 indexed newFeeTime);
    event UpdateGenerationRate(uint256 indexed oldRate, uint256 indexed newRate);
    event UpdateInitialDepositMint(uint256 indexed oldAmount, uint256 indexed newAmount);

    event UpdateInvVoteThreshold(uint256 indexed oldThresold, uint256 indexed newThresold);

    function initialize(
        IERC20 _rvrs,
        IMasterchef _masterchef,
        address _rvrsDAO,
        uint256 _pid
    ) public initializer {
        require(address(_masterchef) != address(0), 'zero address');
        require(address(_rvrs) != address(0), 'zero address');
        require(_rvrsDAO != address(0), 'zero address');

        // Initialize veRvrs
        __ERC20_init('veRVRS', 'veRVRS');
        __Ownable_init();
        masterchef = _masterchef;
        rvrs = _rvrs;
        rvrsDAO = _rvrsDAO;
        pid = _pid;

        // Setup initial variables
        maxCap = 4;
        initialDepositMint = 50; // in bips 0.5%
        withdrawFee = 500; // in bips
        generationRate = 385802469135;
        invVoteThreshold = 20;
        withdrawFeeTime = 14 days;
        rewardsStarted = false;
    }

    /**
     * @dev pause pool, restricting certain operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, enabling certain operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
    * @dev start rewards for everyone
     */
    function startRewards() external onlyOwner {
        require(!rewardsStarted, 'rewards already started');
        rewardsStarted = true;
        emit RewardsStarted(msg.sender);
    }

    /// @notice sets maxCap
    /// @param _maxCap the new max ratio
    /// @dev WARNING - if you lower this, there's no way to reduce it for people over the cap
    function setMaxCap(uint256 _maxCap) external onlyOwner {
        require(_maxCap != 0, 'max cap cannot be zero');
        require(invVoteThreshold <= _maxCap * 100, 'invVoteThreshold must be less than maxCap');
        uint256 oldCap = maxCap;
        maxCap = _maxCap;
        emit UpdateMaxCap(oldCap, _maxCap);
    }

    /// @notice sets authorized for auto-staking
    /// @param _addr - staking contract
    /// @param _isAuth - bool
    function setAuthorized(address _addr, bool _isAuth) external onlyOwner {
        authorized[_addr] = _isAuth;
        emit UpdateAuthorized(_addr, _isAuth);
    }

    /// @notice sets withdrawFee
    /// @param _withdrawFee the new withdraw fee
    function setWithdrawFee(uint256 _withdrawFee) external onlyOwner {
        require(_withdrawFee <= MAX_WITHDRAW_FEE, 'withdraw fee too high');
        uint256 oldFee = withdrawFee;
        withdrawFee = _withdrawFee;
        emit UpdateWithdrawFee(oldFee, _withdrawFee);
    }

    /// @notice sets initialDepositMint
    /// @param _initialDepositMint the new initial deposit mint %
    function setInitialDepositMint(uint256 _initialDepositMint) external onlyOwner {
        require(_initialDepositMint > 0, 'initial mint too low');
        require(_initialDepositMint <= 1000, 'initial mint too high');
        uint256 oldAmount = initialDepositMint;
        initialDepositMint = _initialDepositMint;
        emit UpdateInitialDepositMint(oldAmount, _initialDepositMint);
    }

    /// @notice sets withdrawFeeTime
    /// @param _withdrawFeeTime the new time
    function setWithdrawFeeTime(uint256 _withdrawFeeTime) external onlyOwner {
        require(_withdrawFeeTime <= MAX_WITHDRAW_FEE_TIME, 'bad withdraw fee time');
        uint256 oldTime = withdrawFeeTime;
        withdrawFeeTime = _withdrawFeeTime;
        emit UpdateWithdrawFeeTime(oldTime, _withdrawFeeTime);
    }

    /// @notice sets generation rate
    /// @param _generationRate the new generation rate
    function setGenerationRate(uint256 _generationRate) external onlyOwner {
        require(_generationRate != 0, 'generation rate cannot be zero');
        require(_generationRate <= MAX_GENERATION_RATE, 'generation too high');
        uint256 oldRate = generationRate;
        generationRate = _generationRate;
        emit UpdateGenerationRate(oldRate, _generationRate);
    }

    /// @notice sets invVoteThreshold
    /// @param _invVoteThreshold the new var
    /// Formula is invVoteThreshold = (1 / th) * 100
    function setInvVoteThreshold(uint256 _invVoteThreshold) external onlyOwner {
        // onwner should set a high value if we do not want to implement an important threshold
        require(_invVoteThreshold != 0, 'invVoteThreshold cannot be zero');
        require(_invVoteThreshold <= maxCap * 100, 'invVoteThreshold must be less than maxCap');
        uint256 oldInvVoteThreshold = invVoteThreshold;
        invVoteThreshold = _invVoteThreshold;
        emit UpdateInvVoteThreshold(oldInvVoteThreshold, _invVoteThreshold);
    }

    /// @notice checks whether user _addr has rvrs staked
    /// @param _addr the user address to check
    /// @return true if the user has rvrs in stake, false otherwise
    function isUser(address _addr) public view override returns (bool) {
        return userInfo[_addr].amount > 0;
    }

    /// @notice returns staked amount of rvrs for user
    /// @param _addr the user address to check
    /// @return staked amount of rvrs
    function getStakedRvrs(address _addr) external view override returns (uint256) {
        return userInfo[_addr].amount;
    }

    /// @dev explicity override multiple inheritance
    function totalSupply() public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.totalSupply();
    }

    /// @dev explicity override multiple inheritance
    function balanceOf(address account) public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice deposits RVRS into contract
    /// @param _amount the amount of rvrs to deposit
    /// @param _restakeRewards the amount of rvrs to deposit
    function deposit(uint256 _amount, bool _restakeRewards) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');
        _deposit(_amount, msg.sender, _restakeRewards);
    }

    /// @notice deposits RVRS into contract
    /// @param _amount the amount of rvrs to deposit
    /// @param _to the user to deposit for
    function enter(uint256 _amount, address _to) external nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');
        require(authorized[msg.sender], 'not authorized');
        _deposit(_amount, _to, true);
    }

    function _deposit(uint256 _amount, address _to, bool _restakeRewards) internal {
        _update();
        if (isUser(_to)) {
            // if user exists, first, claim their rewards
            _claim(_to, _restakeRewards);
            // then, increment their holdings
            userInfo[_to].amount += _amount;
        } else {
            // add new user to mapping
            userInfo[_to].amount = _amount;
            userInfo[_to].lastClaim = block.timestamp;
        }
        // mint an initial amount of veRVRS after claiming rewards
        _mintInitialOnDeposit(_to, _amount);

        // sync reward debts after deposits and mints
        userInfo[_to].rewardDebt = userInfo[_to].amount.mul(accRewardPerShare).div(ACC_REWARD_PRECISION);
        userInfo[_to].rewardDebtVeRvrs = balanceOf(_to).mul(accRewardPerVeShare).div(ACC_REWARD_PRECISION);
        userInfo[_to].lastDeposit = block.timestamp;

        // Get rvrs from user
        totalStaked += _amount;
        rvrs.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(_to, _amount);
    }

    /// @notice claims accumulated rvrs and veRvrs
    /// @param _restakeRewards whether to re-stake the accumulated RVRS
    function claim(bool _restakeRewards) external override nonReentrant whenNotPaused {
        require(rewardsStarted, 'rewards not started yet');
        require(isUser(msg.sender), 'user has no stake');
        UserInfo storage user = userInfo[msg.sender];

        _update();
        _claim(msg.sender, _restakeRewards);
        // Update reward debts AFTER minting veRVRS
        user.rewardDebt = user.amount.mul(accRewardPerShare).div(ACC_REWARD_PRECISION);
        user.rewardDebtVeRvrs = balanceOf(msg.sender).mul(accRewardPerVeShare).div(ACC_REWARD_PRECISION);
    }

    function _mintInitialOnDeposit(address _to, uint256 _amount) internal {
        uint256 initialMint = _amount.mul(initialDepositMint).div(TOTAL_PERC);
        _mint(_to, initialMint);
    }

    /// @dev private update function
    /// @notice This works like a masterchef updatePool function
    /// @notice This will harvest rewards and update the accumulated Rewards
    function _update() private {
        if (!rewardsStarted) {
            return;
        }
        if (block.timestamp <= lastRewardTime) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 amountBefore = rvrs.balanceOf(address(this));
        IMasterchef(masterchef).harvest(pid, address(this));
        uint256 reward = rvrs.balanceOf(address(this)).sub(amountBefore);
        totalRewardsClaimed += reward;
        if (reward == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 accReward = reward.mul( ACC_REWARD_PRECISION );

        // increment accumulated rewards
        accRewardPerShare += accReward.mul(TOTAL_PERC.sub(percVeRvrsReward)).div(TOTAL_PERC).div(totalStaked);
        accRewardPerVeShare += accReward.mul(percVeRvrsReward).div(TOTAL_PERC).div(totalSupply());
        lastRewardTime = block.timestamp;
    }

    function accRewardPerShareNow() public view returns (uint256) {
        // Have to do 90% since masterchef doesn't account for it
        uint256 pendingTotal = IMasterchef(masterchef).pendingReward(pid, address(this)).mul(ACC_REWARD_PRECISION).mul(9).div(10);
        return accRewardPerShare + pendingTotal.mul(TOTAL_PERC.sub(percVeRvrsReward)).div(TOTAL_PERC).div(totalStaked);
    }

    function accRewardPerVeShareNow() public view returns (uint256) {
        // Have to do 90% since masterchef doesn't account for it
        uint256 pendingTotal = IMasterchef(masterchef).pendingReward(pid, address(this)).mul(ACC_REWARD_PRECISION).mul(9).div(10);
        return accRewardPerVeShare + pendingTotal.mul(percVeRvrsReward).div(TOTAL_PERC).div(totalSupply());
    }

    /// @dev pending RVRS rewards if they claim
    /// @param _user the address of the user
    function pendingRewards(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (user.amount == 0) {
            return 0;
        }
        uint256 pending = user.amount.mul(accRewardPerShareNow()).div(ACC_REWARD_PRECISION).sub(user.rewardDebt);
        pending += balanceOf(_user).mul(accRewardPerVeShareNow()).div(ACC_REWARD_PRECISION).sub(user.rewardDebtVeRvrs);
        return pending;
    }

    /// @dev private claim function
    /// @param _user the address of the user to claim from
    /// @param _restakeRewards whether to re-stake the accumulated RVRS
    function _claim(address _user, bool _restakeRewards) private {
        if (!rewardsStarted) {
            return;
        }
        uint256 amount = _claimable(_user);
        UserInfo storage user = userInfo[_user];

        // update last claim time
        user.lastClaim = block.timestamp;

        // Send pending rewards before minting
        uint256 pending = user.amount.mul(accRewardPerShare).div(ACC_REWARD_PRECISION).sub(user.rewardDebt);
        pending += balanceOf(_user).mul(accRewardPerVeShare).div(ACC_REWARD_PRECISION).sub(user.rewardDebtVeRvrs);

        if (amount > 0) {
            _mint(_user, amount);
        }

        if (pending > 0) {
            if (_restakeRewards) {
                // Re-stake pending rvrs
                _autostake(pending, _user);
            } else {
                rvrs.safeTransfer(_user, pending);
            }
        }
        emit Claimed(_user, pending, _restakeRewards);
    }

    function _autostake(uint256 _amount, address _to) internal {
        // then, increment their holdings
        userInfo[_to].amount += _amount;
        userInfo[_to].lastDeposit = block.timestamp;
        // mint an initial amount of veRVRS after claiming rewards
        _mintInitialOnDeposit(_to, _amount);
        // already have tokens here so no transfers
        totalStaked += _amount;
    }

    /// @notice Calculate the amount of veRvrs that can be claimed by user
    /// @param _user the address to check
    /// @return amount of veRvrs that can be claimed by user
    function claimable(address _user) external view returns (uint256) {
        require(_user != address(0), 'zero address');
        return _claimable(_user);
    }

    /// @dev private claim function
    /// @param _user the address of the user to claim from
    function _claimable(address _user) private view returns (uint256) {
        UserInfo storage user = userInfo[_user];

        // get seconds elapsed since last claim
        uint256 secondsElapsed = block.timestamp - user.lastClaim;

        // calculate pending amount
        uint256 pending = user.amount.mul(secondsElapsed).mul(generationRate).div(1e18);

        // get user's veRvrs balance
        uint256 userVeRvrsBalance = balanceOf(_user);

        // user veRvrs balance cannot go above user.amount * maxCap
        uint256 maxveRvrsCap = user.amount * maxCap;

        // first, check that user hasn't reached the max limit yet
        if (userVeRvrsBalance < maxveRvrsCap) {
            // then, check if pending amount will make user balance overpass maximum amount
            if ((userVeRvrsBalance + pending) > maxveRvrsCap) {
                return maxveRvrsCap - userVeRvrsBalance;
            } else {
                return pending;
            }
        }
        return 0;
    }

    /// @notice withdraws staked rvrs
    /// @param _amount the amount of rvrs to unstake
    /// Note Beware! you will lose all of your veRvrs if you unstake any amount of rvrs!
    function withdraw(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to withdraw cannot be zero');
        require(userInfo[msg.sender].amount >= _amount, 'not enough balance');
        UserInfo storage user = userInfo[msg.sender];
        // update and claim first
        _update();
        _claim(msg.sender, false);

        // update his balance before burning or sending back rvrs
        user.amount -= _amount;

        // get user veRvrs balance that must be burned
        uint256 userVeRvrsBalance = balanceOf(msg.sender);

        _burn(msg.sender, userVeRvrsBalance);

        totalStaked -= _amount;
        uint256 fee = 0;
        if (withdrawFee > 0) {
            if (block.timestamp - user.lastDeposit < withdrawFeeTime) {
                fee = _amount.mul(withdrawFee).div(TOTAL_PERC);
                if (fee > 0) {
                    _amount = _amount.sub(fee);
                    rvrs.safeTransfer(rvrsDAO, fee);
                }
            }
        }
        // Update reward debts AFTER updating rvrs balance
        user.rewardDebt =  user.amount.mul(accRewardPerShare).div(ACC_REWARD_PRECISION);
        user.rewardDebtVeRvrs = 0;

        // send back the staked rvrs
        rvrs.safeTransfer(msg.sender, _amount);
        emit Unstaked(msg.sender, _amount, fee);
    }

    /// @notice get votes for veRvrs
    /// @dev votes should only count if account has > threshold% of current cap reached
    /// @dev invVoteThreshold = (1/threshold%)*100
    /// @return the valid votes
    function getVotes(address _account) external view virtual override returns (uint256) {
        uint256 veRvrsBalance = balanceOf(_account);

        // check that user has more than voting threshold of maxCap and has rvrs in stake
        if (veRvrsBalance * invVoteThreshold > userInfo[_account].amount * maxCap && isUser(_account)) {
            return veRvrsBalance;
        } else {
            return 0;
        }
    }

    function recoverToken(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(rvrs), "cannot withdraw RVRS");
        IERC20(tokenAddress).transfer(msg.sender, IERC20(tokenAddress).balanceOf(address(this)));
    }
}
