// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ZeroFloatAccount
 * @notice Per-user lightweight spending smart account on Base Sepolia.
 * @dev Maintains minimal or zero float. Fronted funds are routed to merchants instantaneously.
 */
contract ZeroFloatAccount {
    using SafeERC20 for IERC20;

    /// @notice The account owner who can withdraw funds or authorize policies
    address public immutable owner;

    /// @notice The factory contract that deployed this account
    address public immutable factory;

    /// @notice Primary settlement token (mUSD, 6 decimals)
    address public immutable token;

    /// @notice Authorized liquidity pool permitted to call topUp
    address public floatPool;

    /// @notice Authorized PaymentRequestHub permitted to call payMerchant
    address public hub;

    // Events
    event ToppedUp(uint256 amount);
    event MerchantPaid(address indexed merchant, address indexed token, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event FloatPoolUpdated(address indexed oldPool, address indexed newPool);
    event HubUpdated(address indexed oldHub, address indexed newHub);

    // Custom errors
    error OnlyOwner();
    error OnlyFloatPool();
    error OnlyHub();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance(uint256 available, uint256 required);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyFloatPool() {
        if (msg.sender != floatPool) revert OnlyFloatPool();
        _;
    }

    modifier onlyHub() {
        if (msg.sender != hub) revert OnlyHub();
        _;
    }

    /**
     * @param _owner Account owner address
     * @param _floatPool Authorized FloatPool contract address
     * @param _hub Authorized PaymentRequestHub contract address
     * @param _token Mock stablecoin mUSD token address
     */
    constructor(address _owner, address _floatPool, address _hub, address _token) {
        if (_owner == address(0) || _token == address(0)) revert InvalidAddress();

        owner = _owner;
        factory = msg.sender;
        floatPool = _floatPool;
        hub = _hub;
        token = _token;
    }

    /**
     * @notice Records incoming liquidity fronted by the FloatPool.
     * @param amount Token amount topped up.
     */
    function topUp(uint256 amount) external onlyFloatPool {
        if (amount == 0) revert InvalidAmount();
        emit ToppedUp(amount);
    }

    /**
     * @notice Executes payment to a merchant on behalf of the account.
     * @dev Restricted strictly to PaymentRequestHub.
     * @param merchant Destination recipient address.
     * @param paymentToken Address of the ERC20 token being paid.
     * @param amount Token amount to transfer.
     */
    function payMerchant(address merchant, address paymentToken, uint256 amount) external onlyHub {
        if (merchant == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        uint256 currentBal = IERC20(paymentToken).balanceOf(address(this));
        if (currentBal < amount) {
            revert InsufficientBalance(currentBal, amount);
        }

        IERC20(paymentToken).safeTransfer(merchant, amount);
        emit MerchantPaid(merchant, paymentToken, amount);
    }

    /**
     * @notice Allows owner to withdraw any residual float funds.
     * @param to Recipient destination address.
     * @param amount Token amount to withdraw.
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        uint256 currentBal = IERC20(token).balanceOf(address(this));
        if (currentBal < amount) {
            revert InsufficientBalance(currentBal, amount);
        }

        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    /**
     * @notice Configures authorized FloatPool address.
     */
    function setFloatPool(address _floatPool) external {
        if (msg.sender != owner && msg.sender != factory) revert OnlyOwner();
        address oldPool = floatPool;
        floatPool = _floatPool;
        emit FloatPoolUpdated(oldPool, _floatPool);
    }

    /**
     * @notice Configures authorized PaymentRequestHub address.
     */
    function setHub(address _hub) external {
        if (msg.sender != owner && msg.sender != factory) revert OnlyOwner();
        address oldHub = hub;
        hub = _hub;
        emit HubUpdated(oldHub, _hub);
    }

    /**
     * @notice Helper view function returning current float balance of primary token.
     */
    function balance() external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
