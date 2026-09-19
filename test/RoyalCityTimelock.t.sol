// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract RoyalCityTimelockTest is Test {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant TIMELOCK_DELAY = 2 days;
    uint48 internal constant DEFAULT_ADMIN_DELAY = 2 days;

    MockUSDC internal usdc;
    RoyalCityRealEstate internal realEstate;
    TimelockController internal timelock;

    address internal treasury = address(0xA11CE);
    address internal compliance = address(0xC0FFEE);
    address internal safeProposer = address(0x515AFE);
    address internal anyoneExecutor = address(0xE0E);
    address internal investor = address(0xB0B);
    address internal outsider = address(0xBAD);

    function setUp() public {
        usdc = new MockUSDC();
        realEstate = new RoyalCityRealEstate(address(usdc), treasury, "ipfs://royalcity/{id}.json", DEFAULT_ADMIN_DELAY);

        address[] memory proposers = new address[](1);
        proposers[0] = safeProposer;

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(this));

        realEstate.grantRole(realEstate.MANAGER_ROLE(), address(timelock));
        realEstate.revokeRole(realEstate.MANAGER_ROLE(), address(this));

        usdc.mint(investor, 10_000 * USDC);
        usdc.mint(treasury, 10_000 * USDC);

        vm.prank(investor);
        usdc.approve(address(realEstate), type(uint256).max);

        vm.prank(treasury);
        usdc.approve(address(realEstate), type(uint256).max);
    }

    function test_SafeCannotBypassTimelockManagerRole() public {
        vm.prank(safeProposer);
        vm.expectRevert();
        realEstate.createProperty(
            "ipfs://timelocked-property", 100, 10 * USDC, 1_000 * USDC, 10 * USDC, 1_000 * USDC, block.timestamp + 30 days
        );
    }

    function test_DeployerWithoutManagerCannotCreate() public {
        vm.expectRevert();
        realEstate.createProperty(
            "ipfs://deployer-blocked", 100, 10 * USDC, 1_000 * USDC, 10 * USDC, 1_000 * USDC, block.timestamp + 30 days
        );
    }

    function test_NonProposerCannotSchedule() public {
        bytes memory payload = abi.encodeCall(RoyalCityRealEstate.pause, ());
        bytes32 salt = keccak256("NON_PROPOSER");

        vm.prank(outsider);
        vm.expectRevert();
        timelock.schedule(address(realEstate), 0, payload, bytes32(0), salt, TIMELOCK_DELAY);
    }

    function test_TimelockExecutesManagerOperationAfterDelay() public {
        bytes memory createPropertyCall = _createPropertyCall("ipfs://timelocked-property");
        bytes32 salt = keccak256("ROYALCITY_CREATE_PROPERTY");

        _schedule(createPropertyCall, salt);

        vm.prank(anyoneExecutor);
        vm.expectRevert();
        timelock.execute(address(realEstate), 0, createPropertyCall, bytes32(0), salt);

        _executeAfterDelay(createPropertyCall, salt);

        RoyalCityRealEstate.Property memory property = realEstate.getProperty(1);
        assertEq(property.metadataURI, "ipfs://timelocked-property");
        assertEq(property.totalShares, 100);
        assertEq(realEstate.nextPropertyId(), 2);
    }

    function test_GovernanceHandoffAndFundingLifecycleViaTimelock() public {
        // Compliance / treasury roles on dedicated addresses (treasury already has TREASURY_ROLE).
        realEstate.grantRole(realEstate.COMPLIANCE_ROLE(), compliance);
        realEstate.revokeRole(realEstate.COMPLIANCE_ROLE(), address(this));

        assertTrue(realEstate.hasRole(realEstate.MANAGER_ROLE(), address(timelock)));
        assertFalse(realEstate.hasRole(realEstate.MANAGER_ROLE(), address(this)));
        assertTrue(realEstate.hasRole(realEstate.COMPLIANCE_ROLE(), compliance));
        assertTrue(realEstate.hasRole(realEstate.TREASURY_ROLE(), treasury));

        // Default admin → Timelock (RoyalCity delay + Timelock delay).
        realEstate.beginDefaultAdminTransfer(address(timelock));

        bytes memory acceptCall = abi.encodeWithSignature("acceptDefaultAdminTransfer()");
        bytes32 acceptSalt = keccak256("ROYALCITY_ACCEPT_DEFAULT_ADMIN");
        _schedule(acceptCall, acceptSalt);

        vm.warp(block.timestamp + DEFAULT_ADMIN_DELAY + 1);
        _executeAfterDelay(acceptCall, acceptSalt);

        assertEq(realEstate.defaultAdmin(), address(timelock));
        assertTrue(realEstate.hasRole(realEstate.DEFAULT_ADMIN_ROLE(), address(timelock)));
        assertFalse(realEstate.hasRole(realEstate.DEFAULT_ADMIN_ROLE(), address(this)));

        // create → startFunding via Timelock
        bytes memory createCall = _createPropertyCall("ipfs://gov-property");
        bytes32 createSalt = keccak256("ROYALCITY_CREATE_GOV");
        _scheduleAndExecute(createCall, createSalt);

        uint256 propertyId = 1;
        bytes memory startCall = abi.encodeCall(RoyalCityRealEstate.startFunding, (propertyId));
        _scheduleAndExecute(startCall, keccak256("ROYALCITY_START_FUNDING"));

        assertEq(uint8(realEstate.getProperty(propertyId).state), uint8(RoyalCityRealEstate.PropertyState.Funding));

        // Compliance whitelists; investor funds the round to target.
        vm.prank(compliance);
        realEstate.setWhitelist(investor, true);

        vm.prank(investor);
        realEstate.invest(propertyId, 100);

        bytes memory finalizeCall = abi.encodeCall(RoyalCityRealEstate.finalizeFunding, (propertyId));
        _scheduleAndExecute(finalizeCall, keccak256("ROYALCITY_FINALIZE"));

        assertEq(uint8(realEstate.getProperty(propertyId).state), uint8(RoyalCityRealEstate.PropertyState.Funded));
        assertEq(usdc.balanceOf(treasury), 10_000 * USDC + 1_000 * USDC);

        // Property pause is manager-gated through Timelock.
        bytes memory pausePropertyCall = abi.encodeCall(RoyalCityRealEstate.setPropertyPaused, (propertyId, true));
        _scheduleAndExecute(pausePropertyCall, keccak256("ROYALCITY_PROPERTY_PAUSE"));
        assertTrue(realEstate.getProperty(propertyId).paused);

        // Global pause/unpause requires default admin = Timelock.
        bytes memory pauseCall = abi.encodeCall(RoyalCityRealEstate.pause, ());
        _scheduleAndExecute(pauseCall, keccak256("ROYALCITY_GLOBAL_PAUSE"));
        assertTrue(realEstate.paused());

        bytes memory unpauseCall = abi.encodeCall(RoyalCityRealEstate.unpause, ());
        _scheduleAndExecute(unpauseCall, keccak256("ROYALCITY_GLOBAL_UNPAUSE"));
        assertFalse(realEstate.paused());
    }

    function test_FormerAdminCannotPauseAfterTimelockAccepts() public {
        realEstate.beginDefaultAdminTransfer(address(timelock));

        bytes memory acceptCall = abi.encodeWithSignature("acceptDefaultAdminTransfer()");
        bytes32 acceptSalt = keccak256("ROYALCITY_ACCEPT_ADMIN_ONLY");
        _schedule(acceptCall, acceptSalt);
        vm.warp(block.timestamp + DEFAULT_ADMIN_DELAY + 1);
        _executeAfterDelay(acceptCall, acceptSalt);

        vm.expectRevert();
        realEstate.pause();
    }

    function _createPropertyCall(string memory uri) internal view returns (bytes memory) {
        return abi.encodeCall(
            RoyalCityRealEstate.createProperty,
            (uri, 100, 10 * USDC, 1_000 * USDC, 10 * USDC, 1_000 * USDC, block.timestamp + 30 days)
        );
    }

    function _schedule(bytes memory payload, bytes32 salt) internal {
        vm.prank(safeProposer);
        timelock.schedule(address(realEstate), 0, payload, bytes32(0), salt, TIMELOCK_DELAY);
    }

    function _executeAfterDelay(bytes memory payload, bytes32 salt) internal {
        bytes32 id = timelock.hashOperation(address(realEstate), 0, payload, bytes32(0), salt);
        uint256 readyAt = timelock.getTimestamp(id);
        if (readyAt == 0 || readyAt == 1) {
            revert("operation not scheduled");
        }
        if (block.timestamp < readyAt) {
            vm.warp(readyAt + 1);
        }

        vm.prank(anyoneExecutor);
        timelock.execute(address(realEstate), 0, payload, bytes32(0), salt);
    }

    function _scheduleAndExecute(bytes memory payload, bytes32 salt) internal {
        _schedule(payload, salt);
        _executeAfterDelay(payload, salt);
    }
}
