# RISE deltas

Upstream tag `op-reth/v2.3.0` plus the minimum for a vanilla node to follow RISE mainnet.
Stock builds fork. Build **both** binaries from this branch — the tag carries op-reth v2.3.0
and op-node v1.19.0 at the same commit.

## EL — EVM limits

RISE raises three EVM limits. A node on the stock values rejects transactions RISE already
accepted and forks, so we match them exactly. Set in `rust/op-reth/crates/evm/src/lib.rs` on
every `EvmEnv` constructor — mirrors `RiseEvmConfig` in `risechain/rise`,
`execution/crates/core/src/evm.rs`.

| field | vanilla | RISE |
| --- | --- | --- |
| `limit_contract_code_size` | 24_576 (EIP-170) | 262_144 |
| `limit_contract_initcode_size` | 49_152 (EIP-3860) | 524_288 |
| `tx_gas_limit_cap` | `u64::MAX`, → 16_777_216 under Osaka | `u64::MAX` |

## CL — derivation

| file | change |
| --- | --- |
| `op-node/rollup/derive/l1_block_info.go` | `DAFootprintGasScalarDefault` 400 → 0 |
| `op-node/rollup/derive/frame.go` | `MaxFrameLen` 1_000_000 → 16_252_873 (EigenDA payload cap) |

## Picking the base tag

Two traps, both hit once already:

**Track RISE's *deployed* version, not their default branch.** `risechain/rise` `main` may pin a
newer op-reth than mainnet actually runs. Confirm what is deployed before re-basing.

**The datadir is locked to a storage layout.** reth changed the trie encoding (65-byte → 33-byte
subkeys) without bumping `DB_VERSION`, so an older binary opens a newer database and then panics
in `StoredNibblesSubKey::from_compact` on first state-root computation. Downgrading op-reth
requires a full resync. Check with `op-reth db settings get --datadir <path>`.
