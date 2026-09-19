// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RoyalCityRealEstate is ERC1155Supply, AccessControlDefaultAdminRules, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Property lifecycle is intentionally strict so refunds and principal withdrawal
    // cannot both be active for the same asset.
    enum PropertyState {
        Draft,
        Funding,
        Funded,
        Cancelled,
        Closed
    }

    struct Property {
        uint256 totalShares; // Max share supply for this property (ERC1155 id)
        uint256 sharePrice; // PAYMENT_TOKEN amount required per share
        uint256 fundingTarget; // Target raise; finalize when raisedAmount reaches this
        uint256 minInvestment; // Minimum payment amount per invest call
        uint256 maxInvestment; // Cap on cumulative investedAmount per investor
        uint256 fundingDeadline; // Unix timestamp after which invest is rejected
        uint256 soldShares; // Shares minted so far
        uint256 raisedAmount; // PAYMENT_TOKEN collected during funding
        uint256 revenueDeposited; // Lifetime revenue deposited for claims
        PropertyState state; // Draft / Funding / Funded / Cancelled / Closed
        bool paused; // Per-property pause (invest / revenue blocked when true)
        string metadataURI; // Off-chain metadata pointer for this property
    }

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    uint256 internal constant REWARD_PRECISION = 1e24;

    IERC20 public immutable PAYMENT_TOKEN;
    address public treasury;
    uint256 public nextPropertyId = 1;

    mapping(uint256 propertyId => Property property) internal _properties;
    mapping(address account => bool approved) public whitelisted;
    mapping(uint256 propertyId => mapping(address account => uint256 amount)) public investedAmount;
    mapping(uint256 propertyId => uint256 rewardPerShare) public revenuePerShare;
    mapping(uint256 propertyId => mapping(address account => uint256 rewardDebt)) public userRevenueDebt;
    mapping(uint256 propertyId => mapping(address account => uint256 accruedRevenue)) public accruedRevenue;

    error ZeroAddress();
    error InvalidProperty();
    error InvalidSupply();
    error InvalidPrice();
    error InvalidFundingTarget();
    error InvalidInvestmentLimits();
    error InvalidDeadline();
    error InvalidState();
    error InvalidAmount();
    error NotWhitelisted();
    error SoldOut();
    error InvestmentBelowMinimum();
    error InvestmentAboveMaximum();
    error FundingExpired();
    error PropertyPaused();
    error FundingNotComplete();
    error RefundUnavailable();
    error NothingToRefund();
    error NothingToClaim();
    error NoShares();
    error UnauthorizedDepositor();

    event TreasuryUpdated(address indexed treasury);
    event WhitelistUpdated(address indexed account, bool approved);
    event PropertyCreated(
        uint256 indexed propertyId,
        uint256 totalShares,
        uint256 sharePrice,
        uint256 fundingTarget,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 fundingDeadline,
        string metadataURI
    );
    event PropertyTermsUpdated(
        uint256 indexed propertyId,
        uint256 totalShares,
        uint256 sharePrice,
        uint256 fundingTarget,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 fundingDeadline,
        string metadataURI
    );
    event PropertyPauseUpdated(uint256 indexed propertyId, bool paused);
    event FundingStarted(uint256 indexed propertyId);
    event FundingCancelled(uint256 indexed propertyId);
    event FundingFinalized(uint256 indexed propertyId, uint256 principalAmount);
    event PropertyClosed(uint256 indexed propertyId);
    event Invested(uint256 indexed propertyId, address indexed investor, uint256 shares, uint256 amount);
    event Refunded(uint256 indexed propertyId, address indexed investor, uint256 amount);
    event RevenueDeposited(uint256 indexed propertyId, address indexed depositor, uint256 amount);
    event RevenueClaimed(uint256 indexed propertyId, address indexed investor, uint256 amount);

    constructor(address paymentToken_, address treasury_, string memory defaultURI, uint48 defaultAdminDelay)
        ERC1155(defaultURI)
        AccessControlDefaultAdminRules(defaultAdminDelay, msg.sender)
    {
        if (paymentToken_ == address(0) || treasury_ == address(0)) revert ZeroAddress();

        PAYMENT_TOKEN = IERC20(paymentToken_);
        treasury = treasury_;

        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(COMPLIANCE_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, treasury_);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;
        if (oldTreasury != newTreasury && hasRole(TREASURY_ROLE, oldTreasury)) {
            _revokeRole(TREASURY_ROLE, oldTreasury);
        }
        _grantRole(TREASURY_ROLE, newTreasury);

        emit TreasuryUpdated(newTreasury);
    }

    function setWhitelist(address account, bool approved) external onlyRole(COMPLIANCE_ROLE) {
        if (account == address(0)) revert ZeroAddress();

        whitelisted[account] = approved;

        emit WhitelistUpdated(account, approved);
    }

    function createProperty(
        string calldata metadataURI,
        uint256 totalShares,
        uint256 sharePrice,
        uint256 fundingTarget,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 fundingDeadline
    ) external onlyRole(MANAGER_ROLE) returns (uint256 propertyId) {
        _validatePropertyTerms(totalShares, sharePrice, fundingTarget, minInvestment, maxInvestment, fundingDeadline);

        propertyId = nextPropertyId++;
        _properties[propertyId] = Property({
            totalShares: totalShares,
            sharePrice: sharePrice,
            fundingTarget: fundingTarget,
            minInvestment: minInvestment,
            maxInvestment: maxInvestment,
            fundingDeadline: fundingDeadline,
            soldShares: 0,
            raisedAmount: 0,
            revenueDeposited: 0,
            state: PropertyState.Draft,
            paused: false,
            metadataURI: metadataURI
        });

        emit PropertyCreated(
            propertyId,
            totalShares,
            sharePrice,
            fundingTarget,
            minInvestment,
            maxInvestment,
            fundingDeadline,
            metadataURI
        );
    }

    function setPropertyPaused(uint256 propertyId, bool paused) external onlyRole(MANAGER_ROLE) {
        Property storage property = _getExistingProperty(propertyId);
        property.paused = paused;

        emit PropertyPauseUpdated(propertyId, paused);
    }

    function updateDraftPropertyTerms(
        uint256 propertyId,
        string calldata metadataURI,
        uint256 totalShares,
        uint256 sharePrice,
        uint256 fundingTarget,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 fundingDeadline
    ) external onlyRole(MANAGER_ROLE) {
        Property storage property = _getExistingProperty(propertyId);
        if (property.state != PropertyState.Draft) revert InvalidState();

        _validatePropertyTerms(totalShares, sharePrice, fundingTarget, minInvestment, maxInvestment, fundingDeadline);

        property.totalShares = totalShares;
        property.sharePrice = sharePrice;
        property.fundingTarget = fundingTarget;
        property.minInvestment = minInvestment;
        property.maxInvestment = maxInvestment;
        property.fundingDeadline = fundingDeadline;
        property.metadataURI = metadataURI;

        emit PropertyTermsUpdated(
            propertyId,
            totalShares,
            sharePrice,
            fundingTarget,
            minInvestment,
            maxInvestment,
            fundingDeadline,
            metadataURI
        );
    }

    function startFunding(uint256 propertyId) external onlyRole(MANAGER_ROLE) {
        Property storage property = _getExistingProperty(propertyId);
        if (property.state != PropertyState.Draft) revert InvalidState();

        property.state = PropertyState.Funding;

        emit FundingStarted(propertyId);
    }

    function cancelFunding(uint256 propertyId) external onlyRole(MANAGER_ROLE) {
        Property storage property = _getExistingProperty(propertyId);
        if (property.state != PropertyState.Draft && property.state != PropertyState.Funding) revert InvalidState();

        property.state = PropertyState.Cancelled;

        emit FundingCancelled(propertyId);
    }

    function finalizeFunding(uint256 propertyId) external nonReentrant onlyRole(MANAGER_ROLE) {
        Property storage property = _getExistingProperty(propertyId);
        if (property.state != PropertyState.Funding) revert InvalidState();
        if (property.raisedAmount < property.fundingTarget) revert FundingNotComplete();

        uint256 principalAmount = property.raisedAmount;
        property.state = PropertyState.Funded;

        PAYMENT_TOKEN.safeTransfer(treasury, principalAmount);

        emit FundingFinalized(propertyId, principalAmount);
    }

    function closeProperty(uint256 propertyId) external onlyRole(MANAGER_ROLE) {
        Property storage property = _getExistingProperty(propertyId);
        if (property.state != PropertyState.Funded) revert InvalidState();

        property.state = PropertyState.Closed;

        emit PropertyClosed(propertyId);
    }

    function invest(uint256 propertyId, uint256 shares) external nonReentrant whenNotPaused {
        if (!whitelisted[msg.sender]) revert NotWhitelisted();
        if (shares == 0) revert InvalidAmount();

        Property storage property = _getExistingProperty(propertyId);
        if (property.paused) revert PropertyPaused();
        if (property.state != PropertyState.Funding) revert InvalidState();
        if (block.timestamp > property.fundingDeadline) revert FundingExpired();
        if (property.soldShares + shares > property.totalShares) revert SoldOut();

        uint256 cost = shares * property.sharePrice;
        if (cost < property.minInvestment) revert InvestmentBelowMinimum();

        uint256 newInvestedAmount = investedAmount[propertyId][msg.sender] + cost;
        if (newInvestedAmount > property.maxInvestment) revert InvestmentAboveMaximum();

        property.soldShares += shares;
        property.raisedAmount += cost;
        investedAmount[propertyId][msg.sender] = newInvestedAmount;

        PAYMENT_TOKEN.safeTransferFrom(msg.sender, address(this), cost);
        _mint(msg.sender, propertyId, shares, "");

        emit Invested(propertyId, msg.sender, shares, cost);
    }

    function refund(uint256 propertyId) external nonReentrant {
        Property storage property = _getExistingProperty(propertyId);
        if (property.state != PropertyState.Cancelled) revert RefundUnavailable();

        uint256 amount = investedAmount[propertyId][msg.sender];
        if (amount == 0) revert NothingToRefund();

        uint256 shares = balanceOf(msg.sender, propertyId);
        investedAmount[propertyId][msg.sender] = 0;

        if (shares != 0) {
            _burn(msg.sender, propertyId, shares);
        }

        PAYMENT_TOKEN.safeTransfer(msg.sender, amount);

        emit Refunded(propertyId, msg.sender, amount);
    }

    function depositRevenue(uint256 propertyId, uint256 amount) external nonReentrant whenNotPaused {
        if (!hasRole(TREASURY_ROLE, msg.sender) && !hasRole(MANAGER_ROLE, msg.sender)) {
            revert UnauthorizedDepositor();
        }
        if (amount == 0) revert InvalidAmount();

        Property storage property = _getExistingProperty(propertyId);
        if (property.paused) revert PropertyPaused();
        if (property.state != PropertyState.Funded && property.state != PropertyState.Closed) revert InvalidState();

        uint256 currentSupply = totalSupply(propertyId);
        if (currentSupply == 0) revert NoShares();

        // Cumulative reward-per-share avoids iterating over all investors when revenue arrives.
        property.revenueDeposited += amount;
        revenuePerShare[propertyId] += (amount * REWARD_PRECISION) / currentSupply;

        PAYMENT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);

        emit RevenueDeposited(propertyId, msg.sender, amount);
    }

    function claimRevenue(uint256 propertyId) external nonReentrant {
        if (!whitelisted[msg.sender]) revert NotWhitelisted();

        _getExistingProperty(propertyId);
        _settleRevenue(propertyId, msg.sender);

        uint256 amount = accruedRevenue[propertyId][msg.sender];
        if (amount == 0) revert NothingToClaim();

        accruedRevenue[propertyId][msg.sender] = 0;
        PAYMENT_TOKEN.safeTransfer(msg.sender, amount);

        emit RevenueClaimed(propertyId, msg.sender, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function getProperty(uint256 propertyId) external view returns (Property memory) {
        if (_properties[propertyId].totalShares == 0) revert InvalidProperty();
        return _properties[propertyId];
    }

    function pendingRevenue(uint256 propertyId, address account) public view returns (uint256) {
        uint256 pending =
            (balanceOf(account, propertyId) * (revenuePerShare[propertyId] - userRevenueDebt[propertyId][account]))
                / REWARD_PRECISION;
        return accruedRevenue[propertyId][account] + pending;
    }

    function uri(uint256 propertyId) public view override returns (string memory) {
        string memory propertyURI = _properties[propertyId].metadataURI;
        if (bytes(propertyURI).length != 0) {
            return propertyURI;
        }

        return super.uri(propertyId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControlDefaultAdminRules)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Supply)
    {
        // Settle revenue before balance changes so old and new holders receive the right split.
        if (from != address(0)) {
            _settleBatch(ids, from);
        }
        if (to != address(0) && to != from) {
            _settleBatch(ids, to);
        }

        if (from != address(0) && to != address(0)) {
            if (paused()) revert EnforcedPause();
            if (!whitelisted[from] || !whitelisted[to]) revert NotWhitelisted();

            // RWA shares are only transferable after funding has been finalized.
            for (uint256 i = 0; i < ids.length; i++) {
                Property storage property = _properties[ids[i]];
                if (property.paused) revert PropertyPaused();

                PropertyState state = property.state;
                if (state != PropertyState.Funded && state != PropertyState.Closed) revert InvalidState();
            }
        }

        super._update(from, to, ids, values);

        if (from != address(0)) {
            _syncBatchDebt(ids, from);
        }
        if (to != address(0) && to != from) {
            _syncBatchDebt(ids, to);
        }
    }

    function _settleBatch(uint256[] memory ids, address account) internal {
        for (uint256 i = 0; i < ids.length; i++) {
            _settleRevenue(ids[i], account);
        }
    }

    function _syncBatchDebt(uint256[] memory ids, address account) internal {
        for (uint256 i = 0; i < ids.length; i++) {
            userRevenueDebt[ids[i]][account] = revenuePerShare[ids[i]];
        }
    }

    function _settleRevenue(uint256 propertyId, address account) internal {
        uint256 currentDebt = userRevenueDebt[propertyId][account];
        uint256 currentRevenuePerShare = revenuePerShare[propertyId];

        if (currentRevenuePerShare == currentDebt) {
            return;
        }

        uint256 pending = (balanceOf(account, propertyId) * (currentRevenuePerShare - currentDebt)) / REWARD_PRECISION;
        if (pending != 0) {
            accruedRevenue[propertyId][account] += pending;
        }

        userRevenueDebt[propertyId][account] = currentRevenuePerShare;
    }

    function _getExistingProperty(uint256 propertyId) internal view returns (Property storage property) {
        property = _properties[propertyId];
        if (property.totalShares == 0) revert InvalidProperty();
    }

    function _validatePropertyTerms(
        uint256 totalShares,
        uint256 sharePrice,
        uint256 fundingTarget,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 fundingDeadline
    ) internal view {
        if (totalShares == 0) revert InvalidSupply();
        if (sharePrice == 0) revert InvalidPrice();
        if (fundingTarget == 0 || fundingTarget > totalShares * sharePrice) revert InvalidFundingTarget();
        if (minInvestment == 0 || maxInvestment < minInvestment) revert InvalidInvestmentLimits();
        if (fundingDeadline <= block.timestamp) revert InvalidDeadline();
    }
}
