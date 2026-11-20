// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title PaymentRequestHub
 * @notice Origin contract on Base Sepolia for merchants to emit time-bounded payment requests.
 * @dev Reactive Omni subscribes to PaymentRequested events to coordinate liquidity fronting and settlement.
 */
contract PaymentRequestHub {
    enum RequestStatus {
        None,
        Requested,
        Completed,
        Expired
    }

    struct PaymentRequest {
        address account;
        address merchant;
        address token;
        uint256 amount;
        uint256 deadline;
        RequestStatus status;
    }

    /// @notice Minimum payment window in seconds (ensures sufficient time for cross-chain reactive loop)
    uint256 public constant MIN_WINDOW = 5;

    /// @notice Nonce tracker per account to ensure unique request IDs
    mapping(address => uint256) public nonces;

    /// @notice Storage of all payment requests indexed by requestId
    mapping(bytes32 => PaymentRequest) public requests;

    /// @notice Emitted when a merchant initiates a payment request
    event PaymentRequested(
        bytes32 indexed requestId,
        address indexed account,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 deadline
    );

    /// @notice Emitted when a payment request is completed
    event PaymentCompleted(bytes32 indexed requestId);

    /// @notice Emitted when an expired payment request is closed
    event PaymentExpired(bytes32 indexed requestId);

    // Custom errors
    error InvalidAddress();
    error InvalidAmount();
    error DeadlineInPast(uint256 deadline, uint256 currentTimestamp);
    error WindowBelowMinimum(uint256 window, uint256 minWindow);
    error RequestNotFound(bytes32 requestId);
    error InvalidStatus(RequestStatus current, RequestStatus expected);
    error DeadlineExceeded(uint256 deadline, uint256 currentTimestamp);
    error DeadlineStillActive(uint256 deadline, uint256 currentTimestamp);

    /**
     * @notice Initiates a payment request against a customer account.
     * @param account The address of the payer account.
     * @param merchant The recipient of the funds.
     * @param token The ERC20 payment token address.
     * @param amount The token amount to pay.
     * @param deadline Unix timestamp in seconds after which the request is invalid.
     * @return requestId Unique identifier for the payment request.
     */
    function requestPayment(address account, address merchant, address token, uint256 amount, uint256 deadline)
        external
        returns (bytes32 requestId)
    {
        if (account == address(0) || merchant == address(0) || token == address(0)) {
            revert InvalidAddress();
        }
        if (amount == 0) {
            revert InvalidAmount();
        }
        if (deadline <= block.timestamp) {
            revert DeadlineInPast(deadline, block.timestamp);
        }
        if (deadline < block.timestamp + MIN_WINDOW) {
            revert WindowBelowMinimum(deadline - block.timestamp, MIN_WINDOW);
        }

        uint256 accountNonce = nonces[account]++;
        requestId = keccak256(
            abi.encode(block.chainid, address(this), account, merchant, token, amount, deadline, accountNonce)
        );

        requests[requestId] = PaymentRequest({
            account: account,
            merchant: merchant,
            token: token,
            amount: amount,
            deadline: deadline,
            status: RequestStatus.Requested
        });

        emit PaymentRequested(requestId, account, merchant, token, amount, deadline);
    }

    /**
     * @notice Marks a payment request as completed.
     * @param requestId The ID of the payment request.
     */
    function complete(bytes32 requestId) external {
        PaymentRequest storage req = requests[requestId];
        if (req.status == RequestStatus.None) {
            revert RequestNotFound(requestId);
        }
        if (req.status != RequestStatus.Requested) {
            revert InvalidStatus(req.status, RequestStatus.Requested);
        }
        if (block.timestamp > req.deadline) {
            revert DeadlineExceeded(req.deadline, block.timestamp);
        }

        req.status = RequestStatus.Completed;
        emit PaymentCompleted(requestId);
    }

    /**
     * @notice Closes an uncompleted request whose deadline has elapsed.
     * @param requestId The ID of the payment request.
     */
    function expire(bytes32 requestId) external {
        PaymentRequest storage req = requests[requestId];
        if (req.status == RequestStatus.None) {
            revert RequestNotFound(requestId);
        }
        if (req.status != RequestStatus.Requested) {
            revert InvalidStatus(req.status, RequestStatus.Requested);
        }
        if (block.timestamp <= req.deadline) {
            revert DeadlineStillActive(req.deadline, block.timestamp);
        }

        req.status = RequestStatus.Expired;
        emit PaymentExpired(requestId);
    }

    /**
     * @notice Returns payment request details.
     * @param requestId The identifier of the payment.
     */
    function getRequest(bytes32 requestId) external view returns (PaymentRequest memory) {
        return requests[requestId];
    }
}
