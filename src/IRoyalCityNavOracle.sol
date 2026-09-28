// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IRoyalCityNavOracle {
    /// @notice Fresh per-share NAV in payment-token units. Reverts if missing or stale.
    function navPerShare(uint256 propertyId) external view returns (uint256);
}
