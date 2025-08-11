// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZCHFSavingsManagerTestBase} from "./helpers/ZCHFSavingsManagerTestBase.sol";
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";
import {IZCHFErrors} from "./interfaces/IZCHFErrors.sol";

/// @title ZCHFSavingsManager_RedeemDeposits
/// @notice Unit tests for the redeemDeposits() function. These tests
/// validate access control, error conditions and correct computation of
/// principal plus interest when withdrawing deposits.
contract ZCHFSavingsManager_RedeemDeposits is ZCHFSavingsManagerTestBase {
    // Declare events for expectEmit
    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    /// @notice Only the operator should be able to call redeemDeposits().
    function testRevertRedeemWhenCallerNotOperator() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));
        vm.prank(user);
        vm.expectRevert();
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Receiver must hold the RECEIVER_ROLE or the call should revert.
    function testRevertRedeemWhenReceiverInvalid() public {
        // create a valid deposit first
        depositExample(bytes32(uint256(1)), 100, user);
        // use an address without the role
        address invalidReceiver = makeAddr("invalidReceiver");
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.InvalidReceiver.selector, invalidReceiver));
        manager.redeemDeposits(ids, invalidReceiver);
    }

    /// @notice Redeeming a non-existing deposit should revert.
    function testRevertRedeemWhenDepositNotFound() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(999));
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.DepositNotFound.selector, ids[0]));
        manager.redeemDeposits(ids, receiver);
    }

    /// @notice Redeeming a single deposit should withdraw principal plus net interest,
    /// emit an event and clear the deposit.
    function testRedeemSingleDeposit() public {
        // Set up a large deposit to ensure positive interest accrues. Using
        // 1e20 units keeps calculations within the uint192 range while
        // generating non-zero interest.
        uint192 amount = 1e20;
        bytes32 id = bytes32(uint256(123));
        uint40 createdAt = uint40(block.timestamp);

        // Create the deposit
        vm.warp(block.timestamp);
        depositExample(id, amount, user);

        // Retrieve the stored deposit to access ticksAtDeposit
        (uint192 storedInitial, uint40 storedCreatedAt, uint64 storedTicksAtDeposit) = manager.deposits(id);
        assertEq(storedInitial, amount);
        assertEq(storedCreatedAt, createdAt);

        // Simulate a large number of tick increments so that totalInterest > 0.
        // Choose deltaTicks = 1e10.
        uint64 deltaTicks = 10_000_000_000;
        savings.setTick(storedTicksAtDeposit + deltaTicks);

        // Advance time by 30 days to accumulate some fee exposure.
        uint256 duration = 30 days;
        vm.warp(block.timestamp + duration);

        // Compute expected values using the contract's formula
        uint256 totalInterest = uint256(deltaTicks) * amount / 1_000_000 / 365 days;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee = feeTicks * amount / 1_000_000 / 365 days;
        uint256 expectedNet = totalInterest > fee ? totalInterest - fee : 0;
        uint192 expectedTotal = uint192(amount + expectedNet);

        // Expect a DepositRedeemed event
        vm.expectEmit(true, false, false, true);
        emit DepositRedeemed(id, expectedTotal);

        // Redeem the deposit
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = id;
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Verify that the savings module withdrawal was correct
        assertEq(savings.lastWithdrawTarget(), receiver);
        assertEq(savings.lastWithdrawAmount(), expectedTotal);

        // Verify the deposit is cleared
        (uint192 finalPrincipal, uint192 finalInterest) = manager.getDepositDetails(id);
        assertEq(finalPrincipal, 0);
        assertEq(finalInterest, 0);
    }

    /// @notice Redeem multiple deposits in a single call and verify that the
    /// combined amount is withdrawn from the savings module.
    function testRedeemMultipleDeposits() public {
        // Create two deposits with large amounts to ensure interest accrual
        bytes32 id1 = bytes32(uint256(1));
        bytes32 id2 = bytes32(uint256(2));
        uint192 amt1 = 1e19;
        uint192 amt2 = 5e19;
        vm.warp(1); // ensure createdAt is deterministic
        depositExample(id1, amt1, user);
        depositExample(id2, amt2, user);

        // Retrieve their ticksAtDeposit
        (,, uint64 ticksAtDeposit1) = manager.deposits(id1);
        (,, uint64 ticksAtDeposit2) = manager.deposits(id2);
        // Ensure ticksAtDeposit are equal since both deposits were created at the same time
        assertEq(ticksAtDeposit1, ticksAtDeposit2);

        // Simulate 1e9 deltaTicks for both deposits
        uint64 deltaTicks = 1_000_000_000;
        savings.setTick(ticksAtDeposit1 + deltaTicks);

        // Advance time by 15 days
        uint256 duration = 15 days;
        vm.warp(block.timestamp + duration);

        // Compute expected net interest for each deposit
        uint256 totalInterest1 = uint256(deltaTicks) * amt1 / 1_000_000 / 365 days;
        uint256 totalInterest2 = uint256(deltaTicks) * amt2 / 1_000_000 / 365 days;
        uint256 feeableTicks = duration * manager.FEE_ANNUAL_PPM();
        uint256 feeTicks = feeableTicks < deltaTicks ? feeableTicks : deltaTicks;
        uint256 fee1 = feeTicks * amt1 / 1_000_000 / 365 days;
        uint256 fee2 = feeTicks * amt2 / 1_000_000 / 365 days;
        uint256 net1 = totalInterest1 > fee1 ? totalInterest1 - fee1 : 0;
        uint256 net2 = totalInterest2 > fee2 ? totalInterest2 - fee2 : 0;
        uint192 total1 = uint192(amt1 + net1);
        uint192 total2 = uint192(amt2 + net2);
        uint192 expectedTotal = total1 + total2;

        // Expect events in order
        vm.expectEmit(true, false, false, true);
        emit DepositRedeemed(id1, total1);
        vm.expectEmit(true, false, false, true);
        emit DepositRedeemed(id2, total2);

        // Redeem both deposits
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;
        vm.prank(operator);
        manager.redeemDeposits(ids, receiver);

        // Verify aggregated withdrawal
        assertEq(savings.lastWithdrawTarget(), receiver);
        assertEq(savings.lastWithdrawAmount(), expectedTotal);
        // Deposits should be gone
        (uint192 f1,) = manager.getDepositDetails(id1);
        (uint192 f2,) = manager.getDepositDetails(id2);
        assertEq(f1, 0);
        assertEq(f2, 0);
    }
}
