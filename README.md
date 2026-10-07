# Numos (NUMOS)

Numos is a fixed-supply ERC-20 community token for [@Numosimd](https://x.com/Numosimd).
The deployable contract is `src/Numos.sol:Numos`.

| Token parameter | Value |
| --- | --- |
| Name | `Numos` |
| Symbol | `NUMOS` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` |
| Constructor arguments | None (`[]`; encoded arguments `0x`) |
| Initial recipient | The immediate deployer, `msg.sender` |
| Transfer fee | Zero |

The constructor mints the entire supply once. The contract uses OpenZeppelin ERC-20
without transfer overrides. There is no external mint or burn, owner, blacklist,
pause, seizure, upgrade, initializer, or configurable fee. The deployer has only
the same balance and allowance rights as every other holder. Transfers perform no
external calls or recipient callbacks.

## Build and checks

Install Foundry and provide Solidity **0.8.26**, then run:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins the compiler version, Cancun EVM, optimization at 200 runs,
`bytecode_hash = "none"`, and disables the CBOR metadata trailer. FFI and filesystem
cheatcode permissions are disabled. No RPC, wallet, environment variables, or
network access are needed by the project or tests once the compiler is installed.
The verification environment supplies the pinned compiler; no compiler binary is
part of the repository.

All required Solidity dependencies are ordinary files under `lib/`:

- OpenZeppelin Contracts **v5.0.2**, the ERC-20 dependency closure, MIT licensed.
- forge-std **v1.9.7**, the test dependency closure, MIT/Apache-2.0 licensed.

Upstream sources are unmodified. `DEPENDENCIES.json` records each source URL and
SHA-256 digest; license files are included. No submodules or package install step
are required.

The tests check metadata, deployment events and recipient, exact transfers,
zero/self/full-balance transfers, allowance replacement/revocation/exhaustion,
infinite allowances, delegated transfers, failure rollback, invalid addresses,
unauthorized spending, and rejection of common mint/admin/upgrade selectors.
Fuzz tests cover valid and excessive amounts. A stateful invariant exercises
transfers, approvals, delegated transfers and failed overspends across four actors,
checking fixed supply, balance conservation and allowance accounting. A runtime
opcode check rejects delegatecall, callcode, selfdestruct and external calls.

The allocation test checks the exact token movement needed by the factory,
distributor and pool manager. Its recipient addresses are stand-ins: it does not
implement or test Uniswap pricing, liquidity positions, swaps, or Merkle proofs.
The supplied protected harness covers the real launch infrastructure when the
network runs it with its contracts and resolved deployment parameters.

## Launch allocation

The requested constructor behavior and launch allocation are separate steps. For
the IdentityMD launch, **ProjectFactory must deploy Numos** so it receives all
tokens, then complete allocation in the launch transaction. The constructor does
not send tokens to hardcoded pool, creator, or distributor addresses.

| Destination | Basis points of total supply | NUMOS | Minor units |
| --- | ---: | ---: | ---: |
| Liquidity pool | 9,000 | 900,000,000 | 900000000000000000000000000 |
| Network contributor distributor | 1,000 | 100,000,000 | 100000000000000000000000000 |
| Creator allocation | 0 | 0 | 0 |

The remaining 10% follows the supplied network definition: 2% of total supply for
accepted project contributors and 8% for paired seats. The factory and distributor
are responsible for those allocations and claims. No creator allocation means
zero tokens are assigned to the creator by this launch; it does not prevent that
address from later buying or receiving NUMOS.

The factory first transfers the contributor share to the network's
MerkleDistributor and then seeds the single-sided Uniswap v4 pool. Set
`economics.poolBps = 9000`. The calculated requester remainder is zero. Do not add
an application contract or custom distributor: the application list is `[]`.
The token needs no factory, pool, launch-number or exemption constructor arguments.
All launch and claim transfers deliver the full requested amount. The pool's
trading fee remains separate from NUMOS transfers.

## Deployment parameters and assumptions

No chain configuration or opening valuation was supplied. These are documented
defaults for the network's manifest preparation, not a deployed pool:

| Launch field | Default or responsibility |
| --- | --- |
| Kind | `custom_token` |
| Token contract | `src/Numos.sol:Numos` |
| Token constructor arguments | `[]` |
| Application contracts | `[]` |
| `economics.poolBps` | `9000` |
| `economics.initialMarketCapWei` | `1000000000000000000` (1 ETH initial fully diluted capitalization) |
| `pool.pairedCurrency` | `0x0000000000000000000000000000000000000000` (native ETH) |
| `pool.fee` | `3000` (0.30% swap fee) |
| `pool.tickSpacing` | `60` |
| `economics.remainderTo` | Network-resolved requester address; receives zero launch tokens |
| Chain ID, factory, PoolManager, distributor, launch number | Supplied and verified by the network deployer |
| Initial sqrt price, tick bounds, liquidity, hook and CREATE2 salt | Derived by the network's launch tooling |

The 1 ETH opening capitalization is an explicit assumption, not a price promise
or a requirement to deposit 1 ETH. It implies an initial nominal price of
`0.000000001 ETH` per whole NUMOS before fees and price movement. The pool starts
single-sided in NUMOS. The deployer must derive `sqrtPriceX96` from the final sorted
currencies and their minor units; using whole-token prices directly gives the
wrong result. An authoritative network job configuration supersedes the
unspecified pairing/valuation defaults above, while the 90% pool and zero creator
allocation remain required.

The repository supplies token creation bytecode through the Foundry artifact at
`out/Numos.sol/Numos.json`. The network owns `launch.json` generation and
`ProjectFactory.launchCustom` integration. There is no local broadcast script,
private-key handling, production address assumption, or deployment transaction.
For a local constructor-only experiment, `new Numos()` creates the token and
credits the calling address; this alone does not perform the network launch.

Before release the network deployer must resolve and validate chain addresses,
ensure Cancun-compatible execution, attest the exact compiled creation bytecode
and supply, and run the protected suite against the final manifest. This project
targets ordinary EVM execution; a zkSync-native deployment requiring a different
compiler is not covered by this build.

The deployer also owns pool initialization and seeding, rounding/dust accounting,
LP custody and withdrawal policy, fee handling, distributor root/claim setup,
explorer verification, and post-launch balance reconciliation. Reconcile the full
900,000,000 NUMOS pool allocation, 100,000,000 NUMOS distributor allocation, and
zero creator payout. If liquidity math leaves token dust, the infrastructure must
account for it within the pool allocation and must not forward it to the creator;
the token cannot enforce or repair infrastructure accounting. Do not claim LP
tokens are locked or burned without separately verified infrastructure evidence.

## Operational behavior and review

No recurring token administration is necessary or possible. NUMOS cannot enforce
how its initial holder distributes tokens; the factory and launch verification
must enforce the allocation. A direct EOA deployment would put all tokens in that
EOA and would not by itself meet the requested launch economics.

Standard ERC-20 semantics apply: zero-value transfers to valid addresses succeed,
transfers to the zero address revert, and maximum approval is treated as infinite.
`approve` replaces the current allowance; integrations should account for the
standard allowance-change race (revoke first when appropriate). OpenZeppelin v5
does not emit an `Approval` event when `transferFrom` consumes an allowance; read
`allowance` for its current value.

There is no rescue function. Tokens sent to the NUMOS contract itself, or to other
contracts unable to transfer them out, can be permanently inaccessible. Such
transfers do not reduce `totalSupply`. Ordinary native ETH sends revert. No bridge,
cross-chain minting, oracle, time logic, or custom transfer hook is included.

Local review covers the constructor-only mint, inherited ERC-20 checks, absence of
external calls and admin entry points, fixed supply and the allocation arithmetic.
Foundry unit, fuzz and invariant checks are the automated checks delivered here;
Slither and Mythril were not run. This is not an independent security audit. The
network's independent adversarial review and full launch-infrastructure checks
remain release responsibilities.
