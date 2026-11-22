// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ZeroFloatReactive} from "../src/ZeroFloatReactive.sol";
import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";
import {PaymentRequestHub} from "../src/PaymentRequestHub.sol";

contract ZeroFloatReactiveTest is Test {
    ZeroFloatReactive public reactive;

    uint256 public constant BASE_CHAIN_ID = 84532;
    address public constant HUB_ADDRESS = address(0x9999);

    address public user = address(0x1111);
    address public merchant = address(0x2222);
    address public token = address(0x3333);

    event Observed(bytes32 indexed requestId, uint256 originTimestamp);
    event PaymentRequestObserved(
        bytes32 indexed requestId,
        address indexed account,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 deadline
    );

    function setUp() public {
        reactive = new ZeroFloatReactive(BASE_CHAIN_ID, HUB_ADDRESS);
    }

    function test_TopicMatchesPaymentRequestHub() public view {
        bytes32 expectedTopic = keccak256("PaymentRequested(bytes32,address,address,address,uint256,uint256)");
        assertEq(reactive.paymentRequestedTopic(), uint256(expectedTopic));
    }

    function test_React_Success() public {
        bytes32 requestId = keccak256("test_request_1");
        uint256 amount = 50 * 1e6;
        uint256 deadline = block.timestamp + 30;

        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: BASE_CHAIN_ID,
            _contract: HUB_ADDRESS,
            topic_0: reactive.paymentRequestedTopic(),
            topic_1: uint256(requestId),
            topic_2: uint256(uint160(user)),
            topic_3: uint256(uint160(merchant)),
            data: abi.encode(token, amount, deadline),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        vm.expectEmit(true, false, false, true);
        emit Observed(requestId, block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit PaymentRequestObserved(requestId, user, merchant, token, amount, deadline);

        reactive.react(log);

        assertTrue(reactive.observedRequests(requestId), "Request should be marked observed");
        assertEq(reactive.totalObserved(), 1, "Total observed count should increment");
    }

    function test_React_IgnoresWrongChainId() public {
        bytes32 requestId = keccak256("test_request_wrong_chain");

        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: 1, // Ethereum mainnet instead of Base Sepolia
            _contract: HUB_ADDRESS,
            topic_0: reactive.paymentRequestedTopic(),
            topic_1: uint256(requestId),
            topic_2: uint256(uint160(user)),
            topic_3: uint256(uint160(merchant)),
            data: abi.encode(token, 100, block.timestamp + 10),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        reactive.react(log);

        assertFalse(reactive.observedRequests(requestId));
        assertEq(reactive.totalObserved(), 0);
    }

    function test_React_IgnoresWrongContract() public {
        bytes32 requestId = keccak256("test_request_wrong_contract");

        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: BASE_CHAIN_ID,
            _contract: address(0xDEAD), // Not hub address
            topic_0: reactive.paymentRequestedTopic(),
            topic_1: uint256(requestId),
            topic_2: uint256(uint160(user)),
            topic_3: uint256(uint160(merchant)),
            data: abi.encode(token, 100, block.timestamp + 10),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        reactive.react(log);

        assertFalse(reactive.observedRequests(requestId));
        assertEq(reactive.totalObserved(), 0);
    }

    function testFuzz_React(bytes32 requestId, uint256 amount, uint32 duration) public {
        vm.assume(duration >= 5);
        uint256 deadline = block.timestamp + duration;

        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: BASE_CHAIN_ID,
            _contract: HUB_ADDRESS,
            topic_0: reactive.paymentRequestedTopic(),
            topic_1: uint256(requestId),
            topic_2: uint256(uint160(user)),
            topic_3: uint256(uint160(merchant)),
            data: abi.encode(token, amount, deadline),
            block_number: 100,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        reactive.react(log);

        assertTrue(reactive.observedRequests(requestId));
    }
}
