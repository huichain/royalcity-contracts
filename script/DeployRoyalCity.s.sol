// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";

contract DeployRoyalCity is Script {
    function run() external returns (RoyalCityRealEstate realEstate) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address paymentToken = vm.envAddress("PAYMENT_TOKEN");
        address treasury = vm.envAddress("TREASURY");
        string memory baseURI = vm.envOr("BASE_URI", string("ipfs://royalcity/{id}.json"));
        uint48 defaultAdminDelay = uint48(vm.envOr("DEFAULT_ADMIN_DELAY", uint256(2 days)));

        vm.startBroadcast(deployerPrivateKey);
        realEstate = new RoyalCityRealEstate(paymentToken, treasury, baseURI, defaultAdminDelay);
        vm.stopBroadcast();
    }
}
