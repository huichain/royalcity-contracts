// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IRoyalCityNavOracle} from "./IRoyalCityNavOracle.sol";

/// @notice Permissioned per-share NAV. Not a market price feed.
///         RoyalCity reads `navPerShare` when an investor redeems.
contract RoyalCityNavOracle is AccessControl, IRoyalCityNavOracle {
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint256 internal constant BPS = 10_000;

    struct Nav {
        uint256 perShare;
        uint256 updatedAt;
    }

    /// @notice Quotes older than this are rejected. Default 7 days.
    uint256 public maxNavAge = 7 days;
    /// @notice Max move versus the previous quote, in basis points. 2000 = 20%.
    uint256 public maxNavDeviationBps = 2_000;

    mapping(uint256 propertyId => Nav nav) internal _navs;

    error InvalidAmount();
    error InvalidPrice();
    error NavNotSet();
    error StaleNav();
    error NavDeviationExceeded();

    event NavUpdated(uint256 indexed propertyId, uint256 navPerShare, uint256 updatedAt);

    constructor(address admin) {
        if (admin == address(0)) revert InvalidAmount();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ORACLE_ROLE, admin);
    }

    function setMaxNavAge(uint256 maxNavAge_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxNavAge_ == 0) revert InvalidAmount();
        maxNavAge = maxNavAge_;
    }

    function setMaxNavDeviationBps(uint256 maxNavDeviationBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (maxNavDeviationBps_ > BPS) revert InvalidAmount();
        maxNavDeviationBps = maxNavDeviationBps_;
    }

    function setNav(uint256 propertyId, uint256 navPerShare_) external onlyRole(ORACLE_ROLE) {
        if (navPerShare_ == 0) revert InvalidPrice();

        uint256 previous = _navs[propertyId].perShare;
        if (previous != 0) {
            uint256 diff = navPerShare_ > previous ? navPerShare_ - previous : previous - navPerShare_;
            if (diff * BPS / previous > maxNavDeviationBps) revert NavDeviationExceeded();
        }

        _navs[propertyId] = Nav({perShare: navPerShare_, updatedAt: block.timestamp});

        emit NavUpdated(propertyId, navPerShare_, block.timestamp);
    }

    /// @notice Fresh per-share NAV in PAYMENT_TOKEN units. Reverts if missing or stale.
    function navPerShare(uint256 propertyId) external view override returns (uint256) {
        Nav memory nav = _navs[propertyId];
        if (nav.perShare == 0) revert NavNotSet();
        if (block.timestamp > nav.updatedAt + maxNavAge) revert StaleNav();
        return nav.perShare;
    }
}
