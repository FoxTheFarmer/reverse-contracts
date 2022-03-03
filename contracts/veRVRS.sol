// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './VeERC20Upgradeable.sol';
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
    uint256 public maxCap = 4;

    /// @notice Total reverse staked
    uint256 public totalStaked;
    uint256 public lastRewardTime;
    uint256 public accRewardPerShare; // for RVRS
    uint256 public accRewardPerVeShare; // for veRVRS
    uint256 private constant ACC_REWARD_PRECISION = 1e12;

    uint256 public initialDepositMint = 50; // in bips 0.5%
    uint256 public withdrawFee = 500; // in bips
    uint256 public MAX_WITHDRAW_FEE = 2000; // 20%
    uint256 public withdrawFeeTime = 14 days;
    uint256 public MAX_WITHDRAW_FEE_TIME = 90 days;
    uint256 public pid; // pid for custom masterchef pool

    /// @notice the rate of veRvrs generated per second, per rvrs staked
    /// @dev to figure out days to cap, the formula is:
    ///      maxCap * 1e18 / generationRate / 60 / 60 / 24
    /// @dev to reverse engineer generation rate to target a nDays to cap:
    ///      generationRate = maxCap * 1e18 / nDays / 60 / 60 / 24
    uint256 public generationRate = 1111111111111111; // 385802469135;

    /// @notice invVvoteThreshold threshold.
    /// @notice voteThreshold is the percentage of cap from which votes starts to count for governance proposals.
    /// @dev inverse of the threshold to apply.
    /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
    /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
    /// Formula is invVoteThreshold = (1 / th) * 100
    uint256 public invVoteThreshold = 20;

    /// @notice percent of rewards to veRVRS holders,
    /// @notice rest of rewards allocated by RVRS staked
    /// @dev in bips, i.e 100 = 1%
    uint256 public percVeRvrsReward = 3333;
    uint256 public TOTAL_PERC = 10000;

    /// @notice user info mapping
    mapping(address => UserInfo) public userInfo;

    /// @notice user mapping for allowing auto-stake
    mapping(address => bool) public authorized;

    /// @notice events describing staking, unstaking and claiming
    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);

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
        masterchef = _masterchef;
        rvrs = _rvrs;
        rvrsDAO = _rvrsDAO;
        pid = _pid;
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

    /// @notice sets maxCap
    /// @param _maxCap the new max ratio
    /// @dev WARNING - if you lower this, there's no way to reduce it for people over the cap
    function setMaxCap(uint256 _maxCap) external onlyOwner {
        require(_maxCap != 0, 'max cap cannot be zero');
        maxCap = _maxCap;
    }

    /// @notice sets authorized for auto-staking
    /// @param _addr - staking contract
    /// @param _isAuth - bool
    function setAuthorized(address _addr, bool _isAuth) external onlyOwner {
        authorized[_addr] = _isAuth;
    }

    /// @notice sets withdrawFee
    /// @param _withdrawFee the new withdraw fee
    function setWithdrawFee(uint256 _withdrawFee) external onlyOwner {
        require(_withdrawFee <= MAX_WITHDRAW_FEE, 'withdraw fee too high');
        withdrawFee = _withdrawFee;
    }

    /// @notice sets initialDepositMint
    /// @param _initialDepositMint the new withdraw fee
    function setInitialDepositMint(uint256 _initialDepositMint) external onlyOwner {
        require(_initialDepositMint > 0, 'initial mint too low');
        require(_initialDepositMint < 1000, 'initial mint too high');
        initialDepositMint = _initialDepositMint;
    }

    /// @notice sets withdrawFeeTime
    /// @param _withdrawFeeTime the new time
    function setWithdrawFeeTime(uint256 _withdrawFeeTime) external onlyOwner {
        require(_withdrawFeeTime <= MAX_WITHDRAW_FEE_TIME, 'bad withdraw fee time');
        withdrawFeeTime = _withdrawFeeTime;
    }

    /// @notice sets generation rate
    /// @param _generationRate the new max ratio
    function setGenerationRate(uint256 _generationRate) external onlyOwner {
        require(_generationRate != 0, 'generation rate cannot be zero');
        generationRate = _generationRate;
    }

    /// @notice sets invVoteThreshold
    /// @param _invVoteThreshold the new var
    /// Formula is invVoteThreshold = (1 / th) * 100
    function setInvVoteThreshold(uint256 _invVoteThreshold) external onlyOwner {
        // onwner should set a high value if we do not want to implement an important threshold
        require(_invVoteThreshold != 0, 'invVoteThreshold cannot be zero');
        invVoteThreshold = _invVoteThreshold;
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
    function deposit(uint256 _amount) external override nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');
        _deposit(_amount, msg.sender);
    }

    /// @notice deposits RVRS into contract
    /// @param _amount the amount of rvrs to deposit
    function enter(uint256 _amount, address _to) external nonReentrant whenNotPaused {
        require(_amount > 0, 'amount to deposit cannot be zero');
        require(authorized[msg.sender], 'not authorized');
        _deposit(_amount, _to);
    }

    function _deposit(uint256 _amount, address _to) internal {
        _update();
        if (isUser(_to)) {
            // if user exists, first, claim their rewards
            _claim(_to);
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
        rvrs.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice claims accumulated rvrs and veRvrs
    function claim() external override nonReentrant whenNotPaused {
        require(isUser(msg.sender), 'user has no stake');
        UserInfo storage user = userInfo[msg.sender];

        _update();
        _claim(msg.sender);
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
        if (block.timestamp <= lastRewardTime) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        uint256 amountBefore = rvrs.balanceOf(address(this));
        // TODO - handle init with no rewards
        IMasterchef(masterchef).harvest(pid, address(this));
        uint256 reward = rvrs.balanceOf(address(this)).sub(amountBefore);
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

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claim(address _addr) private {
        uint256 amount = _claimable(_addr);
        UserInfo storage user = userInfo[_addr];

        // update last claim time
        user.lastClaim = block.timestamp;

        // Send pending rewards before minting
        uint256 pending = user.amount.mul(accRewardPerShare).div(ACC_REWARD_PRECISION).sub(user.rewardDebt);
        pending += balanceOf(_addr).mul(accRewardPerVeShare).div(ACC_REWARD_PRECISION).sub(user.rewardDebtVeRvrs);

        if (pending > 0) {
            rvrs.safeTransfer(_addr, pending);
        }

        if (amount > 0) {
            emit Claimed(_addr, amount);
            _mint(_addr, amount);
        }
    }

    /// @notice Calculate the amount of veRvrs that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of veRvrs that can be claimed by user
    function claimable(address _addr) external view returns (uint256) {
        require(_addr != address(0), 'zero address');
        return _claimable(_addr);
    }

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claimable(address _addr) private view returns (uint256) {
        UserInfo storage user = userInfo[_addr];

        // get seconds elapsed since last claim
        uint256 secondsElapsed = block.timestamp - user.lastClaim;

        // calculate pending amount
        uint256 pending = user.amount.mul(secondsElapsed).mul(generationRate);

        // get user's veRvrs balance
        uint256 userVeRvrsBalance = balanceOf(_addr);

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
        // claim first
        _claim(msg.sender);

        // update his balance before burning or sending back rvrs
        user.amount -= _amount;

        // get user veRvrs balance that must be burned
        uint256 userVeRvrsBalance = balanceOf(msg.sender);

        _burn(msg.sender, userVeRvrsBalance);

        if (withdrawFee > 0) {
            if (block.timestamp - user.lastDeposit > withdrawFeeTime) {
                uint256 fee = _amount.mul(withdrawFee).div(TOTAL_PERC);
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
}