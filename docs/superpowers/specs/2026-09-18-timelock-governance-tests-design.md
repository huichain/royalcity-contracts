# Timelock Governance Local Tests

## Goal

Expand `test/RoyalCityTimelock.t.sol` so local Forge tests cover the near-term governance rehearsal without Sepolia.

## Scope

- In scope: role handoff, Timelock-gated manager ops (create / start / finalize / property pause), Timelock-gated default-admin accept + global pause, negative paths.
- Out of scope: Sepolia deploy, new scripts, main contract changes, Safe multisig.

## Test plan

1. Keep existing create-via-Timelock and bypass-revert cases.
2. Full rehearsal: grant manager to Timelock and revoke deployer; compliance/treasury on dedicated addresses; `beginDefaultAdminTransfer(timelock)` → wait admin delay → Timelock schedule/execute `acceptDefaultAdminTransfer`.
3. After manager-only Timelock: create → startFunding → whitelist/invest → finalizeFunding via Timelock; `setPropertyPaused` via Timelock.
4. After admin accept: `pause` / `unpause` only via Timelock.
5. Negatives: execute before delay reverts; non-proposer cannot schedule; deployer without manager cannot create.

## Done when

`forge test --match-contract RoyalCityTimelockTest` passes.
