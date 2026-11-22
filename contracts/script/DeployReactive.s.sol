// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ZeroFloatReactive} from "../src/ZeroFloatReactive.sol";

contract DeployReactive is Script {
    function run() external returns (ZeroFloatReactive reactive) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 baseChainId = vm.envOr("BASE_CHAIN_ID", uint256(84532));
        address hubAddress = vm.envAddress("HUB_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);
        reactive = new ZeroFloatReactive(baseChainId, hubAddress);
        vm.stopBroadcast();

        console.log("ZeroFloatReactive deployed at:", address(reactive));
    }
}
