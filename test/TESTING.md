# Numos test coverage

The tests extend the accepted suite without changing production contracts or dependencies.
Supply expectations use the requested 1,000,000,000 NUMOS at 18 decimals, independently of
the contract's `INITIAL_SUPPLY` constant. No RPC, fork, FFI, environment mutation, or
additional dependency is required.

## Coverage and assumptions

- `Numos.t.sol` retains metadata, constructor mint/event, launch allocation movements,
  exact transfers/events, allowance behavior, common unauthorized admin selectors,
  prohibited runtime opcodes, and basic failure/fuzz coverage.
- `Numos.adversarial.t.sol` adds a real intermediate deployer contract; one-wei and
  maximum-integer boundaries; allowance isolation by owner, spender, and immediate caller;
  finite/infinite/revoked approvals; self-transfer failures; contract recipients; and
  failure atomicity with randomized balances and allowances. Five fuzz properties run
  1,000 cases each. Splitting a delegated payment must produce the same balances as one
  direct payment.
- `Numos.invariant.t.sol` drives eleven handler actions across four actors for 256 sequences
  of 64 calls, checking both invariants after each handler call. Inputs include ordinary transfers, self-transfers, zero/full
  amounts, unrestricted and balance-sized approvals, revocations, maximum finite/infinite
  approvals, and deliberate failures. Expected failures are checked inside the handler;
  unexpected handler reverts fail the campaign.

The stateful model starts each actor with exactly one quarter of the specified supply.
It records authorized balance movements and approvals independently of token reads.
After every handler call, invariants check fixed supply, complete balance conservation,
every actor's expected balance, and all sixteen owner/spender allowances. Failed operations
leave the model unchanged, so rollback and changes to unrelated accounts are checked too.
Each sequence ends by moving every actor's entire balance out and back, checking continued
transferability and zero transfer fees. A deterministic sequence also exercises finite
allowance exhaustion, infinite approval, revocation, failure rollback, and self-transfers.

The closed actor set makes conservation exhaustive for the handler's supported calls;
separate fuzz tests exercise arbitrary nonzero recipients. Transfers to the token itself
remain part of total supply; no recovery facility is promised. Maximum `uint256` approval
is infinite under the vendored ERC-20 semantics, while maximum minus one is finite.

The launch interpretation remains 90% to liquidity, 10% to the network distributor, and
zero initial creator allocation. The constructor credits its immediate deployer. The
factory owns subsequent allocation. Local launch tests use stand-in addresses and do not
claim to execute Uniswap swaps, pool seeding math, or Merkle claims. The supplied protected
harness tests those integrations with network-owned contracts and deployment parameters,
which are not present in this repository. Admin-selector probes and randomized sequences
are bounded checks, not an exhaustive proof that every possible byte sequence is safe.

## Local verification

Run `forge build` and `forge test`. To keep generated build/cache files inside the allowed
scratch directory, the equivalent commands used for this assignment are:

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build --offline
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge test --offline
```

The supplied Pashov fizz and Trail of Bits property-based-testing references informed
property selection: conservation, independent accounting, boundary generation, round trips,
and non-vacuous failure checks. Their templates and orchestration were not copied.
