// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PleaToken} from "src/PleaToken.sol";
import {PleaTokenHandler} from "./handlers/PleaTokenHandler.sol";

/// @notice Random sequences must preserve supply, per-holder accounting and authorization.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PleaTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PleaTokenHandler private handler;
    PleaToken private token;

    function setUp() public {
        handler = new PleaTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferFullBalance.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.approveAndSpend.selector;
        selectors[5] = handler.revokeAndAttemptSpend.selector;
        selectors[6] = handler.transferAboveBalance.selector;
        selectors[7] = handler.transferFromAboveAllowance.selector;
        selectors[8] = handler.transferFromAboveBalance.selector;
        selectors[9] = handler.transferToZero.selector;
        selectors[10] = handler.roundTrip.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsAlwaysExactlyOneBillionTokens() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allBalancesMatchAuthorizedMovementsAndSumToSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.ghostBalance(actor), "holder balance diverged from requested transfers");
            sum += balance;
        }
        assertEq(sum, SUPPLY, "tokens were created, destroyed or leaked outside the actor set");
        assertEq(token.balanceOf(address(token)), 0, "unexpected fee credited to the token");
        assertEq(token.balanceOf(address(this)), 0, "unexpected tokens credited to the test");
    }

    function invariant_allowancesMatchApprovalsAndSuccessfulSpendingOnly() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "approval, revocation, spending or rollback diverged"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
        }
    }

    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "plea");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
    }

    /// @dev After every random sequence, each holder must still be able to transfer its full balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < handler.ACTOR_COUNT(); ++i) {
            handler.transferFullBalance(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_supplyIsAlwaysExactlyOneBillionTokens();
        invariant_allBalancesMatchAuthorizedMovementsAndSumToSupply();
        invariant_allowancesMatchApprovalsAndSuccessfulSpendingOnly();
        invariant_metadataNeverChanges();
    }

    function test_handlerExecutesNonzeroSpendingRevocationAndRollback() public {
        // Pin an effective sequence as well as asking the invariant runner to discover sequences.
        handler.approveAndSpend(0, 1, 2, 1, false);
        assertEq(token.balanceOf(handler.actors(2)), SUPPLY / 4 + 1);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 0);
        handler.approve(2, 1, 0, 1); // infinite approval
        handler.transferFrom(2, 1, 3, 1);
        assertEq(token.allowance(handler.actors(2), handler.actors(1)), type(uint256).max);
        handler.transferFromAboveBalance(2, 1, 0, type(uint256).max, false);
        invariant_allowancesMatchApprovalsAndSuccessfulSpendingOnly();
        handler.revokeAndAttemptSpend(2, 1, 3);
        assertEq(token.allowance(handler.actors(2), handler.actors(1)), 0);
        handler.roundTrip(3, 2, 1);
        afterInvariant();
    }
}
