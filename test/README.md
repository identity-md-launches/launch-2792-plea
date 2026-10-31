# PLEA test coverage

The existing `PleaToken.t.sol` and `DeployPleaToken.t.sol` cover metadata, the
constructor mint, deployment through a contract, basic transfers, and the absence
of privileged entry points. The additional suites exercise these properties:

| Review perspective | Property | Coverage |
| --- | --- | --- |
| Conservation | Supply stays exactly `1_000_000_000 * 10**18`; all tracked balances sum to it; each holder receives exactly the authorized amount. | Stateful balance and supply invariants; transfer boundaries. |
| State transitions | Approval replaces the old value, is idempotent, and can be revoked; only successful spending consumes finite approval; infinite approval remains unchanged. | Allowance invariant; replacement, split spending, revocation, and sentinel tests. |
| Round trips | Sending and returning the same amount restores balances and leaves approvals unchanged, including zero, one minor unit, and the full supply. | Round-trip handler and fuzz/unit tests; intermediate balances are also checked. |
| Adversarial calls | Excess spending, insufficient balance, and invalid recipients revert without changing balances or allowances; another spender cannot use an approval. | Negative handler actions; state snapshots; a failed delegated transfer retried after funding. |
| Token properties | Self-transfers preserve balances; delegated self-transfers consume finite approval; zero-value transfers emit events; metadata stays fixed. | Explicit edge tests and metadata invariant. |

`PleaTokenHandler` deploys the actual token and distributes the constructor supply
among four actors, including the contract deployer. It uses only public token
operations: no storage edits, artificial token minting, or mocked token calls.
Expected balances and allowances are derived from the specified supply and
requested operations, independently of the token's getters. All recipients in the
random campaign belong to that tracked set; a separate unit test covers tokens
sent to the token contract itself.

The runner targets exactly eleven handler actions. Successful actions are bounded
to reachable inputs; negative actions deliberately exceed balances/allowances or
use the zero recipient and check the expected revert. Ghost state remains unchanged
after rejected operations. Unexpected reverts fail the campaign. After each random
sequence, every holder must still be able to send its entire balance back to the
deployer, recovering exactly the original supply.

Run counts are inline: 1,000 cases for each new fuzz property and 256 invariant
sequences of depth 128. A deterministic handler test pins nonzero delegated
spending, infinite approval, rejection, and revocation in one sequence. These tests
use the repository's existing vendored dependencies and need no network or fork.
They exercise token behavior locally; the supplied factory/Uniswap integration
checks belong to the separate protected launch harness.

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x8f96bf53ea9a02230faeb307006dc2a70229dbd7b45420b5632e8f7fde4d5e2c forge test --offline
```
