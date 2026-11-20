// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PaymentRequestHub} from "../src/PaymentRequestHub.sol";

contract PaymentRequestHubTest is Test {
    PaymentRequestHub public hub;

    address public user = address(0x1111);
    address public merchant = address(0x2222);
    address public token = address(0x3333);

    event PaymentRequested(
        bytes32 indexed requestId,
        address indexed account,
        address indexed merchant,
        address token,
        uint256 amount,
        uint256 deadline
    );
    event PaymentCompleted(bytes32 indexed requestId);
    event PaymentExpired(bytes32 indexed requestId);

    function setUp() public {
        hub = new PaymentRequestHub();
        // Set a realistic starting timestamp
        vm.warp(1700000000);
    }

    function test_RequestPayment_Success() public {
        uint256 amount = 100 * 1e6;
        uint256 deadline = block.timestamp + 10;

        // Expect PaymentRequested event with indexed topics (requestId wildcard, account, merchant)
        vm.expectEmit(false, true, true, true);
        emit PaymentRequested(bytes32(0), user, merchant, token, amount, deadline);

        bytes32 requestId = hub.requestPayment(user, merchant, token, amount, deadline);
        assertTrue(requestId != bytes32(0), "Request ID should not be zero");

        PaymentRequestHub.PaymentRequest memory req = hub.getRequest(requestId);
        assertEq(req.account, user);
        assertEq(req.merchant, merchant);
        assertEq(req.token, token);
        assertEq(req.amount, amount);
        assertEq(req.deadline, deadline);
        assertEq(uint8(req.status), uint8(PaymentRequestHub.RequestStatus.Requested));
        assertEq(hub.nonces(user), 1);
    }

    function test_RevertIf_ZeroAddresses() public {
        uint256 deadline = block.timestamp + 10;

        vm.expectRevert(PaymentRequestHub.InvalidAddress.selector);
        hub.requestPayment(address(0), merchant, token, 100, deadline);

        vm.expectRevert(PaymentRequestHub.InvalidAddress.selector);
        hub.requestPayment(user, address(0), token, 100, deadline);

        vm.expectRevert(PaymentRequestHub.InvalidAddress.selector);
        hub.requestPayment(user, merchant, address(0), 100, deadline);
    }

    function test_RevertIf_ZeroAmount() public {
        uint256 deadline = block.timestamp + 10;
        vm.expectRevert(PaymentRequestHub.InvalidAmount.selector);
        hub.requestPayment(user, merchant, token, 0, deadline);
    }

    function test_RevertIf_DeadlineInPast() public {
        vm.expectRevert(
            abi.encodeWithSelector(PaymentRequestHub.DeadlineInPast.selector, block.timestamp, block.timestamp)
        );
        hub.requestPayment(user, merchant, token, 100, block.timestamp);
    }

    function test_RevertIf_WindowBelowMinimum() public {
        uint256 deadline = block.timestamp + 4; // Below 5 second MIN_WINDOW
        vm.expectRevert(abi.encodeWithSelector(PaymentRequestHub.WindowBelowMinimum.selector, 4, 5));
        hub.requestPayment(user, merchant, token, 100, deadline);
    }

    function test_Complete_Success() public {
        uint256 deadline = block.timestamp + 10;
        bytes32 requestId = hub.requestPayment(user, merchant, token, 100, deadline);

        vm.expectEmit(true, false, false, false);
        emit PaymentCompleted(requestId);

        hub.complete(requestId);

        PaymentRequestHub.PaymentRequest memory req = hub.getRequest(requestId);
        assertEq(uint8(req.status), uint8(PaymentRequestHub.RequestStatus.Completed));
    }

    function test_RevertIf_CompleteAfterDeadline() public {
        uint256 deadline = block.timestamp + 10;
        bytes32 requestId = hub.requestPayment(user, merchant, token, 100, deadline);

        // Fast-forward past deadline
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(PaymentRequestHub.DeadlineExceeded.selector, deadline, deadline + 1));
        hub.complete(requestId);
    }

    function test_Expire_Success() public {
        uint256 deadline = block.timestamp + 10;
        bytes32 requestId = hub.requestPayment(user, merchant, token, 100, deadline);

        // Warp past deadline
        vm.warp(deadline + 1);

        vm.expectEmit(true, false, false, false);
        emit PaymentExpired(requestId);

        hub.expire(requestId);

        PaymentRequestHub.PaymentRequest memory req = hub.getRequest(requestId);
        assertEq(uint8(req.status), uint8(PaymentRequestHub.RequestStatus.Expired));
    }

    function test_RevertIf_ExpireBeforeDeadline() public {
        uint256 deadline = block.timestamp + 10;
        bytes32 requestId = hub.requestPayment(user, merchant, token, 100, deadline);

        vm.expectRevert(
            abi.encodeWithSelector(PaymentRequestHub.DeadlineStillActive.selector, deadline, block.timestamp)
        );
        hub.expire(requestId);
    }

    function test_RevertIf_DoubleCompletion() public {
        uint256 deadline = block.timestamp + 10;
        bytes32 requestId = hub.requestPayment(user, merchant, token, 100, deadline);

        hub.complete(requestId);

        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentRequestHub.InvalidStatus.selector,
                PaymentRequestHub.RequestStatus.Completed,
                PaymentRequestHub.RequestStatus.Requested
            )
        );
        hub.complete(requestId);
    }

    function testFuzz_RequestPayment(uint256 amount, uint32 duration) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.assume(duration >= 5 && duration < 365 days);

        uint256 deadline = block.timestamp + duration;
        bytes32 requestId = hub.requestPayment(user, merchant, token, amount, deadline);

        PaymentRequestHub.PaymentRequest memory req = hub.getRequest(requestId);
        assertEq(req.amount, amount);
        assertEq(req.deadline, deadline);
    }
}
