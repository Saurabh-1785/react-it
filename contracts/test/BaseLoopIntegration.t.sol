// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PaymentRequestHub} from "../src/PaymentRequestHub.sol";
import {FloatPool} from "../src/FloatPool.sol";
import {FloatCallbackReceiver} from "../src/FloatCallbackReceiver.sol";
import {ZeroFloatReactive} from "../src/ZeroFloatReactive.sol";
import {ZeroFloatFactory} from "../src/ZeroFloatFactory.sol";
import {ZeroFloatAccount} from "../src/ZeroFloatAccount.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";
import {IReactive} from "@reactive-lib/interfaces/IReactive.sol";

/**
 * @title BaseLoopIntegrationTest
 * @notice Tests the complete Block 6 core reactive loop on Base Sepolia.
 * @dev Verifies that an account with 0 balance successfully fulfills a merchant payment within seconds.
 */
contract BaseLoopIntegrationTest is Test {
    PaymentRequestHub public hub;
    MockUSD public token;
    FloatPool public pool;
    ZeroFloatFactory public factory;
    FloatCallbackReceiver public receiver;
    ZeroFloatReactive public reactive;

    address public callbackProxy = address(0xCA11BAC);
    address public rvmId;
    address public lp = address(0x10);
    address public customer = address(0x20);
    address public merchant = address(0x30);
    address public customerAccount;

    uint256 public constant BASE_CHAIN_ID = 84532;
    bytes32 public constant SALT = bytes32(uint256(1));

    event PaymentCompleted(bytes32 indexed requestId);
    event FrontCompleted(bytes32 indexed requestId, address indexed account, address indexed merchant, uint256 amount);

    function setUp() public {
        // Warp to realistic timestamp
        vm.warp(1732000000);

        // 1. Deploy Core Token & Origin Hub
        token = new MockUSD();
        hub = new PaymentRequestHub();

        // 2. Deploy FloatPool (receiver wired next)
        pool = new FloatPool(address(token), address(0));

        // 3. Deploy Factory and Customer Account
        factory = new ZeroFloatFactory(address(pool), address(hub), address(token));
        customerAccount = factory.deployAccount(customer, SALT);

        // 4. Deploy FloatCallbackReceiver
        receiver = new FloatCallbackReceiver(
            callbackProxy,
            address(0), // rvmId set once reactive contract is deployed
            address(pool),
            address(hub)
        );

        // 5. Deploy ZeroFloatReactive
        reactive = new ZeroFloatReactive(BASE_CHAIN_ID, address(hub), address(receiver));
        rvmId = address(reactive);

        // 6. Wire authorizations
        receiver.setRvmId(rvmId);
        pool.setCallbackReceiver(address(receiver));

        // 7. Seed FloatPool with LP Liquidity (100,000 mUSD)
        token.mint(lp, 100_000 * 1e6);
        vm.startPrank(lp);
        token.approve(address(pool), 100_000 * 1e6);
        pool.deposit(100_000 * 1e6, lp);
        vm.stopPrank();
    }

    function test_CoreBaseLoop_ZeroBalancePaymentSuccess() public {
        // Verify customer account starts with zero float
        assertEq(token.balanceOf(customerAccount), 0, "Account must start with ZERO balance");
        assertEq(token.balanceOf(merchant), 0, "Merchant starts with 0");

        uint256 paymentAmount = 45 * 1e6; // $45.00 mUSD
        uint256 deadline = block.timestamp + 10; // 10-second payment deadline

        // STEP 1: Merchant creates payment request on Base Sepolia
        vm.prank(merchant);
        bytes32 requestId = hub.requestPayment(customerAccount, merchant, address(token), paymentAmount, deadline);
        assertTrue(requestId != bytes32(0));

        // STEP 2: Reactive Omni detects the PaymentRequested event
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chain_id: BASE_CHAIN_ID,
            _contract: address(hub),
            topic_0: reactive.paymentRequestedTopic(),
            topic_1: uint256(requestId),
            topic_2: uint256(uint160(customerAccount)),
            topic_3: uint256(uint160(merchant)),
            data: abi.encode(address(token), paymentAmount, deadline),
            block_number: 1000,
            op_code: 0,
            block_hash: 0,
            tx_hash: 0,
            log_index: 0
        });

        // Simulate Reactive Omni execution in ReactVM (1 second block time)
        vm.warp(block.timestamp + 1);
        reactive.react(log);
        assertTrue(reactive.observedRequests(requestId), "Reactive contract must observe request");

        // STEP 3: Callback Proxy delivers the callback on Base Sepolia (another ~1 second)
        vm.warp(block.timestamp + 1);

        vm.expectEmit(true, false, false, false);
        emit PaymentCompleted(requestId);

        vm.expectEmit(true, true, true, false);
        emit FrontCompleted(requestId, customerAccount, merchant, paymentAmount);

        vm.prank(callbackProxy);
        receiver.frontCallback(rvmId, requestId, customerAccount, merchant, address(token), paymentAmount);

        // --- VERIFICATIONS ---
        // 1. Merchant received exact payment within window
        assertEq(token.balanceOf(merchant), paymentAmount, "Merchant was paid in full");

        // 2. Customer account returned to ZERO balance (zero float achieved)
        assertEq(token.balanceOf(customerAccount), 0, "Customer account holds 0 float");

        // 3. Payment marked Completed in Hub before deadline
        PaymentRequestHub.PaymentRequest memory req = hub.getRequest(requestId);
        assertEq(uint8(req.status), uint8(PaymentRequestHub.RequestStatus.Completed));
        assertTrue(block.timestamp <= req.deadline, "Payment completed inside deadline window");

        // 4. FloatPool accounting verified
        assertEq(pool.outstanding(), paymentAmount, "Outstanding credit tracked");
        assertEq(pool.debt(customerAccount), paymentAmount, "Customer debt recorded");
        assertEq(token.balanceOf(address(pool)) + pool.outstanding(), pool.totalDeposited(), "Pool solvency holds");

        // STEP 4: Settlement loop test (repayment to pool)
        address settlementReserve = address(0x999);
        token.mint(settlementReserve, paymentAmount);

        vm.startPrank(settlementReserve);
        token.approve(address(pool), paymentAmount);
        pool.settle(requestId, paymentAmount);
        vm.stopPrank();

        // Debt cleared and pool liquidity restored
        assertEq(pool.outstanding(), 0, "Outstanding cleared after settlement");
        assertEq(pool.debt(customerAccount), 0, "Customer debt zeroed");
        assertEq(token.balanceOf(address(pool)), 100_000 * 1e6, "Pool liquidity fully replenished");
    }

    function test_CoreBaseLoop_RevertIf_DuplicateCallback() public {
        uint256 paymentAmount = 20 * 1e6;
        uint256 deadline = block.timestamp + 10;

        bytes32 requestId = hub.requestPayment(customerAccount, merchant, address(token), paymentAmount, deadline);

        // Execute first callback
        vm.prank(callbackProxy);
        receiver.frontCallback(rvmId, requestId, customerAccount, merchant, address(token), paymentAmount);

        // Replay attempt fails due to idempotency
        vm.prank(callbackProxy);
        vm.expectRevert(abi.encodeWithSelector(FloatCallbackReceiver.RequestAlreadyProcessed.selector, requestId));
        receiver.frontCallback(rvmId, requestId, customerAccount, merchant, address(token), paymentAmount);
    }
}
