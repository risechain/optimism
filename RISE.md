# RISE deltas

Upstream tag `op-reth/v1.11.5` plus the minimum for a vanilla node to follow RISE mainnet.
Stock builds fork. Build **both** binaries from this branch — it ships op-reth 1.11.3
(revm 34, matching RISE's own EVM stack) and op-node v1.16.11.

Pinned to that tag on purpose. Don't rebase onto `develop`.

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

| file | change | why |
| --- | --- | --- |
| `op-node/rollup/derive/l1_block_info.go` | `DAFootprintGasScalarDefault` 400 → 0 | RISE commits 0 in every L1-attributes tx; upstream rewrites 0 → 400, which no config can reproduce |
| `op-node/rollup/derive/frame.go` | `MaxFrameLen` 1_000_000 → 16_252_873 | EigenDA payload cap |
