// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {FloatPool} from "../src/FloatPool.sol";
import {FloatCallbackReceiver} from "../src/FloatCallbackReceiver.sol";

contract DeployBlock5And6 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenAddress = vm.envAddress("MUSD_ADDRESS");
        address receiverAddress = vm.envAddress("RECEIVER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy FloatPool
        FloatPool pool = new FloatPool(tokenAddress, receiverAddress);
        console.log("FloatPool deployed at:", address(pool));

        // 2. Link FloatPool on Receiver
        FloatCallbackReceiver(receiverAddress).setFloatPool(address(pool));
        console.log("Receiver wired to FloatPool");

        vm.stopBroadcast();
    }
}
