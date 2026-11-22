// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive-lib/abstract-base/AbstractReactive.sol";

/**
 * @title ZeroFloatReactive
 * @notice Reactive smart contract deployed on Reactive Omni.
 * @dev Observes PaymentRequested events on Base Sepolia and coordinates cross-chain fronting and settlement.
 */
contract ZeroFloatReactive is AbstractReactive {
    /// @notice Chain ID for Base Sepolia
    uint256 public immutable baseChainId;

    /// @notice Address of PaymentRequestHub on Base Sepolia
    address public immutable hubAddress;

    /// @notice Topic 0 hash for PaymentRequested event
    uint256 public immutable paymentRequestedTopic;

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

    /**
     * @param _baseChainId Chain ID of Base Sepolia (typically 84532)
     * @param _hubAddress Address of PaymentRequestHub contract on Base Sepolia
     */
    constructor(uint256 _baseChainId, address _hubAddress) payable {
        baseChainId = _baseChainId;
        hubAddress = _hubAddress;
        paymentRequestedTopic = uint256(keccak256("PaymentRequested(bytes32,address,address,address,uint256,uint256)"));

        if (!vm) {
            service.subscribe(
                _baseChainId, _hubAddress, paymentRequestedTopic, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
            );
        }
    }

    /**
     * @notice Entry point invoked by Reactive Omni when a subscribed event is intercepted.
     * @param log Record containing event log details from origin chain.
     */
    function react(LogRecord calldata log) external vmOnly {
        // Filter: ensure the event originates from the expected Base Sepolia hub and matches topic
        if (log.chain_id != baseChainId || log._contract != hubAddress || log.topic_0 != paymentRequestedTopic) {
            return;
        }

        bytes32 requestId = bytes32(log.topic_1);
        address account = address(uint160(log.topic_2));
        address merchant = address(uint160(log.topic_3));

        (address token, uint256 amount, uint256 deadline) = abi.decode(log.data, (address, uint256, uint256));

        observedRequests[requestId] = true;
        totalObserved++;

        emit Observed(requestId, block.timestamp);
        emit PaymentRequestObserved(requestId, account, merchant, token, amount, deadline);
    }
}
