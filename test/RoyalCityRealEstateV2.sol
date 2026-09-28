// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";

/// @dev Upgrade target used only in tests. Adds a view so tests can see the new implementation.
contract RoyalCityRealEstateV2 is RoyalCityRealEstate {
    function version() external pure returns (uint256) {
        return 2;
    }
}
