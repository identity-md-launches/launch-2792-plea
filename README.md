# plea (PLEA)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Field            | Value                                           |
| ---------------- | ----------------------------------------------- |
| Solidity contract | `PleaToken` (`src/PleaToken.sol`)              |
| Name             | `plea`                                          |
| Symbol           | `PLEA`                                          |
| Decimals         | 18                                              |
| Total supply     | 1,000,000,000 PLEA = `1000000000000000000000000000` minor units |
| Constructor args | none                                            |
| Owner / admin    | none                                            |
| Compiler         | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"` |

## Behaviour

- The constructor mints the whole supply once to `msg.sender` (the deployer) and emits a single
  `Transfer(0x0, deployer, supply)` event. Nothing else is ever minted: there is no `mint`, no
  minter role, no owner, no upgrade path.
- Transfers, approvals and `transferFrom` are the unmodified OpenZeppelin Contracts v5.1.0 `ERC20`
  implementation. There is no fee, tax, burn-on-transfer, blocklist, pause or freeze, so every
  transfer moves exactly the amount requested and no privileged party can move or lock a holder's
  balance.
- The contract has no `receive` or `fallback`, so it refuses ETH.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, and no public or external
  library functions (nothing to link).

## Layout

```
foundry.toml                 compiler pins and build settings (root project; forge runs here)
remappings.txt               forge-std/ and @openzeppelin/contracts/ remappings
src/PleaToken.sol            the token
script/DeployPleaToken.s.sol reference deploy script; deploy() is tested directly, run() wraps it
test/PleaToken.t.sol         unit and fuzz tests for the token
test/DeployPleaToken.t.sol   tests for the deploy function
lib/forge-std                forge-std v1.9.7, vendored as plain files
lib/openzeppelin-contracts   OpenZeppelin Contracts v5.1.0, only the ERC20 files the token imports
```

Dependencies are committed as ordinary files, not git submodules, so the project builds with no
network.

## Build and test

```
forge build
forge test
forge fmt --check
```

Fuzz tests are deterministic under any seed; the verifier's seed is honoured through
`FOUNDRY_FUZZ_SEED`. Tests read no environment variables and do not depend on which address calls
the deploy script, so they pass in any order and in parallel.

## Deployment parameters

The launch is performed by the IdentityMD factory (`ProjectFactory.launchCustom`) from the attested
bytecode; this repository does not deploy anything. Values the manifest step needs:

| Manifest field       | Value                                                     |
| -------------------- | --------------------------------------------------------- |
| `token.contract`     | `PleaToken`                                               |
| `token.name`         | `plea`                                                    |
| `token.symbol`       | `PLEA`                                                    |
| `token.decimals`     | `18`                                                      |
| `token.constructorArgs` | `[]`                                                   |
| `token.totalSupply`  | `1000000000000000000000000000`                            |
| `contracts`          | `[]` (no application contracts)                           |

Launch policy values supplied by IdentityMD (not chosen here): chain 1; paired currency IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`; pool fee 12500 (1.25%); tick spacing 60; initial
price `79228162514264337593543950336`; economics `poolBps = 6000`,
`initialMarketCapWei = 2500000000000000000000`, `remainderTo = 0xee2aaa315cf7ed169f93148d30d24af9318dbb66`.

Because the constructor takes no arguments and mints to `msg.sender`, the factory (the deployer in
the launch transaction) receives the entire supply and then distributes it: 10% to the launch's
MerkleDistributor, 60% to the Uniswap v4 pool, 30% to `remainderTo`. The token exempts nothing and
taxes nothing, so each of those flows arrives whole.

## Assumptions

- "Deployer" means the address that sends the creation transaction. In the launch that is the
  factory contract; in the reference script it is the broadcaster; in tests it is whichever address
  is pranked or the script contract itself.
- The brief asks for a plain token with a fixed supply. No additional features (burn, tax, vesting,
  governance, owner) were requested, so none were added; adding an admin role would only create
  powers the brief does not call for.
- Decimals are 18, as the brief states, matching OpenZeppelin's default. `decimals()` is overridden
  only to make the constant explicit in source.
- The `remainderTo` address and launch economics are the requester's and are copied by the manifest
  step; they are documented here for reference only.

## After launch

There are no owner-settable values: the token has no owner and nothing to configure after
deployment.

## Operational responsibilities

- **Token holders** control their own balances. There is no admin who can recover tokens sent to a
  wrong address, pause transfers or reverse a transaction.
- **Requester** receives 30% of the supply at `remainderTo` and is responsible for the custody of
  that wallet.
- **IdentityMD factory / deployer** performs the launch, forwards the swarm's 10% to the
  MerkleDistributor, seeds the pool with 60%, and forwards the remainder. The token has no role in
  these steps beyond plain transfers.
- **Explorer verification** of the source after launch belongs to the network's deployer; the
  compiler settings above (solc 0.8.26, optimizer 200 runs, `bytecode_hash = "none"`,
  `cbor_metadata = false`, EVM version cancun) are what the verifier must use.
- **Security review**: tests passing is not an audit. The token is unmodified OpenZeppelin `ERC20`
  with a constructor-only mint, which keeps the attack surface to the library's own. An independent
  adversarial review before release remains the launch policy's call.

## Security checklist notes

Checked against the eth-security reference supplied with the task:

- No reentrancy surface: no external calls in any state-changing path.
- No access control: no privileged functions exist, so none can be misused.
- No `selfdestruct`, `delegatecall`, inline assembly, upgrade path, initializer or storage pointer.
- No `abi.encodePacked` with dynamic values.
- `transferFrom` moves tokens only from the `from` address with the caller's allowance (OpenZeppelin
  semantics); nothing moves funds from an arbitrary address.
- Supply cannot grow after construction, by anyone.

Tools run: `forge build`, `forge test` (including fuzz runs with the verifier's seed), `forge fmt
--check`. Slither was not available on this machine.
