// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IYieldDistributor.sol";
import "../vaults/YieldVault.sol";

/**
 * @title YieldDistributor
 *  @notice Collects protocol swap fees + strategy harvest fees and distributes
 *          them to LP stakers, weighted by each vault's capital utilisation.
 *
 *          Two independent reward streams
 *          ──────────────────────────────
 *          1. **Fee rewards** (per-vault, in the vault's underlying stablecoin)
 *             - Sourced from protocol swap fees (FXEngine) and harvest fees (YieldVault).
 *             - When fees arrive via `notifyFees`, `accFeePerShare` is updated
 *               instantly so all current stakers earn proportionally.
 *             - Fees that arrive before any staker are buffered and flushed
 *               the moment the first staker enters.
 *
 *          2. **Bonus rewards** (cross-vault, in a configurable ERC-20 token)
 *             - Dripped at `bonusPerSecond` between `bonusStartTime` and `bonusEndTime`.
 *             - Each vault's share of the drip is its `allocPoint / totalAllocPoint`.
 *             - `allocPoint` is derived from coverage ratio:
 *               higher capital deployment → higher weight → higher bonus.
 *             - Reconfiguring while a period is active carries over the
 *               remaining undistributed bonus into the new period.
 *
 *          Staking model (MasterChef-style)
 *          ─────────────────────────────────
 *          LPs stake their vault shares (yvUSDT, yvSGD, …) in this contract.
 *          Staked shares continue to accrue swap-fee and strategy yield via
 *          ERC-4626 share-price appreciation; the distributor adds the protocol
 *          fee and bonus layers on top.
 *
 *          An `emergencyWithdraw` lets stakers recover shares even when paused.
 */
contract YieldDistributor is IYieldDistributor, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    // ── Constants ────────────────────────────────────────────────────────────
    uint256 public constant PRECISION = 1e18;
    uint256 public constant RATIO_PRECISION = 10_000; // bps

    // ── Vault registry ───────────────────────────────────────────────────────

    struct VaultInfo {
        bool registered;
        IERC20 underlying; // vault's stablecoin (fee reward token)
        uint256 totalStaked; // total vault shares staked here
        uint256 accFeePerShare; // accumulated fee per staked share (×PRECISION)
        uint256 allocPoint; // weight for bonus distribution
        uint256 accBonusPerShare; // accumulated bonus per staked share (×PRECISION)
        uint256 lastBonusTime; // last timestamp bonus was calculated
    }

    struct UserInfo {
        uint256 amount; // vault shares staked
        uint256 feeDebt; // fee reward debt
        uint256 bonusDebt; // bonus reward debt
    }

    address[] public vaultList;
    mapping(address => VaultInfo) public vaults;
    mapping(address => mapping(address => UserInfo)) public users; // vault → user

    /// @notice Fees received while a vault had zero stakers. Flushed into
    ///         accFeePerShare when the first staker arrives.
    mapping(address => uint256) public undistributedFees;

    // ── Bonus reward config ──────────────────────────────────────────────────

    IERC20 public bonusToken;
    uint256 public bonusPerSecond;
    uint256 public bonusStartTime;
    uint256 public bonusEndTime;
    uint256 public totalAllocPoint;

    // ── Fee notifier whitelist ────────────────────────────────────────────────

    mapping(address => bool) public feeNotifiers;

    // ── Events ───────────────────────────────────────────────────────────────

    event VaultRegistered(address indexed vault, uint256 allocPoint);
    event VaultRemoved(address indexed vault);
    event Staked(address indexed vault, address indexed user, uint256 amount);
    event Unstaked(address indexed vault, address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed vault, address indexed user, uint256 amount);
    event FeeClaimed(address indexed vault, address indexed user, uint256 amount);
    event BonusClaimed(address indexed vault, address indexed user, uint256 amount);
    event FeesReceived(address indexed vault, uint256 amount);
    event UndistributedFeesFlushed(address indexed vault, uint256 amount);
    event AllocPointsUpdated();
    event BonusConfigured(address indexed token, uint256 totalAmount, uint256 duration);
    event FeeNotifierUpdated(address indexed notifier, bool allowed);

    // ── Constructor ──────────────────────────────────────────────────────────

    constructor(address owner_) Ownable(owner_) {}

    // =====================================================================
    //  Admin — vault management
    // =====================================================================

    function registerVault(address vault_) external onlyOwner {
        require(vault_ != address(0), "YD: zero vault");
        require(!vaults[vault_].registered, "YD: already registered");

        IERC20 underlying = IERC20(YieldVault(vault_).asset());

        uint256 allocPt = _computeAllocPoint(vault_);
        totalAllocPoint += allocPt;

        vaults[vault_] = VaultInfo({
            registered: true,
            underlying: underlying,
            totalStaked: 0,
            accFeePerShare: 0,
            allocPoint: allocPt,
            accBonusPerShare: 0,
            lastBonusTime: block.timestamp
        });
        vaultList.push(vault_);

        emit VaultRegistered(vault_, allocPt);
    }

    function removeVault(address vault_) external onlyOwner {
        require(vaults[vault_].registered, "YD: not registered");
        require(vaults[vault_].totalStaked == 0, "YD: has stakers");

        totalAllocPoint -= vaults[vault_].allocPoint;
        delete vaults[vault_];

        uint256 len = vaultList.length;
        for (uint256 i = 0; i < len; i++) {
            if (vaultList[i] == vault_) {
                vaultList[i] = vaultList[len - 1];
                vaultList.pop();
                break;
            }
        }
        emit VaultRemoved(vault_);
    }

    // =====================================================================
    //  Admin — fee notifiers
    // =====================================================================

    function setFeeNotifier(address notifier, bool allowed) external onlyOwner {
        feeNotifiers[notifier] = allowed;
        emit FeeNotifierUpdated(notifier, allowed);
    }

    // =====================================================================
    //  Admin — bonus reward configuration
    // =====================================================================

    /// @notice Fund a new bonus reward period.  Transfers `amount` of `token`
    ///         from the caller and drips it over `duration` seconds.
    ///         If the same bonus token still has an active period, the
    ///         remaining undistributed rewards are rolled into the new period.
    function configureBonusReward(address token, uint256 amount, uint256 duration) external onlyOwner {
        require(token != address(0), "YD: zero token");
        require(amount > 0, "YD: zero amount");
        require(duration > 0, "YD: zero duration");

        _massUpdateBonuses();

        uint256 carryOver;
        if (address(bonusToken) == token && block.timestamp < bonusEndTime && bonusPerSecond > 0) {
            carryOver = (bonusEndTime - block.timestamp) * bonusPerSecond;
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 totalReward = amount + carryOver;
        bonusToken = IERC20(token);
        bonusPerSecond = totalReward / duration;
        bonusStartTime = block.timestamp;
        bonusEndTime = block.timestamp + duration;

        emit BonusConfigured(token, totalReward, duration);
    }

    // =====================================================================
    //  Coverage-weighted allocation points
    // =====================================================================

    /// @notice Recalculate every vault's allocation point from its live
    ///         coverage ratio.  Higher capital deployment = higher weight.
    function updateAllocPoints() external onlyOwner {
        _massUpdateBonuses();

        uint256 newTotal;
        for (uint256 i = 0; i < vaultList.length; i++) {
            address v = vaultList[i];
            uint256 newAlloc = _computeAllocPoint(v);
            vaults[v].allocPoint = newAlloc;
            newTotal += newAlloc;
        }
        totalAllocPoint = newTotal;
        emit AllocPointsUpdated();
    }

    // =====================================================================
    //  Fee collection  (called by FXEngine / YieldVault)
    // =====================================================================

    /// @inheritdoc IYieldDistributor
    function notifyFees(address vault_, uint256 amount) external override {
        require(feeNotifiers[msg.sender], "YD: not authorized");
        VaultInfo storage v = vaults[vault_];
        require(v.registered, "YD: vault not registered");

        if (amount == 0) return;

        if (v.totalStaked > 0) {
            uint256 total = amount + undistributedFees[vault_];
            if (undistributedFees[vault_] > 0) {
                emit UndistributedFeesFlushed(vault_, undistributedFees[vault_]);
                undistributedFees[vault_] = 0;
            }
            v.accFeePerShare += (total * PRECISION) / v.totalStaked;
        } else {
            undistributedFees[vault_] += amount;
        }

        emit FeesReceived(vault_, amount);
    }

    // =====================================================================
    //  Staking
    // =====================================================================

    function stake(address vault_, uint256 amount) external nonReentrant whenNotPaused {
        VaultInfo storage v = vaults[vault_];
        UserInfo storage u = users[vault_][msg.sender];
        require(v.registered, "YD: vault not registered");
        require(amount > 0, "YD: zero amount");

        _updateBonusReward(vault_);
        _settleUser(vault_, msg.sender);

        IERC20(vault_).safeTransferFrom(msg.sender, address(this), amount);

        u.amount += amount;
        v.totalStaked += amount;

        // Set debt BEFORE flushing so the new staker benefits from
        // any undistributed fees that accumulated with zero stakers.
        u.feeDebt = (u.amount * v.accFeePerShare) / PRECISION;
        u.bonusDebt = (u.amount * v.accBonusPerShare) / PRECISION;

        uint256 pending = undistributedFees[vault_];
        if (pending > 0) {
            v.accFeePerShare += (pending * PRECISION) / v.totalStaked;
            undistributedFees[vault_] = 0;
            emit UndistributedFeesFlushed(vault_, pending);
        }

        emit Staked(vault_, msg.sender, amount);
    }

    function unstake(address vault_, uint256 amount) external nonReentrant whenNotPaused {
        VaultInfo storage v = vaults[vault_];
        UserInfo storage u = users[vault_][msg.sender];
        require(u.amount >= amount, "YD: insufficient stake");
        require(amount > 0, "YD: zero amount");

        _updateBonusReward(vault_);
        _settleUser(vault_, msg.sender);

        u.amount -= amount;
        v.totalStaked -= amount;
        u.feeDebt = (u.amount * v.accFeePerShare) / PRECISION;
        u.bonusDebt = (u.amount * v.accBonusPerShare) / PRECISION;

        IERC20(vault_).safeTransfer(msg.sender, amount);

        emit Unstaked(vault_, msg.sender, amount);
    }

    /// @notice Withdraw staked shares without claiming rewards.
    ///         Works even when the contract is paused.
    function emergencyWithdraw(address vault_) external nonReentrant {
        UserInfo storage u = users[vault_][msg.sender];
        uint256 amount = u.amount;
        require(amount > 0, "YD: nothing staked");

        VaultInfo storage v = vaults[vault_];
        v.totalStaked -= amount;
        u.amount = 0;
        u.feeDebt = 0;
        u.bonusDebt = 0;

        IERC20(vault_).safeTransfer(msg.sender, amount);

        emit EmergencyWithdrawn(vault_, msg.sender, amount);
    }

    // =====================================================================
    //  Claiming
    // =====================================================================

    function claim(address vault_) external nonReentrant returns (uint256 feeReward, uint256 bonusReward) {
        _updateBonusReward(vault_);
        (feeReward, bonusReward) = _settleUser(vault_, msg.sender);
        UserInfo storage u = users[vault_][msg.sender];
        VaultInfo storage v = vaults[vault_];
        u.feeDebt = (u.amount * v.accFeePerShare) / PRECISION;
        u.bonusDebt = (u.amount * v.accBonusPerShare) / PRECISION;
    }

    function claimAll() external nonReentrant returns (uint256 totalFees, uint256 totalBonus) {
        for (uint256 i = 0; i < vaultList.length; i++) {
            address vault_ = vaultList[i];
            _updateBonusReward(vault_);
            (uint256 f, uint256 b) = _settleUser(vault_, msg.sender);
            UserInfo storage u = users[vault_][msg.sender];
            VaultInfo storage v = vaults[vault_];
            u.feeDebt = (u.amount * v.accFeePerShare) / PRECISION;
            u.bonusDebt = (u.amount * v.accBonusPerShare) / PRECISION;
            totalFees += f;
            totalBonus += b;
        }
    }

    // =====================================================================
    //  Views
    // =====================================================================

    function pendingFees(address vault_, address user_) external view returns (uint256) {
        VaultInfo storage v = vaults[vault_];
        UserInfo storage u = users[vault_][user_];
        if (u.amount == 0) return 0;
        return (u.amount * v.accFeePerShare) / PRECISION - u.feeDebt;
    }

    function pendingBonus(address vault_, address user_) external view returns (uint256) {
        VaultInfo storage v = vaults[vault_];
        UserInfo storage u = users[vault_][user_];
        if (u.amount == 0) return 0;

        uint256 accBonus = v.accBonusPerShare;
        if (v.totalStaked > 0 && block.timestamp > v.lastBonusTime && totalAllocPoint > 0) {
            uint256 elapsed = _bonusElapsed(v.lastBonusTime);
            uint256 reward = elapsed * bonusPerSecond * v.allocPoint / totalAllocPoint;
            accBonus += (reward * PRECISION) / v.totalStaked;
        }
        return (u.amount * accBonus) / PRECISION - u.bonusDebt;
    }

    function getVaultCount() external view returns (uint256) {
        return vaultList.length;
    }

    function getVaultList() external view returns (address[] memory) {
        return vaultList;
    }

    // =====================================================================
    //  Pausable
    // =====================================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // =====================================================================
    //  Internal helpers
    // =====================================================================

    function _computeAllocPoint(address vault_) internal view returns (uint256) {
        uint256 coverage = YieldVault(vault_).currentCoverageRatio();
        return RATIO_PRECISION > coverage ? RATIO_PRECISION - coverage : 0;
    }

    function _bonusElapsed(uint256 from) internal view returns (uint256) {
        uint256 to = block.timestamp < bonusEndTime ? block.timestamp : bonusEndTime;
        return to > from ? to - from : 0;
    }

    function _updateBonusReward(address vault_) internal {
        VaultInfo storage v = vaults[vault_];
        if (v.totalStaked == 0 || totalAllocPoint == 0 || address(bonusToken) == address(0)) {
            v.lastBonusTime = block.timestamp;
            return;
        }

        uint256 elapsed = _bonusElapsed(v.lastBonusTime);
        if (elapsed == 0) return;

        uint256 reward = elapsed * bonusPerSecond * v.allocPoint / totalAllocPoint;
        v.accBonusPerShare += (reward * PRECISION) / v.totalStaked;
        v.lastBonusTime = block.timestamp;
    }

    function _massUpdateBonuses() internal {
        for (uint256 i = 0; i < vaultList.length; i++) {
            _updateBonusReward(vaultList[i]);
        }
    }

    /// @dev Settle pending fee + bonus rewards for a user.  Transfers tokens.
    function _settleUser(address vault_, address user_) internal returns (uint256 feeReward, uint256 bonusReward) {
        VaultInfo storage v = vaults[vault_];
        UserInfo storage u = users[vault_][user_];

        if (u.amount > 0) {
            feeReward = (u.amount * v.accFeePerShare) / PRECISION - u.feeDebt;
            bonusReward = (u.amount * v.accBonusPerShare) / PRECISION - u.bonusDebt;

            if (feeReward > 0) {
                v.underlying.safeTransfer(user_, feeReward);
                emit FeeClaimed(vault_, user_, feeReward);
            }
            if (bonusReward > 0 && address(bonusToken) != address(0)) {
                bonusToken.safeTransfer(user_, bonusReward);
                emit BonusClaimed(vault_, user_, bonusReward);
            }
        }
    }
}
