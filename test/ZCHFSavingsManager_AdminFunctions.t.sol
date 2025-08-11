// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZCHFSavingsManagerTestBase} from "./helpers/ZCHFSavingsManagerTestBase.sol";
import {IZCHFErrors} from "./interfaces/IZCHFErrors.sol";

/// @title ZCHFSavingsManager_AdminFunctions
/// @notice Tests for the administrative functions moveZCHF() and rescueTokens().
contract ZCHFSavingsManager_AdminFunctions is ZCHFSavingsManagerTestBase {
    // Re-declare events for expectEmit; not used here but kept for completeness.
    event DepositCreated(bytes32 indexed identifier, uint192 amount);
    event DepositRedeemed(bytes32 indexed identifier, uint192 totalAmount);

    /// @notice Ensure that only the operators can call moveZCHF().
    function testRevertMoveZCHFWhenNotOperator() public {
        address normalUser = makeAddr("normalUser");
        vm.prank(normalUser);
        vm.expectRevert();
        manager.moveZCHF(receiver, 100);
    }

    /// @notice Ensure that moveZCHF() requires the receiver to possess the
    /// RECEIVER_ROLE.
    function testRevertMoveZCHFInvalidReceiver() public {
        // Create a deposit so that there is something in the savings module
        depositExample(bytes32(uint256(1)), 1000, user);
        address invalidReceiver = makeAddr("invalidReceiver");
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.InvalidReceiver.selector, invalidReceiver));
        manager.moveZCHF(invalidReceiver, 100);
    }

    /// @notice moveZCHF() should call withdraw() on the savings module and
    /// forward the amount to the receiver. If the requested amount is larger
    /// than the saved balance, the entire balance should be withdrawn.
    function testMoveZCHFWithdrawsCorrectAmount() public {
        // Create a deposit to fund the savings module with 2000 units
        depositExample(bytes32(uint256(1)), 2_000, user);
        // Confirm the savings module balance
        assertEq(savings.saved(), 2_000);
        // Case 1: withdraw less than available
        uint192 requested = 500;
        vm.prank(operator);
        manager.moveZCHF(receiver, requested);
        // The mock will call withdraw with requested
        assertEq(savings.lastWithdrawTarget(), receiver);
        assertEq(savings.lastWithdrawAmount(), requested);
        // The saved balance should decrease accordingly
        assertEq(savings.saved(), 1_500);
        // Case 2: withdraw more than available
        uint192 oversized = 10_000;
        vm.prank(operator);
        manager.moveZCHF(receiver, oversized);
        // The mock will clamp to the remaining balance of 1_500
        assertEq(savings.lastWithdrawAmount(), 1_500);
        assertEq(savings.saved(), 0);
    }

    /// @notice Only the operators should be able to call rescueTokens().
    function testRevertRescueTokensWhenNotOperator() public {
        address normalUser = makeAddr("normalUser");
        vm.prank(normalUser);
        vm.expectRevert();
        manager.rescueTokens(address(token), receiver, 1_000);
    }

    /// @notice rescueTokens() should revert if the receiver lacks the role.
    function testRevertRescueTokensInvalidReceiver() public {
        address invalidReceiver = makeAddr("invalidReceiver2");
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.InvalidReceiver.selector, invalidReceiver));
        manager.rescueTokens(address(token), invalidReceiver, 1_000);
    }

    /// @notice rescueTokens() should transfer ERC20 tokens from the manager
    /// contract to the receiver.
    function testRescueERC20Tokens() public {
        // Send some tokens to the manager
        token.transfer(address(manager), 1_000);
        // Balance before
        uint256 before = token.balanceOf(receiver);
        // Rescue tokens
        vm.prank(operator);
        manager.rescueTokens(address(token), receiver, 500);
        // Receiver should get the tokens
        assertEq(token.balanceOf(receiver), before + 500);
        // Manager's balance should decrease
        assertEq(token.balanceOf(address(manager)), 500);
    }

    /// @notice rescueTokens() should transfer Ether when the token address is zero.
    function testRescueETH() public {
        // Send some Ether to the manager contract
        vm.deal(address(manager), 1 ether);
        uint256 receiverBalanceBefore = receiver.balance;
        uint256 managerBalanceBefore = address(manager).balance;
        // Rescue half an ether
        vm.prank(operator);
        manager.rescueTokens(address(0), receiver, 0.5 ether);
        // Receiver should receive the Ether
        assertEq(receiver.balance, receiverBalanceBefore + 0.5 ether);
        // Manager's balance should decrease accordingly
        assertEq(address(manager).balance, managerBalanceBefore - 0.5 ether);
    }

    /// @notice addZCHF() should revert if called by an address without OPERATOR_ROLE
    function testRevertAddZCHFWhenNotOperator() public {
        address normalUser = makeAddr("normalUser");
        vm.prank(normalUser);
        vm.expectRevert();
        manager.addZCHF(user, 1000);
    }

    /// @notice addZCHF() should revert if amount is zero
    function testRevertAddZCHFWhenZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IZCHFErrors.ZeroAmount.selector));
        manager.addZCHF(user, 0);
    }

    /// @notice addZCHF() should pull tokens from source and forward to savings
    function testAddZCHFWithTransferFrom() public {
        uint192 amount = 1_000;

        // Give operator allowance and balance
        deal(address(token), user, amount);
        vm.prank(user);
        token.approve(address(manager), amount);

        // Expect transferFrom to succeed
        vm.prank(operator);
        manager.addZCHF(user, amount);

        // Confirm tokens were saved
        assertEq(savings.saved(), amount);
    }

    /// @notice addZCHF() should skip transferFrom if source is address(this)
    function testAddZCHFFromContractBalance() public {
        uint192 amount = 777;

        // Pre-fund manager
        deal(address(token), address(manager), amount);

        // Call as operator with source = address(this)
        vm.prank(operator);
        manager.addZCHF(address(manager), amount);

        assertEq(savings.saved(), amount);
    }

    /// @notice addZCHF() should revert if transferFrom fails
    function testRevertAddZCHFFailedTransfer() public {
        uint192 amount = 1000;

        // No allowance or balance for source
        address brokeSource = makeAddr("broke");

        vm.prank(operator);
        vm.expectRevert();
        manager.addZCHF(brokeSource, amount);
    }
}
