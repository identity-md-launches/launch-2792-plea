// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {PleaToken} from "../src/PleaToken.sol";

/// @title Deploy script for PleaToken
/// @notice Reference deployment for local or test networks. The production launch is performed by
///         the IdentityMD factory from the attested bytecode, not by this script; it is kept so the
///         deployment can be reviewed and rehearsed locally.
/// @dev    `deploy()` holds all deployment logic and takes no environment input, so tests call it
///         directly. `run()` only wraps it in a broadcast.
contract DeployPleaToken is Script {
    /// @notice Deploys the token. The caller of this function (the broadcaster in `run()`) becomes
    ///         the holder of the whole supply.
    function deploy() public returns (PleaToken token) {
        token = new PleaToken();
    }

    function run() external returns (PleaToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
