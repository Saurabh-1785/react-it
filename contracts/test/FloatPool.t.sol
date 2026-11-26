// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {FloatPool} from "../src/FloatPool.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";

contract FloatPoolTest is Test {
    FloatPool public pool;
    MockUSD public token;

    address public callbackReceiver = address(0xCA11);
    address public lp = address(0x100);
    address public userAccount = address(0x200);
    address public settler = address(0x300);

    bytes32 public sampleRequestId = keccak256("req_float_1");

    function setUp() public {
        token = new MockUSD();
        pool = new FloatPool(address(token), callbackReceiver);

        // Mint initial tokens to LP and settler
        token.mint(lp, 100_000 * 1e6);
        token.mint(settler, 100_000 * 1e6);
    }

    function test_DepositAndWithdraw_Success() public {
        uint256 depositAssets = 10_000 * 1e6;

        vm.startPrank(lp);
        token.approve(address(pool), depositAssets);
        uint256 shares = pool.deposit(depositAssets, lp);
        vm.stopPrank();

        assertEq(shares, depositAssets, "Initial shares should equal assets 1:1");
        assertEq(pool.totalDeposited(), depositAssets);
        assertEq(pool.totalShares(), shares);
        assertEq(token.balanceOf(address(pool)), depositAssets);

        // Withdraw half
        uint256 withdrawShares = shares / 2;
        vm.prank(lp);
        uint256 returnedAssets = pool.withdraw(withdrawShares, lp, lp);

        assertEq(returnedAssets, depositAssets / 2);
        assertEq(pool.totalDeposited(), depositAssets / 2);
        assertEq(pool.totalShares(), shares - withdrawShares);
    }

    function test_Front_SuccessAndAccounting() public {
        // 1. Seed pool liquidity
        vm.startPrank(lp);
        token.approve(address(pool), 50_000 * 1e6);
        pool.deposit(50_000 * 1e6, lp);
        vm.stopPrank();

        uint256 frontAmount = 500 * 1e6;

        // 2. CallbackReceiver calls front
        vm.prank(callbackReceiver);
        bool success = pool.front(userAccount, frontAmount, sampleRequestId);
        assertTrue(success);

        // 3. Verify accounting
        assertEq(pool.outstanding(), frontAmount, "Outstanding credit should match fronted amount");
        assertEq(pool.debt(userAccount), frontAmount, "User debt should record fronted amount");
        assertEq(token.balanceOf(userAccount), frontAmount, "Account should receive fronted funds");
        assertEq(token.balanceOf(address(pool)), (50_000 * 1e6) - frontAmount, "Pool idle liquidity reduced");

        // 4. Verify Solvency: Idle liquidity + outstanding == totalDeposited
        assertEq(token.balanceOf(address(pool)) + pool.outstanding(), pool.totalDeposited());
    }

    function test_RevertIf_FrontCallerNotCallbackReceiver() public {
        vm.prank(userAccount);
        vm.expectRevert(FloatPool.OnlyCallbackReceiver.selector);
        pool.front(userAccount, 100, sampleRequestId);
    }

    function test_RevertIf_CreditLimitExceeded() public {
        vm.startPrank(lp);
        token.approve(address(pool), 50_000 * 1e6);
        pool.deposit(50_000 * 1e6, lp);
        vm.stopPrank();

        // Default limit is 10,000 * 1e6. Attempt 10,001 * 1e6
        uint256 overLimit = 10_001 * 1e6;
        vm.prank(callbackReceiver);
        vm.expectRevert(
            abi.encodeWithSelector(FloatPool.CreditLimitExceeded.selector, userAccount, 0, overLimit, 10_000 * 1e6)
        );
        pool.front(userAccount, overLimit, sampleRequestId);
    }

    function test_RevertIf_UtilisationCapExceeded() public {
        // Deposit 1,000 mUSD. Utilisation cap is 80% (800 mUSD).
        vm.startPrank(lp);
        token.approve(address(pool), 1_000 * 1e6);
        pool.deposit(1_000 * 1e6, lp);
        vm.stopPrank();

        // Attempt to front 850 mUSD (85% utilisation)
        uint256 frontAmount = 850 * 1e6;
        vm.prank(callbackReceiver);
        vm.expectRevert(abi.encodeWithSelector(FloatPool.UtilisationCapExceeded.selector, frontAmount, 800 * 1e6));
        pool.front(userAccount, frontAmount, sampleRequestId);
    }

    function test_Settle_SuccessAndAccounting() public {
        // Setup: deposit and front
        vm.startPrank(lp);
        token.approve(address(pool), 50_000 * 1e6);
        pool.deposit(50_000 * 1e6, lp);
        vm.stopPrank();

        uint256 frontAmount = 1_000 * 1e6;
        vm.prank(callbackReceiver);
        pool.front(userAccount, frontAmount, sampleRequestId);

        // Settle from settler
        vm.startPrank(settler);
        token.approve(address(pool), frontAmount);
        bool settled = pool.settle(sampleRequestId, frontAmount);
        vm.stopPrank();

        assertTrue(settled);
        assertEq(pool.outstanding(), 0, "Outstanding should be 0 after full settlement");
        assertEq(pool.debt(userAccount), 0, "User debt should be cleared");
        assertEq(token.balanceOf(address(pool)), 50_000 * 1e6, "Pool liquidity fully restored");
        assertEq(token.balanceOf(address(pool)) + pool.outstanding(), pool.totalDeposited());
    }

    function test_RevertIf_SettleUnfrontedOrExceeding() public {
        vm.startPrank(settler);
        token.approve(address(pool), 100);
        vm.expectRevert(
            abi.encodeWithSelector(
                FloatPool.InvalidRequestStatus.selector, FloatPool.RequestStatus.None, FloatPool.RequestStatus.Fronted
            )
        );
        pool.settle(sampleRequestId, 100);
        vm.stopPrank();
    }

    function testFuzz_FrontAndSettle(uint64 depositRaw, uint64 frontRaw) public {
        uint256 depositAmount = bound(uint256(depositRaw) * 1e6, 1_000 * 1e6, 1_000_000 * 1e6);
        uint256 maxAllowed = (depositAmount * 8000) / 10000;
        uint256 frontAmount =
            bound(uint256(frontRaw) * 1e6, 1 * 1e6, maxAllowed < 10_000 * 1e6 ? maxAllowed : 10_000 * 1e6);

        token.mint(lp, depositAmount);
        vm.startPrank(lp);
        token.approve(address(pool), depositAmount);
        pool.deposit(depositAmount, lp);
        vm.stopPrank();

        bytes32 reqId = keccak256(abi.encodePacked(depositRaw, frontRaw));
        vm.prank(callbackReceiver);
        pool.front(userAccount, frontAmount, reqId);

        assertEq(pool.outstanding(), frontAmount);
        assertEq(token.balanceOf(address(pool)) + pool.outstanding(), pool.totalDeposited());

        token.mint(settler, frontAmount);
        vm.startPrank(settler);
        token.approve(address(pool), frontAmount);
        pool.settle(reqId, frontAmount);
        vm.stopPrank();

        assertEq(pool.outstanding(), 0);
        assertEq(pool.debt(userAccount), 0);
        assertEq(token.balanceOf(address(pool)), pool.totalDeposited());
    }
}
