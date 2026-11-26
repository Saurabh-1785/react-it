// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {FloatCallbackReceiver} from "../src/FloatCallbackReceiver.sol";
import {ZeroFloatFactory} from "../src/ZeroFloatFactory.sol";
import {MockUSD} from "../src/mocks/MockUSD.sol";

contract DeployBlock3And4 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address callbackProxy = vm.envOr(
            "CALLBACK_PROXY",
            address(0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6)
        );
        address rvmId = vm.envOr("RVM_ID", address(0));
        address hubAddress = vm.envAddress("HUB_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy FloatCallbackReceiver
        FloatCallbackReceiver receiver = new FloatCallbackReceiver(
            callbackProxy,
            rvmId,
            address(0),
            hubAddress
        );
        console.log("FloatCallbackReceiver deployed at:", address(receiver));

        // 2. Deploy MockUSD
        MockUSD musd = new MockUSD();
        console.log("MockUSD deployed at:", address(musd));

        // 3. Deploy ZeroFloatFactory (FloatPool address can be wired in Block 5)
        ZeroFloatFactory factory = new ZeroFloatFactory(
            address(0),
            hubAddress,
            address(musd)
        );
        console.log("ZeroFloatFactory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
