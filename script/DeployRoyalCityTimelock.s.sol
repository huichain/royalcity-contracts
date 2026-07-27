// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployRoyalCityTimelock is Script {
    function run() external returns (TimelockController timelock) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 minDelay = vm.envUint("TIMELOCK_DELAY");
        address proposerSafe = vm.envAddress("TIMELOCK_PROPOSER_SAFE");
        address executor = vm.envOr("TIMELOCK_EXECUTOR", address(0));
        address temporaryAdmin = vm.envOr("TIMELOCK_TEMP_ADMIN", address(0));

        address[] memory proposers = new address[](1);
        proposers[0] = proposerSafe;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        vm.startBroadcast(deployerPrivateKey);
        timelock = new TimelockController(minDelay, proposers, executors, temporaryAdmin);
        vm.stopBroadcast();
    }
}
