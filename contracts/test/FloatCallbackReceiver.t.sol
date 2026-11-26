// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {FloatCallbackReceiver} from "../src/FloatCallbackReceiver.sol";
import {ZeroFloatReactive} from "../src/ZeroFloatReactive.sol";
import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";

contract FloatCallbackReceiverTest is Test {
    FloatCallbackReceiver public receiver;
    ZeroFloatReactive public reactive;

    address public callbackProxy = address(0xCA11BAC);
    address public rvmId = address(0x5555);
    address public randomUser = address(0x9999);
    address public hubAddress = address(0x8888);

    uint256 public constant BASE_CHAIN_ID = 84532;
    bytes32 public sampleRequestId = keccak256("req_123");

    event Acked(bytes32 indexed requestId, address indexed rvmId);
    event Callback(
        uint256 indexed chain_id,
        address indexed _contract,
        uint64 indexed gas_limit,
        bytes payload
    );

    function setUp() public {
        receiver = new FloatCallbackReceiver(
            callbackProxy,
            rvmId,
            address(0),
            address(0)
        );
        reactive = new ZeroFloatReactive(
            BASE_CHAIN_ID,
            hubAddress,
            address(receiver)
        );
    }

    function test_Ack_Success() public {
        // CallbackProxy invokes receiver.ack with authorized rvmId
        vm.prank(callbackProxy);
        vm.expectEmit(true, true, false, false);
        emit Acked(sampleRequestId, rvmId);

        receiver.ack(rvmId, sampleRequestId);
        assertTrue(receiver.ackedRequests(sampleRequestId));
    }

    function test_RevertIf_CallerNotAuthorizedCallbackProxy() public {
        // Random EOA attempts to call ack directly
        vm.prank(randomUser);
        vm.expectRevert("Authorized sender only");
        receiver.ack(rvmId, sampleRequestId);
    }

    function test_RevertIf_InvalidRvmId() public {
        address fakeRvmId = address(0xBAD);

        // CallbackProxy passes wrong RVM ID
        vm.prank(callbackProxy);
        vm.expectRevert("Authorized RVM ID only");
        receiver.ack(fakeRvmId, sampleRequestId);
    }

    function test_RevertIf_DuplicateAck() public {
        vm.prank(callbackProxy);
        receiver.ack(rvmId, sampleRequestId);

        vm.prank(callbackProxy);
        vm.expectRevert(
            abi.encodeWithSelector(
                FloatCallbackReceiver.RequestAlreadyAcked.selector,
                sampleRequestId
            )
        );
        receiver.ack(rvmId, sampleRequestId);
    }

    function test_SetRvmId_Success() public {
        address newRvmId = address(0x7777);
        receiver.setRvmId(newRvmId);
        assertEq(receiver.getRvmId(), newRvmId);

        // Verify new RVM ID can now be acknowledged
        vm.prank(callbackProxy);
        receiver.ack(newRvmId, sampleRequestId);
        assertTrue(receiver.ackedRequests(sampleRequestId));
    }

    function test_RevertIf_NonOwnerSetsRvmId() public {
        vm.prank(randomUser);
        vm.expectRevert();
        receiver.setRvmId(address(0x123));
    }

    function test_ReactiveEmitsCallbackMatchingReceiver() public {
        // Verify ZeroFloatReactive emits a Callback event targeting the receiver
        bytes32 reqId = keccak256("req_reactive_ack");
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: BASE_CHAIN_ID,
            _contract: hubAddress,
            topic_0: reactive.paymentRequestedTopic(),
            topic_1: uint256(reqId),
            topic_2: uint256(uint160(address(0x1))),
            topic_3: uint256(uint160(address(0x2))),
            data: abi.encode(address(0x3), 100, block.timestamp + 20),
            block_number: 1,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        bytes memory expectedPayload = abi.encodeWithSignature(
            "frontCallback(address,bytes32,address,address,address,uint256)",
            address(0),
            reqId,
            address(0x1),
            address(0x2),
            address(0x3),
            100
        );

        vm.expectEmit(true, true, true, true);
        emit Callback(
            BASE_CHAIN_ID,
            address(receiver),
            400000,
            expectedPayload
        );

        reactive.react(log);
    }
}
