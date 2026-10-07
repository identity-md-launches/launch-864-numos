// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Numos} from "../src/Numos.sol";

contract NumosTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    address internal constant FACTORY = address(0xFAC7);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL_MANAGER = address(0x9001);
    address internal constant CREATOR = address(0xC0FFEE);

    Numos internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Numos();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Numos");
        assertEq(token.symbol(), "NUMOS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new Numos();
    }

    function test_ConstructorMintsToImmediateDeployer() public {
        vm.prank(FACTORY);
        Numos launched = new Numos();
        assertEq(launched.balanceOf(FACTORY), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(CREATOR), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    /// @dev Exercises token movement only; these addresses are not an AMM or a Merkle distributor.
    function test_LaunchAllocationClaimsAndPoolTransfersAreExact() public {
        vm.prank(FACTORY);
        Numos launched = new Numos();
        uint256 swarm = SUPPLY / 10;
        uint256 liquidity = SUPPLY * 9 / 10;

        vm.startPrank(FACTORY);
        assertTrue(launched.transfer(DISTRIBUTOR, swarm));
        assertTrue(launched.transfer(POOL_MANAGER, liquidity));
        vm.stopPrank();

        assertEq(launched.balanceOf(FACTORY), 0);
        assertEq(launched.balanceOf(CREATOR), 0);
        assertEq(launched.balanceOf(DISTRIBUTOR), swarm);
        assertEq(launched.balanceOf(POOL_MANAGER), liquidity);

        vm.prank(DISTRIBUTOR);
        assertTrue(launched.transfer(ALICE, swarm));
        assertEq(launched.balanceOf(ALICE), swarm);
        assertEq(launched.balanceOf(DISTRIBUTOR), 0);

        vm.prank(POOL_MANAGER);
        assertTrue(launched.transfer(BOB, 1_000 ether));
        assertEq(launched.balanceOf(BOB), 1_000 ether);
        assertEq(launched.balanceOf(POOL_MANAGER), liquidity - 1_000 ether);
        vm.prank(BOB);
        assertTrue(launched.transfer(POOL_MANAGER, 1_000 ether));
        assertEq(launched.balanceOf(BOB), 0);
        assertEq(launched.balanceOf(POOL_MANAGER), liquidity);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 7 ether);
        assertTrue(token.transfer(ALICE, 7 ether));
        assertEq(token.balanceOf(ALICE), 7 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanTransfer() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenSelfTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenTransferringToZeroEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalEmitsEventAndCanBeReplaced() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 50 ether));
        assertEq(token.allowance(address(this), SPENDER), 50 ether);
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalCanBeRevoked() public {
        token.approve(SPENDER, 50 ether);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_RevertWhenApprovingZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 8 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 3 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 5 ether);
        assertEq(token.balanceOf(ALICE), 3 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3 ether);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 5 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 8 ether);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_RevertWhenTransferFromExceedsAllowance() public {
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 2, 3));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 3);
        assertEq(token.allowance(address(this), SPENDER), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_FailedTransferFromRestoresAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 2));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 2);
        assertEq(token.allowance(ALICE, SPENDER), 2);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromToZeroRevertsWithoutConsumingAllowance() public {
        token.approve(SPENDER, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 2);
        assertEq(token.allowance(address(this), SPENDER), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_ZeroTransferFromZeroSenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_DelegatedSelfTransferConsumesAllowanceOnly() public {
        token.approve(SPENDER, 5 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 5 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_DeployerCannotSpendHolderFundsWithoutApproval() public {
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function test_NoMintBurnAdminOrUpgradeEntryPoints() public {
        token.transfer(ALICE, 100 ether);
        bytes[] memory calls = new bytes[](22);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[5] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[6] = abi.encodeWithSignature("owner()");
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[8] = abi.encodeWithSignature("setOwner(address)", BOB);
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[12] = abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true);
        calls[13] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[14] = abi.encodeWithSignature("lock(address)", ALICE);
        calls[15] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[16] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[17] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[18] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[19] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", BOB, bytes(""));
        calls[20] = abi.encodeWithSignature("setFee(uint256)", 100);
        calls[21] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 100 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
        assertEq(token.balanceOf(BOB), 100 ether);
    }

    function test_RuntimeHasNoDangerousOpcodesOrExternalCalls() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "delegatecall, callcode or selfdestruct");
            assertTrue(op != 0xf1 && op != 0xfa, "external call or staticcall");
        }
    }

    function test_NativeCurrencyAndUnknownCallsRevert() public {
        vm.deal(address(this), 1 ether);
        (bool nativeAccepted,) = address(token).call{value: 1 wei}("");
        (bool unknownAccepted,) = address(token).call(hex"deadbeef");
        assertFalse(nativeAccepted);
        assertFalse(unknownAccepted);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_TransfersConserveSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransfersRespectBalancesAndAllowance(uint256 rawAmount, uint256 rawApproval) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 approval = bound(rawApproval, amount, type(uint256).max);
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawAlwaysReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
