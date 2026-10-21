// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";

contract ExecuteBurntatoBuyback is Script {
    error InvalidDiamond(address diamond);
    error InvalidPrivateKey();
    error MarketDependenciesUnavailable();
    error ProtocolPaused();
    error EmptyBuybackReserve();

    function run() external returns (uint256 staticsAcquired, uint256 reserveAfter) {
        address diamond = vm.envAddress("BURNTATO_DIAMOND");
        checkExecutionState(diamond);
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (privateKey == 0) revert InvalidPrivateKey();

        IBuyback buybacks = IBuyback(diamond);

        vm.startBroadcast(privateKey);
        staticsAcquired = buybacks.buyback();
        vm.stopBroadcast();

        reserveAfter = buybacks.buybackReserveEth();
        console2.log("Buyback STATICS acquired and POTATO reserve funded", staticsAcquired);
        console2.log("Buyback reserve after execution", reserveAfter);
    }

    function checkExecutionState(address diamond) public view {
        if (diamond == address(0) || diamond.code.length == 0) revert InvalidDiamond(diamond);

        (address manager, address weth,) = IBuyback(diamond).buybackMarket();
        if (manager.code.length == 0 || weth.code.length == 0) revert MarketDependenciesUnavailable();
        if (IGovernance(diamond).paused()) revert ProtocolPaused();
        if (IBuyback(diamond).buybackReserveEth() == 0) revert EmptyBuybackReserve();
    }
}
