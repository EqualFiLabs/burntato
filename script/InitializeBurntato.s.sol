// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IGovernance} from "../src/interfaces/IGovernance.sol";

contract InitializeBurntato is Script {
    function run() external returns (bool initialized) {
        address diamond = vm.envAddress("BURNTATO_DIAMOND");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        IGovernance(diamond).initializePurchases();
        vm.stopBroadcast();

        initialized = IGovernance(diamond).purchasesInitialized();
        console2.log("Burntato purchases initialized", initialized);
    }
}
