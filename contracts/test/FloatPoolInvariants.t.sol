// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {FloatPool} from "../src/FloatPool.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";

contract FloatPoolHandler is Test {
    FloatPool public pool;
    MockUSD public token;

    address public callbackReceiver;
    address[] public lps;
    address[] public users;
    bytes32[] public activeRequests;

    uint256 public constant MAX_DEPOSIT = 100_000 * 1e6;

    constructor(FloatPool _pool, MockUSD _token, address _callbackReceiver) {
        pool = _pool;
        token = _token;
        callbackReceiver = _callbackReceiver;

        // Initialize sample actors
        lps.push(address(0x101));
        lps.push(address(0x102));
        users.push(address(0x201));
        users.push(address(0x202));
    }

    function deposit(uint256 lpSeed, uint256 amountRaw) public {
        address lp = lps[lpSeed % lps.length];
        uint256 amount = bound(amountRaw, 100 * 1e6, MAX_DEPOSIT);

        token.mint(lp, amount);
        vm.startPrank(lp);
        token.approve(address(pool), amount);
        pool.deposit(amount, lp);
        vm.stopPrank();
    }

    function withdraw(uint256 lpSeed, uint256 shareFraction) public {
        address lp = lps[lpSeed % lps.length];
        uint256 shares = pool.sharesOf(lp);
        if (shares == 0) return;

        uint256 fraction = bound(shareFraction, 1, 100);
        uint256 sharesToWithdraw = (shares * fraction) / 100;
        if (sharesToWithdraw == 0) return;

        // Check if pool has sufficient liquid assets
        uint256 expectedAssets = (sharesToWithdraw * pool.totalDeposited()) / pool.totalShares();
        if (token.balanceOf(address(pool)) < expectedAssets) return;

        vm.prank(lp);
        pool.withdraw(sharesToWithdraw, lp, lp);
    }

    function front(uint256 userSeed, uint256 amountRaw, uint256 reqNonce) public {
        if (pool.totalDeposited() == 0) return;

        address user = users[userSeed % users.length];
        uint256 maxAllowed = (pool.totalDeposited() * pool.maxUtilisationBps()) / 10000;
        uint256 currentOutstanding = pool.outstanding();
        if (currentOutstanding >= maxAllowed) return;

        uint256 availableCapacity = maxAllowed - currentOutstanding;
        uint256 creditLimitRemaining =
            pool.getCreditLimit(user) > pool.debt(user) ? pool.getCreditLimit(user) - pool.debt(user) : 0;

        uint256 maxFrontable = availableCapacity < creditLimitRemaining ? availableCapacity : creditLimitRemaining;
        uint256 liquidInPool = token.balanceOf(address(pool));
        if (maxFrontable > liquidInPool) maxFrontable = liquidInPool;

        if (maxFrontable < 1 * 1e6) return;

        uint256 amount = bound(amountRaw, 1 * 1e6, maxFrontable);
        bytes32 reqId = keccak256(abi.encodePacked(user, reqNonce, block.timestamp));

        vm.prank(callbackReceiver);
        pool.front(user, amount, reqId);
        activeRequests.push(reqId);
    }

    function settle(uint256 reqSeed) public {
        if (activeRequests.length == 0) return;

        uint256 index = reqSeed % activeRequests.length;
        bytes32 reqId = activeRequests[index];

        (, uint256 amount, FloatPool.RequestStatus status,) = pool.frontRecords(reqId);
        if (status != FloatPool.RequestStatus.Fronted) return;

        // Mint repayment to caller
        token.mint(address(this), amount);
        token.approve(address(pool), amount);
        pool.settle(reqId, amount);

        // Remove settled request
        activeRequests[index] = activeRequests[activeRequests.length - 1];
        activeRequests.pop();
    }
}

contract FloatPoolInvariantsTest is StdInvariant, Test {
    FloatPool public pool;
    MockUSD public token;
    FloatPoolHandler public handler;

    address public callbackReceiver = address(0xCAFE);

    function setUp() public {
        token = new MockUSD();
        pool = new FloatPool(address(token), callbackReceiver);
        handler = new FloatPoolHandler(pool, token, callbackReceiver);

        // Target handler for invariant fuzzing
        targetContract(address(handler));
    }

    /// @notice Invariant: Pool liquid balance + outstanding credit strictly equals total deposited assets
    function invariant_Solvency() public view {
        uint256 liquidBalance = token.balanceOf(address(pool));
        uint256 outstandingCredit = pool.outstanding();
        uint256 deposits = pool.totalDeposited();

        assertEq(
            liquidBalance + outstandingCredit,
            deposits,
            "Solvency invariant violated: idle + outstanding must equal deposits"
        );
    }

    /// @notice Invariant: Outstanding credit never exceeds total deposited assets
    function invariant_OutstandingBoundedByDeposits() public view {
        assertTrue(pool.outstanding() <= pool.totalDeposited(), "Outstanding credit cannot exceed total deposits");
    }
}
