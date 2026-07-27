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
    address internal safeProposer = address(0x515AFE);
    address internal anyoneExecutor = address(0xE0E);

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
    }

    function test_SafeCannotBypassTimelockManagerRole() public {
        vm.prank(safeProposer);
        vm.expectRevert();
        realEstate.createProperty(
            "ipfs://timelocked-property", 100, 10 * USDC, 1_000 * USDC, 10 * USDC, 700 * USDC, block.timestamp + 30 days
        );
    }

    function test_TimelockExecutesManagerOperationAfterDelay() public {
        bytes memory createPropertyCall = abi.encodeCall(
            RoyalCityRealEstate.createProperty,
            (
                "ipfs://timelocked-property",
                100,
                10 * USDC,
                1_000 * USDC,
                10 * USDC,
                700 * USDC,
                block.timestamp + 30 days
            )
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("ROYALCITY_CREATE_PROPERTY");

        vm.prank(safeProposer);
        timelock.schedule(address(realEstate), 0, createPropertyCall, predecessor, salt, TIMELOCK_DELAY);

        vm.prank(anyoneExecutor);
        vm.expectRevert();
        timelock.execute(address(realEstate), 0, createPropertyCall, predecessor, salt);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        vm.prank(anyoneExecutor);
        timelock.execute(address(realEstate), 0, createPropertyCall, predecessor, salt);

        RoyalCityRealEstate.Property memory property = realEstate.getProperty(1);
        assertEq(property.metadataURI, "ipfs://timelocked-property");
        assertEq(property.totalShares, 100);
        assertEq(realEstate.nextPropertyId(), 2);
    }
}
