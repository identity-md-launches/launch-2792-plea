// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @notice Stands in for the launch factory: deploys the token so the supply lands on a contract
///         address, then forwards it the way the factory does.
contract FactoryStub {
    PleaToken public token;

    function deployToken() external returns (PleaToken) {
        token = new PleaToken();
        return token;
    }

    function forward(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract PleaTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    PleaToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new PleaToken();
    }

    // ------------------------------------------------------------------
    // Metadata and supply
    // ------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "plea");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "plea");
        assertEq(token.TOKEN_SYMBOL(), "PLEA");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleTransferFromZero() public {
        address other = makeAddr("other");
        vm.recordLogs();
        vm.prank(other);
        PleaToken fresh = new PleaToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event expected");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(0));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), other);
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_supplyMintedToContractDeployer() public {
        // The real launch deploys from the factory contract, so msg.sender is a contract.
        FactoryStub factory = new FactoryStub();
        PleaToken launched = factory.deployToken();
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
    }

    function test_launchFlowsMoveExactAmounts() public {
        FactoryStub factory = new FactoryStub();
        PleaToken launched = factory.deployToken();
        address distributor = makeAddr("distributor");
        address remainder = makeAddr("remainder");

        uint256 swarm = (SUPPLY * 1000) / 10_000;
        uint256 pool = (SUPPLY * 6000) / 10_000;
        uint256 rest = SUPPLY - swarm - pool;

        assertTrue(factory.forward(distributor, swarm));
        assertTrue(factory.forward(alice, pool)); // alice stands in for the pool manager
        assertTrue(factory.forward(remainder, rest));

        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(alice), pool);
        assertEq(launched.balanceOf(remainder), rest);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    // ------------------------------------------------------------------
    // Transfers: success
    // ------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        uint256 amount = 12_345 ether;
        vm.expectEmit(address(token));
        emit IERC20.Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 1 ether));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_holderCanTransferFullBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 100 ether);
    }

    // ------------------------------------------------------------------
    // Transfers: failure
    // ------------------------------------------------------------------

    function test_transferRevertsWhenBalanceInsufficient() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        vm.prank(alice);
        token.transfer(bob, 11 ether);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    // ------------------------------------------------------------------
    // Allowances and transferFrom
    // ------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(address(token));
        emit IERC20.Approval(deployer, spender, 5 ether);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 5 ether));
        assertEq(token.allowance(deployer, spender), 5 ether);
    }

    function test_approveZeroAddressSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_transferFromWithinAllowanceSucceedsAndDecrements() public {
        vm.prank(deployer);
        token.approve(spender, 5 ether);

        vm.expectEmit(address(token));
        emit IERC20.Transfer(deployer, bob, 3 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 3 ether));

        assertEq(token.balanceOf(bob), 3 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 3 ether);
        assertEq(token.allowance(deployer, spender), 2 ether);
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecrement() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 7 ether);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(bob), 7 ether);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromRevertsAboveAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1 ether, 2 ether)
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, 2 ether);
    }

    function test_transferFromRevertsWhenOwnerBalanceInsufficient() public {
        vm.prank(alice);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1 ether);
    }

    function test_nobodyCanMoveAHoldersTokensWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 50 ether);
        // Not even the deployer, the address a token would most plausibly trust.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 50 ether);
    }

    // ------------------------------------------------------------------
    // No privileged surface
    // ------------------------------------------------------------------

    function test_noMintOrAdminSelectorsExist() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setBlacklist(address,bool)",
            "freeze(address)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 1);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(alice);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_receivingEtherReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallSelfdestructOrCallcode() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ------------------------------------------------------------------
    // Fuzz
    // ------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY - 1);
        attempt = bound(attempt, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempt));
        vm.prank(alice);
        token.transfer(bob, attempt);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);
        vm.prank(spender);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
            token.transferFrom(deployer, bob, amount);
        } else {
            assertTrue(token.transferFrom(deployer, bob, amount));
            assertEq(token.balanceOf(bob), amount);
            assertEq(token.allowance(deployer, spender), allowed - amount);
        }
    }

    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b);
    }
}
