// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {PaymentRequestHub} from "../src/PaymentRequestHub.sol";

contract DeployHub is Script {
    function run() external returns (PaymentRequestHub hub) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        hub = new PaymentRequestHub();
        vm.stopBroadcast();

        console.log("PaymentRequestHub deployed at:", address(hub));
    }
}
