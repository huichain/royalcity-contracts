# Redeem (Closed Property Exit) Design

## Goal

Add a post-funding exit so investors can burn shares for PAYMENT_TOKEN after a property is `Closed`, funded by an explicit redemption pool (principal already left the contract at `finalizeFunding`).

## Decisions (approved)

- **When:** Only in `PropertyState.Closed`.
- **Funding:** Treasury (or manager, same as revenue deposit) calls `depositRedemption(propertyId, amount)` to grow `redemptionPool`.
- **Payout:** Pro-rata — `payout = shares * redemptionPool / totalSupply` (supply read before burn).
- **Pending revenue:** `redeem` auto-settles and pays pending/accrued revenue first, then redeems shares (same accounting as `claimRevenue`).
- **Partial redeem:** Allowed.
- **Pause:** Global / per-property pause does **not** block `redeem` (same policy as `refund` / `claimRevenue`).

## Non-goals

- Open redemption while still `Funded` without close.
- Fixed per-share buyback price.
- On-chain NAV / oracle pricing.
- Changing `finalizeFunding` to keep principal in the contract.

## Flow

```text
Funded → (optional revenue deposit/claim) → closeProperty
      → depositRedemption (one or more times)
      → redeem(shares) → settle revenue + burn + pay pool share
```

## Contract changes (`RoyalCityRealEstate.sol`)

### State

- Add `mapping(uint256 propertyId => uint256 amount) public redemptionPool` (or field on `Property` — prefer mapping to avoid widening every property read unless we already touch the struct for clarity; **prefer `Property.redemptionPool`** for one place to inspect property accounting).

Recommendation: add `uint256 redemptionPool` on `Property`.

### Functions

1. `depositRedemption(uint256 propertyId, uint256 amount)`
   - `nonReentrant`, authorized like `depositRevenue` (`TREASURY_ROLE` or `MANAGER_ROLE`).
   - Require `Closed`, `amount > 0`.
   - Pull tokens via `SafeERC20`, increment `redemptionPool`.
   - Emit `RedemptionDeposited(propertyId, depositor, amount)`.

2. `redeem(uint256 propertyId, uint256 shares)`
   - `nonReentrant`.
   - Require whitelisted, `Closed`, `shares > 0`, `balanceOf >= shares`.
   - `_settleRevenue(propertyId, msg.sender)`; if `accruedRevenue > 0`, pay it out and zero (emit `RevenueClaimed` or include in redeem event — prefer existing `RevenueClaimed` for clarity).
   - `supply = totalSupply(propertyId)`; require `supply > 0` and `redemptionPool > 0` (or allow redeem with 0 pool only if payout is 0? **revert if payout would be 0 and pool is 0** — if pool > 0 but tiny dust, pay floor).
   - `payout = shares * redemptionPool / supply`; require `payout > 0` **or** allow 0-payout burn when pool is empty? **Policy: revert `NothingToRedeem` if `redemptionPool == 0`; if pool > 0 but rounding yields 0 for tiny share, revert `NothingToRedeem`.**
   - Decrement `redemptionPool` by `payout`, `_burn`, transfer `payout`.
   - Emit `Redeemed(propertyId, investor, shares, payout)`.

### Errors / events

- `NothingToRedeem`, reuse `InvalidState`, `NotWhitelisted`, `InvalidAmount`, `UnauthorizedDepositor`, `NoShares` as needed.
- Events: `RedemptionDeposited`, `Redeemed`.

## Invariants

- After any redeem: `redemptionPool` decreases by exactly the sum of payouts.
- `redemptionPool` never exceeds contract PAYMENT_TOKEN balance attributable to redemption (plus any residual revenue dust accounting stays separate — revenue and redemption pools are both held as the same ERC20 balance; **do not** let redeem pull from funds still owed as `accruedRevenue` / pending. Practical rule: payouts only reduce `redemptionPool`; revenue settlement only uses settled claim amounts. Contract ERC20 balance must remain ≥ sum of remaining `redemptionPool` across properties + unpaid accrued liabilities. Tests should fund pools explicitly and claim/settle before asserting balances.)

## Tests

- Revert redeem when not `Closed` / not whitelisted / zero shares / no pool.
- Auto-settles pending revenue before burn.
- Two investors redeem pro-rata; partial redeem updates balances and pool.
- Multiple `depositRedemption` calls accumulate.
- Pause does not block redeem.

## Docs (after implementation)

- Update README core flow + exit layer: `Closed` → deposit redemption → redeem.
- Mark skeleton “future redeem” as implemented for this MVP path.

## Done when

- `forge test` green including new redeem cases.
- README updated to match.
