// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Numos} from "../src/Numos.sol";

/// @dev All token holders are in this closed actor set, allowing a complete balance sum.
contract NumosHandler is Test {
    Numos public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA401), address(0xDA7E)];

    constructor(Numos token_) {
        token = token_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 amount = bound(rawAmount, 0, fromBefore);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 before = token.balanceOf(owner);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
        assertEq(token.balanceOf(owner), before);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 ownerBefore = token.balanceOf(owner);
        uint256 toBefore = token.balanceOf(to);
        uint256 available = ownerBefore < allowanceBefore ? ownerBefore : allowanceBefore;
        uint256 amount = bound(rawAmount, 0, available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(token.balanceOf(owner), owner == to ? ownerBefore : ownerBefore - amount);
        assertEq(token.balanceOf(to), owner == to ? toBefore : toBefore + amount);
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
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
}

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
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = NumosHandler.transfer.selector;
        selectors[1] = NumosHandler.approve.selector;
        selectors[2] = NumosHandler.transferFrom.selector;
        selectors[3] = NumosHandler.rejectOverspend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
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
}
