// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract RoyalCityRealEstateTest is Test {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant DEFAULT_TOTAL_SHARES = 100;
    uint256 internal constant DEFAULT_SHARE_PRICE = 10 * USDC;
    uint256 internal constant DEFAULT_FUNDING_TARGET = 1_000 * USDC;
    uint256 internal constant DEFAULT_MIN_INVESTMENT = 10 * USDC;
    uint256 internal constant DEFAULT_MAX_INVESTMENT = 700 * USDC;
    uint48 internal constant DEFAULT_ADMIN_DELAY = 2 days;

    MockUSDC internal usdc;
    RoyalCityRealEstate internal realEstate;

    address internal treasury = address(0xA11CE);
    address internal newTreasury = address(0xA22CE);
    address internal investor = address(0xB0B);
    address internal secondInvestor = address(0xCAFE);
    address internal outsider = address(0xBAD);
    address internal newAdmin = address(0xDAD);

    function setUp() public {
        usdc = new MockUSDC();
        realEstate = new RoyalCityRealEstate(address(usdc), treasury, "ipfs://royalcity/{id}.json", DEFAULT_ADMIN_DELAY);

        realEstate.setWhitelist(investor, true);
        realEstate.setWhitelist(secondInvestor, true);

        usdc.mint(investor, 10_000 * USDC);
        usdc.mint(secondInvestor, 10_000 * USDC);
        usdc.mint(treasury, 10_000 * USDC);
        usdc.mint(newTreasury, 10_000 * USDC);

        vm.prank(investor);
        usdc.approve(address(realEstate), type(uint256).max);

        vm.prank(secondInvestor);
        usdc.approve(address(realEstate), type(uint256).max);

        vm.prank(treasury);
        usdc.approve(address(realEstate), type(uint256).max);

        vm.prank(newTreasury);
        usdc.approve(address(realEstate), type(uint256).max);
    }

    function test_CreatePropertyAndStartFunding() public {
        uint256 deadline = block.timestamp + 30 days;
        uint256 propertyId = realEstate.createProperty(
            "ipfs://property-1",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            DEFAULT_MIN_INVESTMENT,
            DEFAULT_MAX_INVESTMENT,
            deadline
        );

        realEstate.startFunding(propertyId);

        RoyalCityRealEstate.Property memory property = realEstate.getProperty(propertyId);
        assertEq(property.metadataURI, "ipfs://property-1");
        assertEq(property.totalShares, DEFAULT_TOTAL_SHARES);
        assertEq(property.sharePrice, DEFAULT_SHARE_PRICE);
        assertEq(property.fundingTarget, DEFAULT_FUNDING_TARGET);
        assertEq(property.minInvestment, DEFAULT_MIN_INVESTMENT);
        assertEq(property.maxInvestment, DEFAULT_MAX_INVESTMENT);
        assertEq(property.fundingDeadline, deadline);
        assertFalse(property.paused);
        assertEq(property.minKycTier, 1);
        assertEq(uint8(property.state), uint8(RoyalCityRealEstate.PropertyState.Funding));
    }

    function test_DefaultAdminTransferRequiresDelay() public {
        realEstate.beginDefaultAdminTransfer(newAdmin);

        vm.prank(newAdmin);
        vm.expectRevert();
        realEstate.acceptDefaultAdminTransfer();

        vm.warp(block.timestamp + DEFAULT_ADMIN_DELAY + 1);

        vm.prank(newAdmin);
        realEstate.acceptDefaultAdminTransfer();

        assertEq(realEstate.defaultAdmin(), newAdmin);
        assertTrue(realEstate.hasRole(realEstate.DEFAULT_ADMIN_ROLE(), newAdmin));
        assertFalse(realEstate.hasRole(realEstate.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function test_RevertWhen_GrantingDefaultAdminDirectly() public {
        bytes32 defaultAdminRole = realEstate.DEFAULT_ADMIN_ROLE();

        vm.expectRevert();
        realEstate.grantRole(defaultAdminRole, newAdmin);
    }

    function test_ManagerCanUpdateDraftPropertyTerms() public {
        uint256 propertyId = realEstate.createProperty(
            "ipfs://property-draft",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            DEFAULT_MIN_INVESTMENT,
            DEFAULT_MAX_INVESTMENT,
            block.timestamp + 30 days
        );

        uint256 newDeadline = block.timestamp + 45 days;
        realEstate.updateDraftPropertyTerms(
            propertyId, "ipfs://property-draft-v2", 120, 12 * USDC, 1_200 * USDC, 24 * USDC, 800 * USDC, newDeadline
        );

        RoyalCityRealEstate.Property memory property = realEstate.getProperty(propertyId);
        assertEq(property.metadataURI, "ipfs://property-draft-v2");
        assertEq(property.totalShares, 120);
        assertEq(property.sharePrice, 12 * USDC);
        assertEq(property.fundingTarget, 1_200 * USDC);
        assertEq(property.minInvestment, 24 * USDC);
        assertEq(property.maxInvestment, 800 * USDC);
        assertEq(property.fundingDeadline, newDeadline);
        assertEq(property.minKycTier, 1);
    }

    function test_RevertWhen_UpdatingTermsAfterFundingStarts() public {
        uint256 propertyId = _createFundingProperty();

        vm.expectRevert(RoyalCityRealEstate.InvalidState.selector);
        realEstate.updateDraftPropertyTerms(
            propertyId,
            "ipfs://property-started-v2",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            DEFAULT_MIN_INVESTMENT,
            DEFAULT_MAX_INVESTMENT,
            block.timestamp + 30 days
        );
    }

    function test_RevertWhen_NonWhitelistedInvestorBuysShares() public {
        uint256 propertyId = _createFundingProperty();

        vm.startPrank(outsider);
        usdc.approve(address(realEstate), type(uint256).max);
        vm.expectRevert(RoyalCityRealEstate.NotWhitelisted.selector);
        realEstate.invest(propertyId, 1);
        vm.stopPrank();
    }

    function test_WhitelistedInvestorBuysShares() public {
        uint256 propertyId = _createFundingProperty();

        vm.prank(investor);
        realEstate.invest(propertyId, 25);

        RoyalCityRealEstate.Property memory property = realEstate.getProperty(propertyId);
        assertEq(realEstate.balanceOf(investor, propertyId), 25);
        assertEq(realEstate.investedAmount(propertyId, investor), 250 * USDC);
        assertEq(property.soldShares, 25);
        assertEq(property.raisedAmount, 250 * USDC);
        assertEq(usdc.balanceOf(address(realEstate)), 250 * USDC);
    }

    function test_RevertWhen_BuyingMoreThanAvailableSupply() public {
        uint256 propertyId = _createFundingProperty();

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.SoldOut.selector);
        realEstate.invest(propertyId, 101);
    }

    function test_RevertWhen_InvestmentIsBelowMinimum() public {
        uint256 propertyId = realEstate.createProperty(
            "ipfs://property-min",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            20 * USDC,
            DEFAULT_MAX_INVESTMENT,
            block.timestamp + 30 days
        );
        realEstate.startFunding(propertyId);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.InvestmentBelowMinimum.selector);
        realEstate.invest(propertyId, 1);
    }

    function test_RevertWhen_CumulativeInvestmentExceedsMaximum() public {
        uint256 propertyId = _createFundingProperty();

        vm.prank(investor);
        realEstate.invest(propertyId, 60);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.InvestmentAboveMaximum.selector);
        realEstate.invest(propertyId, 11);
    }

    function test_RevertWhen_FundingDeadlineExpired() public {
        uint256 propertyId = _createFundingProperty();

        vm.warp(block.timestamp + 31 days);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.FundingExpired.selector);
        realEstate.invest(propertyId, 10);
    }

    function test_CancelledFundingAllowsRefundOnce() public {
        uint256 propertyId = _createFundingProperty();

        vm.prank(investor);
        realEstate.invest(propertyId, 10);

        realEstate.cancelFunding(propertyId);

        uint256 beforeRefund = usdc.balanceOf(investor);

        vm.prank(investor);
        realEstate.refund(propertyId);

        assertEq(usdc.balanceOf(investor), beforeRefund + 100 * USDC);
        assertEq(realEstate.balanceOf(investor, propertyId), 0);
        assertEq(realEstate.investedAmount(propertyId, investor), 0);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.NothingToRefund.selector);
        realEstate.refund(propertyId);
    }

    function test_FinalizedFundingTransfersPrincipalToTreasury() public {
        uint256 propertyId = _fullyFundProperty();

        uint256 beforeFinalize = usdc.balanceOf(treasury);
        realEstate.finalizeFunding(propertyId);

        RoyalCityRealEstate.Property memory property = realEstate.getProperty(propertyId);
        assertEq(uint8(property.state), uint8(RoyalCityRealEstate.PropertyState.Funded));
        assertEq(usdc.balanceOf(treasury), beforeFinalize + 1_000 * USDC);
        assertEq(usdc.balanceOf(address(realEstate)), 0);
    }

    function test_RevenueIsClaimedProRataByShareholders() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        vm.prank(treasury);
        realEstate.depositRevenue(propertyId, 100 * USDC);

        uint256 investorBefore = usdc.balanceOf(investor);
        uint256 secondBefore = usdc.balanceOf(secondInvestor);

        vm.prank(investor);
        realEstate.claimRevenue(propertyId);

        vm.prank(secondInvestor);
        realEstate.claimRevenue(propertyId);

        assertEq(usdc.balanceOf(investor), investorBefore + 60 * USDC);
        assertEq(usdc.balanceOf(secondInvestor), secondBefore + 40 * USDC);
        assertEq(realEstate.pendingRevenue(propertyId, investor), 0);
        assertEq(realEstate.pendingRevenue(propertyId, secondInvestor), 0);
    }

    function test_RevertWhen_UnauthorizedAccountDepositsRevenue() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        vm.prank(outsider);
        vm.expectRevert(RoyalCityRealEstate.UnauthorizedDepositor.selector);
        realEstate.depositRevenue(propertyId, 100 * USDC);
    }

    function test_TreasuryRotationRevokesDefaultTreasuryRole() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        realEstate.setTreasury(newTreasury);

        vm.prank(treasury);
        vm.expectRevert(RoyalCityRealEstate.UnauthorizedDepositor.selector);
        realEstate.depositRevenue(propertyId, 100 * USDC);

        vm.prank(newTreasury);
        realEstate.depositRevenue(propertyId, 100 * USDC);

        assertEq(realEstate.pendingRevenue(propertyId, investor), 60 * USDC);
        assertEq(realEstate.pendingRevenue(propertyId, secondInvestor), 40 * USDC);
    }

    function test_TransfersRequireBothSidesWhitelistedAfterFunding() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.NotWhitelisted.selector);
        realEstate.safeTransferFrom(investor, outsider, propertyId, 5, "");

        realEstate.setWhitelist(outsider, true);

        vm.prank(investor);
        realEstate.safeTransferFrom(investor, outsider, propertyId, 5, "");

        assertEq(realEstate.balanceOf(outsider, propertyId), 5);
        assertEq(realEstate.balanceOf(investor, propertyId), 55);
    }

    function test_SetWhitelistSetsKycTierOne() public {
        assertEq(realEstate.kycTier(investor), 1);
        assertTrue(realEstate.whitelisted(investor));

        realEstate.setKycTier(outsider, 2);
        assertEq(realEstate.kycTier(outsider), 2);
        assertTrue(realEstate.whitelisted(outsider));

        realEstate.setWhitelist(outsider, false);
        assertEq(realEstate.kycTier(outsider), 0);
        assertFalse(realEstate.whitelisted(outsider));
    }

    function test_RevertWhen_KycTierBelowPropertyMinimum() public {
        uint256 propertyId = realEstate.createProperty(
            "ipfs://kyc-gated",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            DEFAULT_MIN_INVESTMENT,
            DEFAULT_MAX_INVESTMENT,
            block.timestamp + 30 days
        );
        realEstate.setDraftMinKycTier(propertyId, 2);
        realEstate.startFunding(propertyId);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.InsufficientKyc.selector);
        realEstate.invest(propertyId, 10);

        realEstate.setKycTier(investor, 2);

        vm.prank(investor);
        realEstate.invest(propertyId, 10);

        assertEq(realEstate.balanceOf(investor, propertyId), 10);
    }

    function test_RevertWhen_SetDraftMinKycTierAfterFundingStarts() public {
        uint256 propertyId = _createFundingProperty();

        vm.expectRevert(RoyalCityRealEstate.InvalidState.selector);
        realEstate.setDraftMinKycTier(propertyId, 2);
    }

    function test_TransferRequiresReceiverToMeetMinKycTier() public {
        uint256 propertyId = realEstate.createProperty(
            "ipfs://kyc-transfer",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            DEFAULT_MIN_INVESTMENT,
            DEFAULT_MAX_INVESTMENT,
            block.timestamp + 30 days
        );
        realEstate.setDraftMinKycTier(propertyId, 2);
        realEstate.setKycTier(investor, 2);
        realEstate.setKycTier(secondInvestor, 2);
        realEstate.startFunding(propertyId);

        vm.prank(investor);
        realEstate.invest(propertyId, 60);
        vm.prank(secondInvestor);
        realEstate.invest(propertyId, 40);
        realEstate.finalizeFunding(propertyId);

        realEstate.setWhitelist(outsider, true);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.InsufficientKyc.selector);
        realEstate.safeTransferFrom(investor, outsider, propertyId, 5, "");

        realEstate.setKycTier(outsider, 2);

        vm.prank(investor);
        realEstate.safeTransferFrom(investor, outsider, propertyId, 5, "");

        assertEq(realEstate.balanceOf(outsider, propertyId), 5);
    }

    function test_PauseBlocksInvestingAndTransfersButNotRefunds() public {
        uint256 propertyId = _createFundingProperty();

        realEstate.pause();

        vm.prank(investor);
        vm.expectRevert();
        realEstate.invest(propertyId, 1);

        realEstate.unpause();

        vm.prank(investor);
        realEstate.invest(propertyId, 10);

        realEstate.cancelFunding(propertyId);
        realEstate.pause();

        vm.prank(investor);
        realEstate.refund(propertyId);

        assertEq(realEstate.balanceOf(investor, propertyId), 0);
    }

    function test_PropertyPauseBlocksOnlyThatProperty() public {
        uint256 pausedPropertyId = _createFundingProperty();
        uint256 activePropertyId = _createFundingProperty();

        realEstate.setPropertyPaused(pausedPropertyId, true);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.PropertyPaused.selector);
        realEstate.invest(pausedPropertyId, 10);

        vm.prank(investor);
        realEstate.invest(activePropertyId, 10);

        assertEq(realEstate.balanceOf(investor, activePropertyId), 10);
    }

    function test_PropertyPauseBlocksTransfersButNotRefunds() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        realEstate.setPropertyPaused(propertyId, true);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.PropertyPaused.selector);
        realEstate.safeTransferFrom(investor, secondInvestor, propertyId, 1, "");

        uint256 refundPropertyId = _createFundingProperty();

        vm.prank(investor);
        realEstate.invest(refundPropertyId, 10);

        realEstate.cancelFunding(refundPropertyId);
        realEstate.setPropertyPaused(refundPropertyId, true);

        vm.prank(investor);
        realEstate.refund(refundPropertyId);

        assertEq(realEstate.balanceOf(investor, refundPropertyId), 0);
    }

    function testFuzz_WhitelistedInvestorBuysWithinLimits(uint8 rawShares) public {
        uint256 shares = bound(uint256(rawShares), 1, 70);
        uint256 propertyId = _createFundingProperty();

        vm.prank(investor);
        realEstate.invest(propertyId, shares);

        uint256 expectedCost = shares * DEFAULT_SHARE_PRICE;
        assertEq(realEstate.balanceOf(investor, propertyId), shares);
        assertEq(realEstate.investedAmount(propertyId, investor), expectedCost);
    }

    function test_RevertWhen_RedeemWhileFunded() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.InvalidState.selector);
        realEstate.redeem(propertyId, 1);
    }

    function test_RevertWhen_RedeemWithEmptyPool() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.NothingToRedeem.selector);
        realEstate.redeem(propertyId, 10);
    }

    function test_RevertWhen_NonWhitelistedRedeems() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 1_000 * USDC);

        vm.prank(outsider);
        vm.expectRevert(RoyalCityRealEstate.NotWhitelisted.selector);
        realEstate.redeem(propertyId, 1);
    }

    function test_RevertWhen_RedeemZeroShares() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 1_000 * USDC);

        vm.prank(investor);
        vm.expectRevert(RoyalCityRealEstate.InvalidAmount.selector);
        realEstate.redeem(propertyId, 0);
    }

    function test_DepositRedemptionAndRedeemProRata() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 1_000 * USDC);

        uint256 investorBefore = usdc.balanceOf(investor);
        uint256 secondBefore = usdc.balanceOf(secondInvestor);

        vm.prank(investor);
        realEstate.redeem(propertyId, 60);

        vm.prank(secondInvestor);
        realEstate.redeem(propertyId, 40);

        assertEq(usdc.balanceOf(investor), investorBefore + 600 * USDC);
        assertEq(usdc.balanceOf(secondInvestor), secondBefore + 400 * USDC);
        assertEq(realEstate.balanceOf(investor, propertyId), 0);
        assertEq(realEstate.balanceOf(secondInvestor, propertyId), 0);
        assertEq(realEstate.getProperty(propertyId).redemptionPool, 0);
    }

    function test_RedeemAutoClaimsPendingRevenue() public {
        uint256 propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);

        vm.prank(treasury);
        realEstate.depositRevenue(propertyId, 100 * USDC);

        realEstate.closeProperty(propertyId);

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 1_000 * USDC);

        uint256 before = usdc.balanceOf(investor);

        vm.prank(investor);
        realEstate.redeem(propertyId, 60);

        // 60% of 100 revenue + 60% of 1000 redemption
        assertEq(usdc.balanceOf(investor), before + 60 * USDC + 600 * USDC);
        assertEq(realEstate.pendingRevenue(propertyId, investor), 0);
        assertEq(realEstate.balanceOf(investor, propertyId), 0);
    }

    function test_PartialRedeemUpdatesPool() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 1_000 * USDC);

        vm.prank(investor);
        realEstate.redeem(propertyId, 30); // half of investor's 60

        assertEq(realEstate.balanceOf(investor, propertyId), 30);
        // payout = 30 * 1000 / 100 = 300; pool left 700
        assertEq(realEstate.getProperty(propertyId).redemptionPool, 700 * USDC);
    }

    function test_PauseDoesNotBlockRedeem() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 1_000 * USDC);

        realEstate.pause();
        realEstate.setPropertyPaused(propertyId, true);

        vm.prank(investor);
        realEstate.redeem(propertyId, 60);

        assertEq(realEstate.balanceOf(investor, propertyId), 0);
    }

    function test_RevertWhen_UnauthorizedDepositRedemption() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(outsider);
        vm.expectRevert(RoyalCityRealEstate.UnauthorizedDepositor.selector);
        realEstate.depositRedemption(propertyId, 100 * USDC);
    }

    function test_MultipleRedemptionDepositsAccumulate() public {
        uint256 propertyId = _closeFundedProperty();

        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 400 * USDC);
        vm.prank(treasury);
        realEstate.depositRedemption(propertyId, 600 * USDC);

        assertEq(realEstate.getProperty(propertyId).redemptionPool, 1_000 * USDC);
    }

    function _createFundingProperty() internal returns (uint256 propertyId) {
        propertyId = realEstate.createProperty(
            "ipfs://property-1",
            DEFAULT_TOTAL_SHARES,
            DEFAULT_SHARE_PRICE,
            DEFAULT_FUNDING_TARGET,
            DEFAULT_MIN_INVESTMENT,
            DEFAULT_MAX_INVESTMENT,
            block.timestamp + 30 days
        );
        realEstate.startFunding(propertyId);
    }

    function _fullyFundProperty() internal returns (uint256 propertyId) {
        propertyId = _createFundingProperty();

        vm.prank(investor);
        realEstate.invest(propertyId, 60);

        vm.prank(secondInvestor);
        realEstate.invest(propertyId, 40);
    }

    function _closeFundedProperty() internal returns (uint256 propertyId) {
        propertyId = _fullyFundProperty();
        realEstate.finalizeFunding(propertyId);
        realEstate.closeProperty(propertyId);
    }
}
