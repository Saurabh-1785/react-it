// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IAccountTopUp {
    function topUp(uint256 amount) external;
}

/**
 * @title FloatPool
 * @notice LP liquidity pool on Base Sepolia providing instant credit for Zero-Float accounts.
 * @dev Tracks per-account debt, aggregate outstanding credit, and per-request lifecycle.
 */
contract FloatPool is Ownable2Step {
    using SafeERC20 for IERC20;

    enum RequestStatus {
        None,
        Fronted,
        Settled,
        Expired
    }

    struct FrontRecord {
        address account;
        uint256 amount;
        RequestStatus status;
        uint256 timestamp;
    }

    /// @notice Underlying settlement token (e.g., mUSD, 6 decimals)
    IERC20 public immutable token;

    /// @notice Authorized callback receiver contract permitted to invoke front()
    address public callbackReceiver;

    /// @notice Authorized settlement source or bridge reserve
    address public bridgeReserve;

    /// @notice Total assets deposited by liquidity providers
    uint256 public totalDeposited;

    /// @notice Total LP shares minted
    uint256 public totalShares;

    /// @notice Total amount of credit currently advanced and unsettled
    uint256 public outstanding;

    /// @notice Maximum allowed pool utilisation in basis points (e.g. 8000 = 80%)
    uint256 public maxUtilisationBps = 8000;
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Default per-account credit limit (e.g., 10,000 mUSD)
    uint256 public defaultCreditLimit = 10_000 * 1e6;

    /// @notice LP share balance per provider
    mapping(address => uint256) public sharesOf;

    /// @notice Per-account outstanding debt
    mapping(address => uint256) public debt;

    /// @notice Custom credit limits overriding default
    mapping(address => uint256) public customCreditLimit;

    /// @notice Mapping of request IDs to front records
    mapping(bytes32 => FrontRecord) public frontRecords;

    // Events
    event Deposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event Fronted(bytes32 indexed requestId, address indexed account, uint256 amount);
    event Settled(bytes32 indexed requestId, address indexed account, uint256 amount);
    event Expired(bytes32 indexed requestId);
    event CallbackReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event BridgeReserveUpdated(address indexed oldReserve, address indexed newReserve);
    event UtilisationCapUpdated(uint256 oldCap, uint256 newCap);
    event CreditLimitUpdated(address indexed account, uint256 newLimit);

    // Custom errors
    error OnlyCallbackReceiver();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientShares();
    error InsufficientPoolLiquidity(uint256 available, uint256 required);
    error CreditLimitExceeded(address account, uint256 currentDebt, uint256 added, uint256 limit);
    error UtilisationCapExceeded(uint256 newOutstanding, uint256 maxAllowed);
    error InvalidRequestStatus(RequestStatus current, RequestStatus expected);
    error SettleAmountExceedsFronted(uint256 requested, uint256 fronted);

    modifier onlyCallbackReceiver() {
        if (msg.sender != callbackReceiver) revert OnlyCallbackReceiver();
        _;
    }

    /**
     * @param _token Underlying ERC20 settlement token
     * @param _callbackReceiver Authorized FloatCallbackReceiver contract
     */
    constructor(address _token, address _callbackReceiver) Ownable(msg.sender) {
        if (_token == address(0)) revert InvalidAddress();
        token = IERC20(_token);
        callbackReceiver = _callbackReceiver;
    }

    /**
     * @notice Deposits assets into the pool in exchange for LP shares.
     * @param assets Amount of tokens to deposit.
     * @param receiver Recipient of the minted LP shares.
     * @return shares Amount of LP shares minted.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        if (assets == 0) revert InvalidAmount();
        if (receiver == address(0)) revert InvalidAddress();

        if (totalShares == 0 || totalDeposited == 0) {
            shares = assets;
        } else {
            shares = (assets * totalShares) / totalDeposited;
        }

        totalShares += shares;
        totalDeposited += assets;
        sharesOf[receiver] += shares;

        token.safeTransferFrom(msg.sender, address(this), assets);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Redeems LP shares for underlying pool assets.
     * @param shares Amount of shares to burn.
     * @param receiver Recipient of the withdrawn assets.
     * @param shareOwner Owner of the LP shares being redeemed.
     * @return assets Amount of underlying assets returned.
     */
    function withdraw(uint256 shares, address receiver, address shareOwner) external returns (uint256 assets) {
        if (shares == 0) revert InvalidAmount();
        if (receiver == address(0) || shareOwner == address(0)) revert InvalidAddress();
        if (sharesOf[shareOwner] < shares) revert InsufficientShares();
        if (msg.sender != shareOwner) {
            // Note: simple direct redemption for owner; in standard flows caller is owner
            if (msg.sender != owner()) revert InsufficientShares();
        }

        assets = (shares * totalDeposited) / totalShares;
        uint256 availableLiquidity = token.balanceOf(address(this));
        if (availableLiquidity < assets) {
            revert InsufficientPoolLiquidity(availableLiquidity, assets);
        }

        sharesOf[shareOwner] -= shares;
        totalShares -= shares;
        totalDeposited -= assets;

        token.safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, shareOwner, assets, shares);
    }

    /**
     * @notice Advances liquidity directly to a user's ZeroFloatAccount for an active request.
     * @dev Restricted strictly to the authorized FloatCallbackReceiver.
     * @param account Payer smart account address.
     * @param amount Token amount to advance.
     * @param requestId Payment request identifier.
     */
    function front(address account, uint256 amount, bytes32 requestId) external onlyCallbackReceiver returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        FrontRecord storage record = frontRecords[requestId];
        if (record.status != RequestStatus.None) {
            revert InvalidRequestStatus(record.status, RequestStatus.None);
        }

        // 1. Credit Limit Check
        uint256 limit = getCreditLimit(account);
        uint256 currentDebt = debt[account];
        if (currentDebt + amount > limit) {
            revert CreditLimitExceeded(account, currentDebt, amount, limit);
        }

        // 2. Utilisation Cap Check
        uint256 maxOutstanding = (totalDeposited * maxUtilisationBps) / BPS_DENOMINATOR;
        if (outstanding + amount > maxOutstanding) {
            revert UtilisationCapExceeded(outstanding + amount, maxOutstanding);
        }

        // 3. Pool Liquidity Check
        uint256 available = token.balanceOf(address(this));
        if (available < amount) {
            revert InsufficientPoolLiquidity(available, amount);
        }

        // Update State
        record.account = account;
        record.amount = amount;
        record.status = RequestStatus.Fronted;
        record.timestamp = block.timestamp;

        debt[account] += amount;
        outstanding += amount;

        // Transfer funds to account
        token.safeTransfer(account, amount);

        // Notify smart account if deployed
        if (account.code.length > 0) {
            try IAccountTopUp(account).topUp(amount) {} catch {}
        }

        emit Fronted(requestId, account, amount);
        return true;
    }

    /**
     * @notice Settles an outstanding fronted amount, replenishing pool liquidity.
     * @param requestId The request ID being settled.
     * @param amount The token amount to repay.
     */
    function settle(bytes32 requestId, uint256 amount) external returns (bool) {
        FrontRecord storage record = frontRecords[requestId];
        if (record.status != RequestStatus.Fronted) {
            revert InvalidRequestStatus(record.status, RequestStatus.Fronted);
        }
        if (amount > record.amount) {
            revert SettleAmountExceedsFronted(amount, record.amount);
        }

        record.status = RequestStatus.Settled;
        address account = record.account;

        debt[account] = debt[account] >= amount ? debt[account] - amount : 0;
        outstanding = outstanding >= amount ? outstanding - amount : 0;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Settled(requestId, account, amount);
        return true;
    }

    /**
     * @notice Marks an unfronted request as expired.
     */
    function expire(bytes32 requestId) external {
        FrontRecord storage record = frontRecords[requestId];
        if (record.status != RequestStatus.None) {
            revert InvalidRequestStatus(record.status, RequestStatus.None);
        }
        record.status = RequestStatus.Expired;
        emit Expired(requestId);
    }

    /**
     * @notice Returns effective credit limit for an account.
     */
    function getCreditLimit(address account) public view returns (uint256) {
        uint256 custom = customCreditLimit[account];
        return custom > 0 ? custom : defaultCreditLimit;
    }

    /**
     * @notice Total assets managed by pool (idle balance in contract + unsettled outstanding credit).
     */
    function totalAssets() external view returns (uint256) {
        return token.balanceOf(address(this)) + outstanding;
    }

    // --- Admin Configuration ---

    function setCallbackReceiver(address _callbackReceiver) external onlyOwner {
        address old = callbackReceiver;
        callbackReceiver = _callbackReceiver;
        emit CallbackReceiverUpdated(old, _callbackReceiver);
    }

    function setBridgeReserve(address _bridgeReserve) external onlyOwner {
        address old = bridgeReserve;
        bridgeReserve = _bridgeReserve;
        emit BridgeReserveUpdated(old, _bridgeReserve);
    }

    function setMaxUtilisationBps(uint256 _bps) external onlyOwner {
        if (_bps > BPS_DENOMINATOR) revert InvalidAmount();
        uint256 old = maxUtilisationBps;
        maxUtilisationBps = _bps;
        emit UtilisationCapUpdated(old, _bps);
    }

    function setCustomCreditLimit(address account, uint256 limit) external onlyOwner {
        customCreditLimit[account] = limit;
        emit CreditLimitUpdated(account, limit);
    }

    function setDefaultCreditLimit(uint256 limit) external onlyOwner {
        defaultCreditLimit = limit;
        emit CreditLimitUpdated(address(0), limit);
    }
}
