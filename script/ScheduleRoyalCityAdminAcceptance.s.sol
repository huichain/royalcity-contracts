// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

interface IDefaultAdminAcceptor {
    function acceptDefaultAdminTransfer() external;
}

contract ScheduleRoyalCityAdminAcceptance is Script {
    function run() external returns (bytes32 operationId) {
        uint256 proposerPrivateKey = vm.envUint("PRIVATE_KEY");
        TimelockController timelock = TimelockController(payable(vm.envAddress("TIMELOCK")));
        address realEstate = vm.envAddress("ROYALCITY_CONTRACT");
        uint256 delay = vm.envUint("TIMELOCK_DELAY");
        bytes32 salt = vm.envOr("TIMELOCK_SALT", keccak256("ROYALCITY_ACCEPT_DEFAULT_ADMIN"));

        bytes memory payload = abi.encodeCall(IDefaultAdminAcceptor.acceptDefaultAdminTransfer, ());
        bytes32 predecessor = bytes32(0);

        vm.startBroadcast(proposerPrivateKey);
        timelock.schedule(realEstate, 0, payload, predecessor, salt, delay);
        vm.stopBroadcast();

        operationId = timelock.hashOperation(realEstate, 0, payload, predecessor, salt);
    }
}
