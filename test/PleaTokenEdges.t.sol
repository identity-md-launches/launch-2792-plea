// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "src/PleaToken.sol";

/// @notice Complements the deployment and basic ERC-20 tests with boundary and rollback properties.
/// forge-config: default.fuzz.runs = 1000
contract PleaTokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PleaToken private token;
    address private deployer = makeAddr("edge deployer");
    address private alice = makeAddr("edge alice");
    address private bob = makeAddr("edge bob");
    address private spender = makeAddr("edge spender");

    function setUp() public {
        vm.prank(deployer);
        token = new PleaToken();
    }

    function test_transferBoundaryAmountsAndReturnThem() public {
        uint256[4] memory amounts = [uint256(0), 1, SUPPLY - 1, SUPPLY];
        for (uint256 i; i < amounts.length; ++i) {
            uint256 amount = amounts[i];
            vm.expectEmit(address(token));
            emit IERC20.Transfer(deployer, alice, amount);
            vm.prank(deployer);
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);

            vm.prank(alice);
            assertTrue(token.transfer(deployer, amount));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(deployer), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_transferMoreThanSupplyOrUintMaxRevertsEvenToSelf() public {
        uint256[2] memory amounts = [SUPPLY + 1, type(uint256).max];
        bytes32 beforeState = _state();
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amounts[i])
            );
            vm.prank(deployer);
            token.transfer(deployer, amounts[i]);
            assertEq(_state(), beforeState, "failed self-transfer changed state");
        }
    }

    function test_zeroTransferFromEmptyAccountEmitsAndPreservesState() public {
        bytes32 beforeState = _state();
        vm.expectEmit(address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(_state(), beforeState);
    }

    function test_zeroTransferFromNeedsNoAllowanceAndEmits() public {
        bytes32 beforeState = _state();
        vm.expectEmit(address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(_state(), beforeState);
    }

    function test_zeroAmountDoesNotMakeZeroRecipientValid() public {
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(_state(), beforeState);
    }

    function test_transferFromZeroOwnerCannotMintEvenForZeroAmount() public {
        // Do not prescribe error precedence between invalid owner and insufficient allowance.
        bytes32 beforeState = _state();
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(_state(), beforeState);
    }

    function test_zeroSpenderCannotBeApprovedEvenForZeroAmount() public {
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(_state(), beforeState);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_largestFiniteAllowanceIsDecremented() public {
        _approve(deployer, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        _approve(deployer, spender, SUPPLY);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(deployer, deployer, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.allowance(deployer, spender), 0);

        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, deployer, 1);
        assertEq(_state(), beforeState);
    }

    function test_ownerCallingTransferFromStillNeedsSelfApproval() public {
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        assertEq(_state(), beforeState);

        _approve(deployer, deployer, 1);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_approvalIsSpecificToBothOwnerAndSpender() public {
        _approve(deployer, spender, SUPPLY);
        _approve(alice, bob, SUPPLY);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(_state(), beforeState);
    }

    function test_infiniteAllowanceSurvivesRepeatedFullSupplyTransfersThenCanBeRevoked() public {
        _approve(deployer, spender, type(uint256).max);
        for (uint256 i; i < 3; ++i) {
            vm.prank(spender);
            assertTrue(token.transferFrom(deployer, alice, SUPPLY));
            assertEq(token.balanceOf(deployer), 0);
            assertEq(token.balanceOf(alice), SUPPLY);
            assertEq(token.allowance(deployer, spender), type(uint256).max);
            vm.prank(alice);
            assertTrue(token.transfer(deployer, SUPPLY));
        }

        _approve(deployer, spender, 0);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(_state(), beforeState);
    }

    function test_infiniteApprovalDoesNotPermitUintMaxOverspend() public {
        _approve(deployer, spender, type(uint256).max);
        bytes32 beforeState = _state();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(_state(), beforeState);
    }

    function test_tokensSentToTokenContractAreIncludedInSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacesIsIdempotentAndCanBeRevoked(uint256 initial, uint256 replacement) public {
        _approve(deployer, spender, initial);
        _approve(deployer, bob, 17);
        vm.expectEmit(address(token));
        emit IERC20.Approval(deployer, spender, replacement);
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement);
        bytes32 afterReplacement = _state();
        _approve(deployer, spender, replacement);
        assertEq(_state(), afterReplacement, "repeating approve must be idempotent");

        _approve(deployer, spender, 0);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.allowance(deployer, bob), 17, "another spender's approval changed");
        assertEq(token.allowance(spender, deployer), 0, "approval is not symmetric");
        assertEq(token.balanceOf(deployer), SUPPLY, "approval moved tokens");
        assertEq(token.totalSupply(), SUPPLY);
        bytes32 beforeFailure = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(_state(), beforeFailure);
    }

    function testFuzz_finiteAllowanceCannotBeReusedAfterSplitSpending(uint256 allowance_, uint256 first) public {
        allowance_ = bound(allowance_, 1, SUPPLY);
        first = bound(first, 0, allowance_);
        _approve(deployer, spender, allowance_);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, first));
        assertEq(token.allowance(deployer, spender), allowance_ - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, allowance_ - first));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), allowance_);
        assertEq(token.balanceOf(deployer), SUPPLY - allowance_);

        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(_state(), beforeState);
    }

    function testFuzz_failedBalanceCheckPreservesApprovalAndCanBeRetried(uint256 held, uint256 amount, bool infinite)
        public
    {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        uint256 allowance_ = infinite ? type(uint256).max : amount;
        _approve(alice, spender, allowance_);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(_state(), beforeState, "balance failure consumed approval or moved tokens");

        // Funding the deficit, without approving again, must make the same request succeed.
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount - held));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedAllowanceCheckPreservesState(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, SUPPLY - 1);
        amount = bound(amount, allowance_ + 1, SUPPLY);
        _approve(deployer, spender, allowance_);
        bytes32 beforeState = _state();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
        assertEq(_state(), beforeState);
    }

    function testFuzz_zeroRecipientFailurePreservesAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(deployer, spender, infinite ? type(uint256).max : amount);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(_state(), beforeState, "invalid recipient consumed allowance");
    }

    function testFuzz_roundTripAndSelfTransferLeaveBalancesAndApprovalsUnchanged(uint256 amount, uint256 allowance_)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        _approve(deployer, spender, allowance_);
        bytes32 beforeState = _state();
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, amount));
        assertEq(_state(), beforeState);

        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, amount));
        assertEq(_state(), beforeState, "round trip lost value or changed approval");
    }

    function _approve(address owner, address delegate, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(delegate, amount));
    }

    /// @dev Snapshot every balance and allowance in this fixture, including passive recipients.
    function _state() private view returns (bytes32 state) {
        address[6] memory accounts = [deployer, alice, bob, spender, address(token), address(0)];
        state = keccak256(abi.encode(token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            state = keccak256(abi.encode(state, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                state = keccak256(abi.encode(state, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}
