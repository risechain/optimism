# Upgrade OptimismPortal2 `PROOF_MATURITY_DELAY_SECONDS`

Change the proof maturity delay of the RISE mainnet portal from `604800` (7d) to
`388800` (4.5d) using [`UpgradePortalProofMaturity.s.sol`](./UpgradePortalProofMaturity.s.sol).

The delay is an `immutable` of the implementation. To change it, deploy a new
implementation from the same source with a different constructor arg, then have the
ProxyAdmin owner Safe call `ProxyAdmin.upgrade(portal, newImpl)`. Do **not** use
`upgradeAndCall`: the proxy is already initialized at `initVersion() = 3`, so
`initialize` would revert. The upgrade does not touch proxy storage.

The full Safe proposal record (pre-state, hash-verified trace, fork post-state) is a
follow-up in `risechain/safe-runbook`, written per its `PROPOSAL_GUIDELINE.md`.

## Addresses (Ethereum mainnet)

| Role | Address |
| --- | --- |
| OptimismPortal proxy | `0xad92Fa18EB74E46Db844240623124BF46589db4C` |
| Current implementation (v5.1.1, delay 604800) | `0x7Cf803296662e8C72A6C1d6450572209aCF7f202` |
| ProxyAdmin | `0xCf32d8c4Be30cA330c1150916A71A651bADd70d5` |
| ProxyAdmin owner (Safe 3/5) | `0x9196464e3F828A50233C20732fa6898F4317002c` |

## Setup

Build from tag `rise-contracts/v5.0.0-rise.2`, which is the source running on mainnet.
The current implementation's runtime bytecode matches this tag; the only difference is
in the immutable values.

```bash
cd packages/contracts-bedrock
git submodule update --init lib/   # contract libraries must be populated
export L1_RPC=<ethereum mainnet RPC>
export PORTAL=0xad92Fa18EB74E46Db844240623124BF46589db4C
export NEW_DELAY=388800
```

## 1. Dry run on a fork

```bash
forge script scripts/deploy/UpgradePortalProofMaturity.s.sol \
  --sig 'run(address,uint256)' $PORTAL $NEW_DELAY --fork-url $L1_RPC
```

This deploys the implementation on the fork, simulates the upgrade as the ProxyAdmin
owner, and asserts that only the implementation and the delay change. Any `UPPM-*`
revert means stop.

## 2. Deploy the implementation

Any funded EOA can deploy; the deployer gets no privileges.

```bash
forge script scripts/deploy/UpgradePortalProofMaturity.s.sol \
  --sig 'deploy(uint256)' $NEW_DELAY \
  --rpc-url $L1_RPC --broadcast --account <foundry-account> \
  --verify --etherscan-api-key $ETHERSCAN_API_KEY

export NEW_IMPL=<address printed as "New OptimismPortal2 implementation">
```

## 3. Get the Safe calldata

```bash
forge script scripts/deploy/UpgradePortalProofMaturity.s.sol \
  --sig 'check(address,address,uint256)' $PORTAL $NEW_IMPL $NEW_DELAY --fork-url $L1_RPC
```

`check` verifies that the new implementation has the same `version()` and `initVersion()`
as the live one and carries the expected delay. It then simulates the upgrade and prints:

```text
Safe transaction (from ProxyAdmin owner):
  to:    0xCf32d8c4Be30cA330c1150916A71A651bADd70d5
  value: 0
  data:  0x99a88ec4<portal><NEW_IMPL>      # upgrade(address,address)
Rollback data (upgrade back to old implementation):
  0x99a88ec4<portal><OLD_IMPL>
```

Use `operation = 0` (CALL) from Safe `0x9196464e3F828A50233C20732fa6898F4317002c`.
Cross-check the calldata independently:

```bash
cast calldata 'upgrade(address,address)' $PORTAL $NEW_IMPL
```

## Notes

- **Retroactive effect.** The delay is compared against `provenWithdrawal.timestamp` at
  finalization time. Once upgraded, every withdrawal that was proven more than 4.5d ago,
  and whose dispute game has finalized, can be finalized immediately. Before signing,
  check every recent `WithdrawalProven` against L2.
- **Future OPCM upgrades.** Deploy configs and OPCM implementation bootstraps must use
  `proofMaturityDelaySeconds = 388800`. Otherwise the next OPCM upgrade resets the
  delay to 7d.
- **Rollback.** Propose the same call with `OLD_IMPL`. This is safe because the storage
  layout is unchanged.
