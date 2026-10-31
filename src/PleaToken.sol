// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title plea (PLEA)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 PLEA (18 decimals) is minted
///         once, in the constructor, to the deployer (`msg.sender`). There is no owner, no mint
///         function, no pause, no blocklist and no fee: after construction the contract has no
///         privileged role of any kind, and the supply can never grow.
/// @dev    Built on OpenZeppelin Contracts v5.1.0 `ERC20`, vendored under `lib/`. Transfers are
///         plain ERC-20 transfers, so launch flows (factory -> distributor, factory -> pool,
///         pool <-> traders) move exactly the amounts they state.
contract PleaToken is ERC20 {
    /// @notice ERC-20 name.
    string public constant TOKEN_NAME = "plea";

    /// @notice ERC-20 symbol.
    string public constant TOKEN_SYMBOL = "PLEA";

    /// @notice ERC-20 decimals. Matches OpenZeppelin's default, exposed here so the manifest value
    ///         is visible in source.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice Total supply in minor units: 1,000,000,000 * 10^18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints the entire fixed supply to the deployer.
    /// @dev    Takes no arguments and makes no external calls, so it deploys on an empty chain and
    ///         the launch manifest needs no constructor arguments for it.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}
