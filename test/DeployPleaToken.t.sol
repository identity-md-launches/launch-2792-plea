// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployPleaToken} from "../script/DeployPleaToken.s.sol";
import {PleaToken} from "../src/PleaToken.sol";

contract DeployPleaTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    function test_deployMintsWholeSupplyToTheScriptCaller() public {
        DeployPleaToken script = new DeployPleaToken();
        PleaToken token = script.deploy();
        // `deploy()` is an ordinary call, so the script contract is msg.sender in the constructor.
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(script)), SUPPLY);
        assertEq(token.name(), "plea");
        assertEq(token.symbol(), "PLEA");
        assertEq(token.decimals(), 18);
    }

    function test_deployTwiceGivesIndependentTokens() public {
        DeployPleaToken script = new DeployPleaToken();
        PleaToken first = script.deploy();
        PleaToken second = script.deploy();
        assertTrue(address(first) != address(second));
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(first.balanceOf(address(second)), 0);
    }
}
