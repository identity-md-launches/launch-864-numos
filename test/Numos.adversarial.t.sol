// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Numos} from "src/Numos.sol";

/// @dev A plain ERC-20 must not invoke receiver hooks, even for a contract that rejects every call.
contract RejectingNumosRecipient {
    fallback() external {
        revert("recipient was called");
    }
}

contract NumosFactoryProbe {
    function deploy() external returns (Numos) {
        return new Numos();
    }
}

/// forge-config: default.fuzz.runs = 1000
contract NumosAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    Numos internal token;

    function setUp() public {
        token = new Numos();
    }

    function test_ActualFactoryGetsSupplyInsteadOfTransactionOrigin() public {
        NumosFactoryProbe factory = new NumosFactoryProbe();
        vm.prank(ALICE, ALICE);
        Numos launched = factory.deploy();
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_OneWeiTransfersExactlyInBothModes() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1));
        vm.prank(BOB);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(BOB, ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsConsumedAndReplacementIsNotAdditive() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        token.approve(SPENDER, 3);
        assertEq(token.allowance(address(this), SPENDER), 3);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 3));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 4);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4);
    }

    function test_InfiniteApprovalCanBeRevokedThenRegrantedAsFinite() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 2));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_OwnerAlsoNeedsAllowanceForTransferFrom() public {
        token.transfer(ALICE, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 7);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        token.approve(ALICE, 7);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(ALICE, ALICE, 7));
        assertEq(token.balanceOf(ALICE), 7);
        assertEq(token.allowance(ALICE, ALICE), 0);
    }

    function test_AllowanceUsesImmediateCallerNotTransactionOrigin() public {
        token.transfer(ALICE, 2);
        vm.prank(ALICE);
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB, SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, SPENDER), 2);
        vm.prank(SPENDER, BOB);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 1);
    }

    function test_ApprovalCannotBeBorrowedFromAnotherOwnerOrSpender() public {
        token.transfer(ALICE, 10);
        token.transfer(BOB, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(BOB, ALICE, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.allowance(BOB, SPENDER), 0);
        assertEq(token.allowance(ALICE, BOB), 0);
    }

    function test_DirectAndZeroDelegatedTransfersPreserveApprovals() public {
        token.approve(SPENDER, 11);
        token.approve(BOB, type(uint256).max);
        token.transfer(ALICE, 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 0));
        assertEq(token.allowance(address(this), SPENDER), 11);
        assertEq(token.allowance(address(this), BOB), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_MaxUintTransferFromCannotOverflowOrConsumeInfiniteApproval() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedSelfTransferStillRequiresSufficientBalance() public {
        token.transfer(ALICE, 1);
        vm.prank(ALICE);
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(ALICE, SPENDER), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractRecipientsNeedNoCallback() public {
        address recipient = address(new RejectingNumosRecipient());
        assertTrue(token.transfer(recipient, 1));
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), recipient, 2));
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransfersToTokenContractAreAccountedForWithoutBurning() public {
        assertTrue(token.transfer(address(token), 1));
        token.approve(SPENDER, 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(token), 2));
        assertEq(token.balanceOf(address(token)), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceWithSufficientBalanceIsAtomic(uint256 rawBalance, uint256 rawAllowance)
        public
    {
        uint256 balance = bound(rawBalance, 1, SUPPLY);
        uint256 allowance = bound(rawAllowance, 0, balance - 1);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, allowance + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, allowance + 1);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(ALICE, SPENDER), allowance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalanceWithSufficientAllowanceIsAtomic(
        uint256 rawBalance,
        uint256 rawAmount,
        uint256 rawApproval
    ) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        uint256 approval = bound(rawApproval, amount, type(uint256).max);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersEqualOneDirectTransfer(uint256 rawAmount, uint256 rawFirst) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, amount);
        Numos direct = new Numos();
        assertTrue(direct.transfer(ALICE, amount));
        token.approve(SPENDER, amount);
        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        assertTrue(token.transferFrom(address(this), ALICE, amount - first));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), direct.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), direct.balanceOf(address(this)));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(direct.totalSupply(), SUPPLY);
    }

    function testFuzz_TransfersToArbitraryNonzeroRecipientsAreExact(address recipient, uint256 rawAmount) public {
        if (recipient == address(0)) recipient = ALICE;
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 before = token.balanceOf(recipient);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), recipient == address(this) ? before : before + amount);
        assertEq(token.balanceOf(address(this)), recipient == address(this) ? SUPPLY : SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroRecipientFailureRestoresFiniteOrInfiniteApproval(uint256 rawAmount, bool infinite) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 approval = infinite ? type(uint256).max : amount;
        token.approve(SPENDER, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
