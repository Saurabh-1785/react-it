// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ZeroFloatAccount} from "../src/ZeroFloatAccount.sol";
import {ZeroFloatFactory} from "../src/ZeroFloatFactory.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";

contract ZeroFloatAccountAndFactoryTest is Test {
    ZeroFloatFactory public factory;
    MockUSD public token;

    address public owner = address(0xAAAA);
    address public floatPool = address(0xBBBB);
    address public hub = address(0xCCCC);
    address public merchant = address(0xDDDD);
    address public unauthorized = address(0xEEEE);

    bytes32 public constant TEST_SALT = bytes32(uint256(1));

    function setUp() public {
        token = new MockUSD();
        factory = new ZeroFloatFactory(floatPool, hub, address(token));
    }

    function test_Create2AddressPredictionMatchesDeployed() public {
        address predicted = factory.getAccountAddress(owner, TEST_SALT);
        assertTrue(predicted != address(0), "Predicted address should not be zero");

        address deployed = factory.deployAccount(owner, TEST_SALT);
        assertEq(predicted, deployed, "CREATE2 predicted address must match deployed address");
        assertTrue(factory.isAccount(deployed), "Factory registry should confirm account");
    }

    function test_RevertIf_DeployDuplicate() public {
        factory.deployAccount(owner, TEST_SALT);

        vm.expectRevert();
        factory.deployAccount(owner, TEST_SALT);
    }

    function test_RevertIf_DeployZeroOwner() public {
        vm.expectRevert(ZeroFloatFactory.InvalidAddress.selector);
        factory.deployAccount(address(0), TEST_SALT);
    }

    function test_TopUp_AccessControl() public {
        address accountAddr = factory.deployAccount(owner, TEST_SALT);
        ZeroFloatAccount account = ZeroFloatAccount(accountAddr);

        // Pool can topUp
        vm.prank(floatPool);
        account.topUp(50 * 1e6);

        // Non-pool reverts
        vm.prank(unauthorized);
        vm.expectRevert(ZeroFloatAccount.OnlyFloatPool.selector);
        account.topUp(50 * 1e6);
    }

    function test_PayMerchant_SuccessAndAccessControl() public {
        address accountAddr = factory.deployAccount(owner, TEST_SALT);
        ZeroFloatAccount account = ZeroFloatAccount(accountAddr);

        uint256 paymentAmount = 25 * 1e6;
        // Fund account with mock stablecoin
        token.mint(accountAddr, paymentAmount);
        assertEq(account.balance(), paymentAmount);

        // Unauthorized cannot call payMerchant
        vm.prank(unauthorized);
        vm.expectRevert(ZeroFloatAccount.OnlyHub.selector);
        account.payMerchant(merchant, address(token), paymentAmount);

        // Hub executes payment
        vm.prank(hub);
        account.payMerchant(merchant, address(token), paymentAmount);

        assertEq(token.balanceOf(merchant), paymentAmount);
        assertEq(account.balance(), 0);
    }

    function test_PayMerchant_RevertIf_InsufficientBalance() public {
        address accountAddr = factory.deployAccount(owner, TEST_SALT);
        ZeroFloatAccount account = ZeroFloatAccount(accountAddr);

        vm.prank(hub);
        vm.expectRevert(abi.encodeWithSelector(ZeroFloatAccount.InsufficientBalance.selector, 0, 100 * 1e6));
        account.payMerchant(merchant, address(token), 100 * 1e6);
    }

    function test_Withdraw_SuccessAndAccessControl() public {
        address accountAddr = factory.deployAccount(owner, TEST_SALT);
        ZeroFloatAccount account = ZeroFloatAccount(accountAddr);

        uint256 depositAmount = 100 * 1e6;
        token.mint(accountAddr, depositAmount);

        // Non-owner cannot withdraw
        vm.prank(unauthorized);
        vm.expectRevert(ZeroFloatAccount.OnlyOwner.selector);
        account.withdraw(unauthorized, depositAmount);

        // Owner withdraws
        address recipient = address(0x999);
        vm.prank(owner);
        account.withdraw(recipient, depositAmount);

        assertEq(token.balanceOf(recipient), depositAmount);
        assertEq(account.balance(), 0);
    }

    function testFuzz_Withdraw(uint128 mintAmount, uint128 withdrawAmount) public {
        vm.assume(mintAmount > 0);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= mintAmount);

        address accountAddr = factory.deployAccount(owner, TEST_SALT);
        ZeroFloatAccount account = ZeroFloatAccount(accountAddr);

        token.mint(accountAddr, mintAmount);

        vm.prank(owner);
        account.withdraw(owner, withdrawAmount);

        assertEq(token.balanceOf(owner), withdrawAmount);
        assertEq(account.balance(), mintAmount - withdrawAmount);
    }
}
