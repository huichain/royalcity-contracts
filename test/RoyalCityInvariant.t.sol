// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract RoyalCityInvestmentHandler is Test {
    uint256 internal constant USDC_UNIT = 1e6;

    MockUSDC internal immutable MOCK_USDC;
    RoyalCityRealEstate internal immutable REAL_ESTATE;
    uint256 internal immutable PROPERTY_ID;

    address[] internal investors;
    uint256 public expectedRaised;
    uint256 public expectedShares;

    constructor(MockUSDC usdc_, RoyalCityRealEstate realEstate_, uint256 propertyId_) {
        MOCK_USDC = usdc_;
        REAL_ESTATE = realEstate_;
        PROPERTY_ID = propertyId_;

        investors.push(address(0x1001));
        investors.push(address(0x1002));
        investors.push(address(0x1003));

        for (uint256 i = 0; i < investors.length; i++) {
            address investor = investors[i];
            MOCK_USDC.mint(investor, 10_000 * USDC_UNIT);

            vm.prank(investor);
            MOCK_USDC.approve(address(REAL_ESTATE), type(uint256).max);
        }
    }

    function invest(uint8 rawInvestorIndex, uint8 rawShares) external {
        address investor = investors[uint256(rawInvestorIndex) % investors.length];
        uint256 shares = uint256(rawShares % 25) + 1;
        uint256 cost = shares * 10 * USDC_UNIT;

        if (expectedShares + shares > 100) {
            return;
        }
        if (REAL_ESTATE.investedAmount(PROPERTY_ID, investor) + cost > 700 * USDC_UNIT) {
            return;
        }

        vm.prank(investor);
        REAL_ESTATE.invest(PROPERTY_ID, shares);

        expectedShares += shares;
        expectedRaised += cost;
    }
}

contract RoyalCityInvariantTest is StdInvariant, Test {
    uint256 internal constant USDC = 1e6;

    MockUSDC internal usdc;
    RoyalCityRealEstate internal realEstate;
    RoyalCityInvestmentHandler internal handler;
    uint256 internal propertyId;
    address internal treasury = address(0xA11CE);

    function setUp() public {
        usdc = new MockUSDC();
        realEstate = new RoyalCityRealEstate(address(usdc), treasury, "ipfs://royalcity/{id}.json", 2 days);

        propertyId = realEstate.createProperty(
            "ipfs://property-invariant", 100, 10 * USDC, 1_000 * USDC, 10 * USDC, 700 * USDC, block.timestamp + 30 days
        );
        realEstate.startFunding(propertyId);

        realEstate.setWhitelist(address(0x1001), true);
        realEstate.setWhitelist(address(0x1002), true);
        realEstate.setWhitelist(address(0x1003), true);

        handler = new RoyalCityInvestmentHandler(usdc, realEstate, propertyId);
        targetContract(address(handler));
    }

    function invariant_RaisedAmountMatchesMintedShares() public view {
        RoyalCityRealEstate.Property memory property = realEstate.getProperty(propertyId);

        assertEq(property.soldShares, handler.expectedShares());
        assertEq(property.raisedAmount, handler.expectedRaised());
        assertEq(realEstate.totalSupply(propertyId), handler.expectedShares());
        assertEq(usdc.balanceOf(address(realEstate)), handler.expectedRaised());
        assertLe(property.soldShares, property.totalShares);
    }
}
