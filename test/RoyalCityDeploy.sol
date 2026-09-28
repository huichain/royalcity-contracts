// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {RoyalCityRealEstate} from "../src/RoyalCityRealEstate.sol";

library RoyalCityDeploy {
    function deploy(address paymentToken, address treasury, string memory uri_, uint48 defaultAdminDelay)
        internal
        returns (RoyalCityRealEstate)
    {
        RoyalCityRealEstate implementation = new RoyalCityRealEstate();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(RoyalCityRealEstate.initialize, (paymentToken, treasury, uri_, defaultAdminDelay))
        );
        return RoyalCityRealEstate(address(proxy));
    }
}
