// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PleaToken} from "src/PleaToken.sol";

/// @notice Closed actor set: the contract deployer and three ordinary holders.
/// @dev Ghosts come from the specified initial supply and requested operations, never balanceOf
/// or allowance. A faulty getter therefore cannot silently change the handler's input bounds.
contract PleaTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTOR_COUNT = 4;
    PleaToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    constructor() {
        actors = [address(this), makeAddr("invariant alice"), makeAddr("invariant bob"), makeAddr("invariant carol")];
        token = new PleaToken();
        ghostBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            _transfer(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), bound(amountSeed, 0, ghostBalance[from]));
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), ghostBalance[from]);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) external {
        // Exercise the full uint256 domain, revocation, and both sides of the infinite sentinel.
        mode %= 4;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = ghostBalance[owner];
        uint256 allowance_ = ghostAllowance[owner][spender];
        if (available > allowance_) available = allowance_;
        // Uses existing approval: spending in one call constrains later calls in the sequence.
        _spend(owner, spender, _actor(toSeed), bound(amountSeed, 0, available));
    }

    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool infinite)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = ghostBalance[owner];
        uint256 amount = balance == 0 ? 0 : bound(amountSeed, 1, balance);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _spend(owner, spender, _actor(toSeed), amount);
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
        // No ghost update on expected failure. The invariants check rollback of every account.
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function transferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 allowanceSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance_ = bound(allowanceSeed, 0, SUPPLY);
        _approve(owner, spender, allowance_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, allowance_ + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, allowance_ + 1);
    }

    function transferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = ghostBalance[owner];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = bound(amountSeed, 0, ghostBalance[owner]);
        if (delegated) {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 beforeFrom = ghostBalance[from];
        uint256 beforeTo = ghostBalance[to];
        uint256 amount = bound(amountSeed, 0, beforeFrom);
        _transfer(from, to, amount);
        _transfer(to, from, amount);
        assertEq(token.balanceOf(from), beforeFrom, "round trip changed sender balance");
        assertEq(token.balanceOf(to), beforeTo, "round trip changed recipient balance");
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        ghostAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount, "approval was not replaced exactly");
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer failed");
        _recordMovement(from, to, amount);
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer failed");
        if (ghostAllowance[owner][spender] != type(uint256).max) {
            ghostAllowance[owner][spender] -= amount;
        }
        _recordMovement(owner, to, amount);
        assertEq(token.allowance(owner, spender), ghostAllowance[owner][spender], "incorrect allowance consumption");
    }

    function _recordMovement(address from, address to, uint256 amount) private {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        // Also check intermediate states of compound actions, not just the final round-trip state.
        assertEq(token.balanceOf(from), ghostBalance[from], "incorrect sender balance");
        assertEq(token.balanceOf(to), ghostBalance[to], "incorrect recipient balance");
    }
}
