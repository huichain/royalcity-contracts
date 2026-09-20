# KYC Tiers (on-chain gate)

## Goal

Replace a boolean whitelist with per-account `kycTier` and per-property `minKycTier`. Compliance still writes the number; no KYC vendor on-chain.

## Rules

- `kycTier[account] == 0` means not approved (`NotWhitelisted`).
- `setWhitelist(account, true)` sets tier `1`; `false` sets `0` (keeps existing tests/scripts).
- `setKycTier(account, tier)` is the general compliance write; `tier > 0` also sets `whitelisted = true`.
- New properties default `minKycTier = 1`. Manager may change it only in `Draft` via `setDraftMinKycTier` (`minKycTier >= 1`).
- `invest`, `claimRevenue`, `redeem`, and share transfers require `kycTier >= property.minKycTier` (`InsufficientKyc` if approved but too low). Both transfer parties must meet the property minimum.
- `refund` does not check KYC (avoid stuck principal after a downgrade).

## Out of scope

Vendor APIs, webhooks, identity documents, zkKYC.
