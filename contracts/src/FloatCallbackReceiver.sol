// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AbstractCallback} from "@reactive-lib/abstract-base/AbstractCallback.sol";
import {IPayable} from "@reactive-lib/interfaces/IPayable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title FloatCallbackReceiver
 * @notice Destination callback receiver on Base Sepolia for Zero-Float reactive callbacks.
 * @dev Validates callback provenance: caller must be Reactive Callback Proxy and payload sender must be authorized RVM.
 */
contract FloatCallbackReceiver is AbstractCallback, Ownable2Step {
    /// @notice Records whether a payment request has been acknowledged
    mapping(bytes32 => bool) public ackedRequests;

    /// @notice Emitted when a callback acknowledges a request
    event Acked(bytes32 indexed requestId, address indexed rvmId);

    /// @notice Emitted when the authorized RVM ID is updated
    event RvmIdUpdated(address indexed oldRvmId, address indexed newRvmId);

    /// @notice Emitted when the callback proxy sender is updated
    event CallbackSenderUpdated(address indexed oldSender, address indexed newSender);

    error RequestAlreadyAcked(bytes32 requestId);

    /**
     * @param _callbackSender Address of Reactive Network callback proxy on Base Sepolia.
     * @param _rvmId Address of the reactive contract deployed on Reactive Omni.
     */
    constructor(address _callbackSender, address _rvmId) AbstractCallback(_callbackSender) Ownable(msg.sender) {
        rvm_id = _rvmId;
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
     * @notice Updates the authorized reactive contract address on Reactive Omni.
     * @param _newRvmId New reactive contract address.
     */
    function setRvmId(address _newRvmId) external onlyOwner {
        address oldRvmId = rvm_id;
        rvm_id = _newRvmId;
        emit RvmIdUpdated(oldRvmId, _newRvmId);
    }

    /**
     * @notice Updates the authorized callback sender address.
     * @param _newSender New callback proxy address.
     */
    function setCallbackSender(address _newSender) external onlyOwner {
        address oldSender = address(vendor);
        vendor = IPayable(payable(_newSender));
        addAuthorizedSender(_newSender);
        emit CallbackSenderUpdated(oldSender, _newSender);
    }

    /**
     * @notice Returns current authorized RVM ID.
     */
    function getRvmId() external view returns (address) {
        return rvm_id;
    }

    /**
     * @notice Returns current authorized callback proxy vendor.
     */
    function getCallbackSender() external view returns (address) {
        return address(vendor);
    }
}
