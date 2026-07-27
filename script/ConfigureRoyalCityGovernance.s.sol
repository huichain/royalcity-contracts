// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";

contract ConfigureRoyalCityGovernance is Script {
    function run() external {
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        RoyalCityRealEstate realEstate = RoyalCityRealEstate(vm.envAddress("ROYALCITY_CONTRACT"));
        address timelock = vm.envAddress("TIMELOCK");
        address complianceSafe = vm.envAddress("COMPLIANCE_SAFE");
        address treasurySafe = vm.envAddress("TREASURY_SAFE");
        address defaultAdminTarget = vm.envOr("DEFAULT_ADMIN_TARGET", timelock);
        bool revokeDeployerManager = vm.envOr("REVOKE_DEPLOYER_MANAGER", false);
        bool revokeDeployerCompliance = vm.envOr("REVOKE_DEPLOYER_COMPLIANCE", false);

        address deployer = vm.addr(adminPrivateKey);

        vm.startBroadcast(adminPrivateKey);

        realEstate.grantRole(realEstate.MANAGER_ROLE(), timelock);
        realEstate.grantRole(realEstate.COMPLIANCE_ROLE(), complianceSafe);
        realEstate.grantRole(realEstate.TREASURY_ROLE(), treasurySafe);
        realEstate.beginDefaultAdminTransfer(defaultAdminTarget);

        if (revokeDeployerManager) {
            realEstate.revokeRole(realEstate.MANAGER_ROLE(), deployer);
        }

        if (revokeDeployerCompliance) {
            realEstate.revokeRole(realEstate.COMPLIANCE_ROLE(), deployer);
        }

        vm.stopBroadcast();
    }
}
