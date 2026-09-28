# Management fee on rental deposits

## Goal

Take one protocol fee from rental USDC when it is deposited. Shareholders split only the remainder. Invest, refund, claim, and redeem stay free of this fee.

## Rate

- `managementFeeBps` is a single global rate. `10_000` is 100%. `500` is 5%.
- Default is `0`, so existing revenue splits stay unchanged until an admin sets a rate.
- Only `DEFAULT_ADMIN_ROLE` may call `setManagementFeeBps`.
- A rate above `10_000` reverts.

## depositRevenue

Treasury still approves and transfers the full `amount`.

- `fee = amount * managementFeeBps / 10_000`
- `net = amount - fee`
- The contract transfers `fee` to `treasury` immediately.
- Only `net` is added to `revenueDeposited` and `revenuePerShare`.
- `claimRevenue` therefore pays shareholders the post-fee amount.
- Integer division leaves any dust in `net`. A fee that rounds to `0` distributes the full deposit.
- A rate of `10_000` sends the whole deposit to `treasury` and credits shareholders `0`. That call still succeeds when `net` is `0`; it does not increase the per-share accumulator.

`RevenueDeposited` continues to report the gross `amount` pulled from the depositor. A new `ManagementFeeCollected(propertyId, fee)` event records the skim.

## Out of scope

Per-property rates, fees on invest, refund, claim, or redeem, and a fee recipient other than `treasury`.
