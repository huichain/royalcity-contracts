# UUPS upgrade for RoyalCityRealEstate

## Goal

Keep one stable share-contract address. Logic lives in an implementation contract and can be replaced by the default admin. `RoyalCityNavOracle` stays a normal contract.

## Deployment

1. Deploy `RoyalCityRealEstate` (the implementation). Its constructor only calls `_disableInitializers()`.
2. Deploy `ERC1967Proxy` with `initialize(paymentToken, treasury, defaultURI, defaultAdminDelay)`.
3. `initialize` runs in the proxy's storage and may run only once. It sets the payment token, treasury, ERC1155 URI, default admin delay, and grants `MANAGER_ROLE` and `COMPLIANCE_ROLE` to the caller and `TREASURY_ROLE` to the treasury. The caller is the proxy deployer, same as today's constructor.

Users, tests, and `setNavOracle` use the proxy address.

## Inheritance

Switch the share contract to the upgradeable OpenZeppelin bases (v5.5, same release as the current `openzeppelin-contracts`) plus `UUPSUpgradeable`:

- `ERC1155SupplyUpgradeable`
- `AccessControlDefaultAdminRulesUpgradeable`
- `PausableUpgradeable`
- `ReentrancyGuardUpgradeable`

`openzeppelin-contracts-upgradeable` is not in the repo yet. Add that dependency before changing the contract. Do not copy initializer code by hand.

## Upgrade authority

Override `_authorizeUpgrade` so only `DEFAULT_ADMIN_ROLE` can upgrade. No new role. This change does not require Timelock. If that admin is later a Timelock, the delay comes from the Timelock, not from a second rule here.

## Storage

`PAYMENT_TOKEN` is `immutable` today. Immutables live in the implementation bytecode, so a new implementation would not keep the proxy's token. Change it to a normal `IERC20 public PAYMENT_TOKEN` assigned in `initialize`.

No proxy is deployed yet, so this layout is the first one. After the first proxy deployment, do not reorder or remove existing RoyalCity variables. OpenZeppelin v5 upgradeable parents keep their own namespaced storage; RoyalCity's variables stay in the contract's linear layout.

## Tests

Existing tests, Timelock tests, and invariant tests construct the share contract directly. Deploy implementation plus proxy in those setups and keep using the proxy as `RoyalCityRealEstate`.

Add these cases:

- Default admin upgrades to a test V2 that exposes a new function. A property and share balance created before the upgrade are still readable.
- An account without `DEFAULT_ADMIN_ROLE` cannot upgrade.
- Calling `initialize` on the implementation reverts.

V2 exists only under `test/`. It is not a production contract.

## Deploy script

`script/DeployRoyalCity.s.sol` deploys the implementation and the proxy, and returns the proxy. It still does not deploy the NAV oracle.

## Docs

README states that the share contract users call is the proxy, and that only the default admin can upgrade it. The existing Sepolia address is not a proxy and cannot be upgraded in place.

## Out of scope

NAV oracle upgrades, protocol fees, redemption-pool fairness, secondary market, forcing upgrades through Timelock, and migrating the current Sepolia deployment.
