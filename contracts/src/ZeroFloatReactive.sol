// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";
import {
    AbstractReactive
} from "@reactive-lib/abstract-base/AbstractReactive.sol";
import {
    Ownable2Step,
    Ownable
} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title ZeroFloatReactive
 * @notice Reactive smart contract deployed on Reactive Omni.
 * @dev Observes PaymentRequested events on Base Sepolia and coordinates cross-chain callbacks.
 */
contract ZeroFloatReactive is AbstractReactive, Ownable2Step {
    /// @notice Chain ID for Base Sepolia
    uint256 public immutable baseChainId;

    /// @notice Address of PaymentRequestHub on Base Sepolia
    address public immutable hubAddress;

    /// @notice Topic 0 hash for PaymentRequested event
    uint256 public immutable paymentRequestedTopic;

    /// @notice Destination callback receiver contract on Base Sepolia
    address public callbackReceiver;

    /// @notice Gas limit for destination callback execution
    uint64 public callbackGasLimit = 400000;

    /// @notice Mapping to track observed payment requests
    mapping(bytes32 => bool) public observedRequests;

    /// @notice Counter of total observed requests
    uint256 public totalObserved;

    /// @notice Emitted when a PaymentRequested event from Base Sepolia is observed by Reactive Omni
    event Observed(bytes32 indexed requestId, uint256 originTimestamp);

    /// @notice Emitted with full details for auditing and tracing
    event PaymentRequestObserved(
        bytes32 indexed requestId,
        address indexed account,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 deadline
    );

    /// @notice Emitted when the destination callback receiver address is updated
    event CallbackReceiverUpdated(
        address indexed oldReceiver,
        address indexed newReceiver
    );

    /// @notice Emitted when the callback gas limit is updated
    event CallbackGasLimitUpdated(uint64 oldLimit, uint64 newLimit);

    /**
     * @param _baseChainId Chain ID of Base Sepolia (typically 84532)
     * @param _hubAddress Address of PaymentRequestHub contract on Base Sepolia
     * @param _callbackReceiver Address of FloatCallbackReceiver on Base Sepolia
     */
    constructor(
        uint256 _baseChainId,
        address _hubAddress,
        address _callbackReceiver
    ) payable Ownable(msg.sender) {
        baseChainId = _baseChainId;
        hubAddress = _hubAddress;
        callbackReceiver = _callbackReceiver;
        paymentRequestedTopic = uint256(
            keccak256(
                "PaymentRequested(bytes32,address,address,address,uint256,uint256)"
            )
        );

        if (!vm) {
            service.subscribe(
                _baseChainId,
                _hubAddress,
                paymentRequestedTopic,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    /**
     * @notice Entry point invoked by Reactive Omni when a subscribed event is intercepted.
     * @param log Record containing event log details from origin chain.
     */
    function react(LogRecord calldata log) external vmOnly {
        // Filter: ensure the event originates from the expected Base Sepolia hub and matches topic
        if (
            log.chain_id != baseChainId ||
            log._contract != hubAddress ||
            log.topic_0 != paymentRequestedTopic
        ) {
            return;
        }

        bytes32 requestId = bytes32(log.topic_1);
        address account = address(uint160(log.topic_2));
        address merchant = address(uint160(log.topic_3));

        (address token, uint256 amount, uint256 deadline) = abi.decode(
            log.data,
            (address, uint256, uint256)
        );

        observedRequests[requestId] = true;
        totalObserved++;

        emit Observed(requestId, block.timestamp);
        emit PaymentRequestObserved(
            requestId,
            account,
            merchant,
            token,
            amount,
            deadline
        );

        // Emit callback to destination receiver on Base Sepolia
        if (callbackReceiver != address(0)) {
            bytes memory payload = abi.encodeWithSignature(
                "frontCallback(address,bytes32,address,address,address,uint256)",
                address(0),
                requestId,
                account,
                merchant,
                token,
                amount
            );
            emit Callback(
                baseChainId,
                callbackReceiver,
                callbackGasLimit,
                payload
            );
        }
    }

    /**
     * @notice Sets the destination callback receiver address on Base Sepolia
     */
    function setCallbackReceiver(address _callbackReceiver) external onlyOwner {
        address oldReceiver = callbackReceiver;
        callbackReceiver = _callbackReceiver;
        emit CallbackReceiverUpdated(oldReceiver, _callbackReceiver);
    }

    /**
     * @notice Configures callback gas limit
     */
    function setCallbackGasLimit(uint64 _gasLimit) external onlyOwner {
        uint64 oldLimit = callbackGasLimit;
        callbackGasLimit = _gasLimit;
        emit CallbackGasLimitUpdated(oldLimit, _gasLimit);
    }
}
