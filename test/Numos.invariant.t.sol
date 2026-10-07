// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Numos} from "../src/Numos.sol";

/// @dev All token holders are in this closed actor set, allowing a complete balance sum.
contract NumosHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    Numos public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xDA7E)];
    // Seeded from the intended allocation, never copied from the token's storage.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Numos token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 before = token.balanceOf(owner);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.balanceOf(owner), before);
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 available = expectedBalance[owner] < expectedAllowance[owner][spender]
            ? expectedBalance[owner]
            : expectedAllowance[owner][spender];
        uint256 amount = bound(rawAmount, 0, available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.balanceOf(owner), owner == to ? ownerBefore : ownerBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowanceBefore = token.allowance(owner, spender);

        vm.prank(spender);
        (bool succeeded,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, ownerBefore + 1)));
        assertFalse(succeeded);
        assertEq(token.balanceOf(owner), ownerBefore);
        assertEq(token.balanceOf(to), toBefore);
        assertEq(token.allowance(owner, spender), allowanceBefore);
    }

    /// @dev Finite approvals near spendable balances exercise exhaustion, not just huge approvals.
    function approveBounded(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        uint256 amount = bound(rawAmount, 0, expectedBalance[actors[ownerSeed % actors.length]]);
        approve(ownerSeed, spenderSeed, amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        uint256[4] memory amounts = [uint256(0), uint256(1), type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[mode % amounts.length]);
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approve(ownerSeed, spenderSeed, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectDirectOverspend(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    /// @dev Isolate insufficient balance after allowance processing, including infinite allowance.
    function rejectApprovedOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        approve(ownerSeed, spenderSeed, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        // The ghost allowance remains the approval: the reverted spend must roll back.
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[owner]);
        approve(ownerSeed, spenderSeed, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
    }

    /// @dev Every holder must remain able to move its whole balance and receive it back without fees.
    function roundTripFullBalance(uint256 fromSeed) public {
        uint256 index = fromSeed % actors.length;
        address from = actors[index];
        address to = actors[(index + 1) % actors.length];
        uint256 amount = expectedBalance[from];
        uint256 recipientBefore = expectedBalance[to];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), recipientBefore + amount);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        assertEq(token.balanceOf(from), amount);
        assertEq(token.balanceOf(to), recipientBefore);
        // The model is unchanged by this exact round trip.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract NumosInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    Numos internal token;
    NumosHandler internal handler;

    function setUp() public {
        token = new Numos();
        handler = new NumosHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), SUPPLY / 4);
        }
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = NumosHandler.transfer.selector;
        selectors[1] = NumosHandler.approve.selector;
        selectors[2] = NumosHandler.transferFrom.selector;
        selectors[3] = NumosHandler.rejectOverspend.selector;
        selectors[4] = NumosHandler.approveBounded.selector;
        selectors[5] = NumosHandler.approveBoundary.selector;
        selectors[6] = NumosHandler.revokeAndReject.selector;
        selectors[7] = NumosHandler.rejectDirectOverspend.selector;
        selectors[8] = NumosHandler.rejectApprovedOverspend.selector;
        selectors[9] = NumosHandler.rejectZeroReceiver.selector;
        selectors[10] = NumosHandler.roundTripFullBalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        invariant_BalancesAndAllowancesMatchModel();
    }

    function invariant_TotalSupplyAndBalancesAreConserved() public view {
        uint256 balances;
        for (uint256 i; i < 4; ++i) {
            balances += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(balances, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_BalancesAndAllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(
                token.balanceOf(owner), handler.expectedBalance(owner), "balance differs from authorized movements"
            );
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender), "allowance drift");
            }
        }
    }

    /// @dev Check liveness for every actor at the end of each generated sequence, then reconcile again.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.roundTripFullBalance(i);
        }
        invariant_TotalSupplyAndBalancesAreConserved();
        invariant_BalancesAndAllowancesMatchModel();
    }

    function test_HandlerFiniteInfiniteRevocationAndFailureSequence() public {
        handler.approveBounded(0, 1, 7);
        handler.transferFrom(0, 1, 2, 7);
        invariant_BalancesAndAllowancesMatchModel();
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(2)), SUPPLY / 4 + 7);
        handler.approveBoundary(0, 1, 3);
        handler.transferFrom(0, 1, 0, 1);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max);
        handler.revokeAndReject(0, 1, 2);
        handler.rejectApprovedOverspend(0, 1, 2, false);
        invariant_BalancesAndAllowancesMatchModel();
        handler.rejectApprovedOverspend(0, 1, 0, true);
        handler.rejectZeroReceiver(0, 1, 1);
        handler.rejectDirectOverspend(0, 0, type(uint256).max);
        handler.rejectOverspend(0, 1, 2);
        handler.transfer(2, 3, 1);
        afterInvariant();
    }
}
