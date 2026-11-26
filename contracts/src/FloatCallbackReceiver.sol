// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AbstractCallback} from "@reactive-lib/abstract-base/AbstractCallback.sol";
import {IPayable} from "@reactive-lib/interfaces/IPayable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {FloatPool} from "./FloatPool.sol";
import {PaymentRequestHub} from "./PaymentRequestHub.sol";

/**
 * @title FloatCallbackReceiver
 * @notice Destination callback receiver on Base Sepolia for Zero-Float reactive callbacks.
 * @dev Validates callback provenance: caller must be Reactive Callback Proxy and payload sender must be authorized RVM.
 */
contract FloatCallbackReceiver is AbstractCallback, Ownable2Step {
    /// @notice FloatPool contract providing fronted credit
    FloatPool public floatPool;

    /// @notice PaymentRequestHub origin contract
    PaymentRequestHub public hub;

    /// @notice Records whether a payment request has been acknowledged (Block 3 loop)
    mapping(bytes32 => bool) public ackedRequests;

    /// @notice Records whether a payment request fronting callback has been processed (Block 6 loop)
    mapping(bytes32 => bool) public processedRequests;

    // Events
    event Acked(bytes32 indexed requestId, address indexed rvmId);
    event FrontCompleted(bytes32 indexed requestId, address indexed account, address indexed merchant, uint256 amount);
    event FloatPoolUpdated(address indexed oldPool, address indexed newPool);
    event HubUpdated(address indexed oldHub, address indexed newHub);
    event RvmIdUpdated(address indexed oldRvmId, address indexed newRvmId);
    event CallbackSenderUpdated(address indexed oldSender, address indexed newSender);

    // Custom errors
    error RequestAlreadyAcked(bytes32 requestId);
    error RequestAlreadyProcessed(bytes32 requestId);
    error InvalidToken(address token);

    /**
     * @param _callbackSender Address of Reactive Network callback proxy on Base Sepolia.
     * @param _rvmId Address of the reactive contract deployed on Reactive Omni.
     * @param _floatPool Address of the FloatPool contract.
     * @param _hub Address of the PaymentRequestHub contract.
     */
    constructor(address _callbackSender, address _rvmId, address _floatPool, address _hub)
        AbstractCallback(_callbackSender)
        Ownable(msg.sender)
    {
        rvm_id = _rvmId;
        floatPool = FloatPool(_floatPool);
        hub = PaymentRequestHub(_hub);
    }

    /**
     * @notice Callback endpoint for Block 3 acknowledgment test loop.
     * @param sender Address of the reactive contract on Reactive Omni (injected by callback proxy).
     * @param requestId Unique identifier of the payment request.
     */
    function ack(address sender, bytes32 requestId) external authorizedSenderOnly rvmIdOnly(sender) {
        if (ackedRequests[requestId]) {
            revert RequestAlreadyAcked(requestId);
        }

        ackedRequests[requestId] = true;
        emit Acked(requestId, sender);
    }

    /**
     * @notice Callback endpoint executing the core fronting and payment loop on Base Sepolia.
     * @dev Fronts liquidity from FloatPool into ZeroFloatAccount, then marks hub payment completed.
     * @param sender Reactive contract address injected by proxy.
     * @param requestId Unique request identifier.
     * @param account Payer smart account address.
     * @param merchant Destination recipient merchant address.
     * @param tokenAddress Payment token address.
     * @param amount Token payment amount.
     */
    function frontCallback(
        address sender,
        bytes32 requestId,
        address account,
        address merchant,
        address tokenAddress,
        uint256 amount
    ) external authorizedSenderOnly rvmIdOnly(sender) {
        if (processedRequests[requestId]) {
            revert RequestAlreadyProcessed(requestId);
        }
        if (address(floatPool) != address(0) && tokenAddress != address(floatPool.token())) {
            revert InvalidToken(tokenAddress);
        }
        processedRequests[requestId] = true;

        // 1. Advance liquidity from FloatPool to account
        floatPool.front(account, amount, requestId);

        // 2. Complete payment in hub (routes funds from account to merchant)
        hub.complete(requestId);

        emit FrontCompleted(requestId, account, merchant, amount);
    }

    // --- Admin Configuration ---

    function setFloatPool(address _floatPool) external onlyOwner {
        address old = address(floatPool);
        floatPool = FloatPool(_floatPool);
        emit FloatPoolUpdated(old, _floatPool);
    }

    function setHub(address _hub) external onlyOwner {
        address old = address(hub);
        hub = PaymentRequestHub(_hub);
        emit HubUpdated(old, _hub);
    }

    function setRvmId(address _newRvmId) external onlyOwner {
        address oldRvmId = rvm_id;
        rvm_id = _newRvmId;
        emit RvmIdUpdated(oldRvmId, _newRvmId);
    }

    function setCallbackSender(address _newSender) external onlyOwner {
        address oldSender = address(vendor);
        vendor = IPayable(payable(_newSender));
        addAuthorizedSender(_newSender);
        emit CallbackSenderUpdated(oldSender, _newSender);
    }

    function getRvmId() external view returns (address) {
        return rvm_id;
    }

    function getCallbackSender() external view returns (address) {
        return address(vendor);
    }
}
