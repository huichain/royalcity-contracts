# UUPS Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put `RoyalCityRealEstate` behind an ERC-1967 UUPS proxy so the default admin can replace the logic without changing the share-contract address.

**Architecture:** The implementation disables initializers in its constructor. `ERC1967Proxy` delegatecalls `initialize` once. `PAYMENT_TOKEN` moves from `immutable` to proxy storage. The NAV oracle stays a non-proxy contract. Tests and the deploy script construct the proxy and treat that address as the share contract.

**Tech Stack:** Solidity 0.8.30, Foundry, OpenZeppelin Contracts 5.6.1 and Contracts Upgradeable 5.6.1.

## Global Constraints

- Only `DEFAULT_ADMIN_ROLE` may upgrade.
- `RoyalCityNavOracle` is not upgradeable.
- `PAYMENT_TOKEN` is a normal storage variable set in `initialize`.
- Do not reorder RoyalCity storage after this first upgradeable layout.
- V2 used to prove upgrades lives under `test/` only.
- Deploy script returns the proxy and still does not deploy the NAV oracle.
- The existing Sepolia address is not migrated.

---

### Task 1: Upgradeable share contract and proxy tests

**Files:**
- Create: `lib/openzeppelin-contracts-upgradeable` (forge install v5.6.1)
- Modify: `remappings.txt`
- Modify: `src/RoyalCityRealEstate.sol`
- Create: `test/RoyalCityRealEstateV2.sol`
- Modify: `test/RoyalCityRealEstate.t.sol`
- Modify: `test/RoyalCityTimelock.t.sol`
- Modify: `test/RoyalCityInvariant.t.sol`
- Test: `forge test`

**Interfaces:**
- Consumes: existing `RoyalCityRealEstate` behavior
- Produces: `initialize(address,address,string,uint48)`, `upgradeToAndCall(address,bytes)` restricted to `DEFAULT_ADMIN_ROLE`, proxy deployment helper used by tests

- [ ] Install `openzeppelin-contracts-upgradeable` v5.6.1 and add the remapping.
- [ ] Replace parent constructors with upgradeable initializers, disable initializers on the implementation, and authorize upgrades with `DEFAULT_ADMIN_ROLE`.
- [ ] Deploy tests through `ERC1967Proxy`.
- [ ] Add admin-upgrade, outsider-upgrade, and implementation-initialize tests.
- [ ] Run `forge test`. Expected: full suite passes.

### Task 2: Deploy script and README

**Files:**
- Modify: `script/DeployRoyalCity.s.sol`
- Modify: `README.md`

- [ ] Deploy implementation then proxy; return the proxy.
- [ ] Document that users call the proxy and only the default admin can upgrade.
- [ ] Run `forge test` again.
