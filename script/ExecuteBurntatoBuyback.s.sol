// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";

contract ExecuteBurntatoBuyback is Script {
    error InvalidDiamond(address diamond);
    error InvalidPrivateKey();
    error MarketNotLaunched();
    error ProtocolPaused();
    error EmptyBuybackReserve();

    function run() external returns (uint256 potatoBought, uint256 reserveAfter) {
        address diamond = vm.envAddress("BURNTATO_DIAMOND");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (privateKey == 0) revert InvalidPrivateKey();

        checkExecutionState(diamond);
        IBuyback buybacks = IBuyback(diamond);

        vm.startBroadcast(privateKey);
        potatoBought = buybacks.buyback();
        vm.stopBroadcast();

        reserveAfter = buybacks.buybackReserveEth();
        console2.log("Buyback POTATO output", potatoBought);
        console2.log("Buyback reserve after execution", reserveAfter);
    }

    function checkExecutionState(address diamond) public view {
        if (diamond == address(0) || diamond.code.length == 0) revert InvalidDiamond(diamond);

        (,, bool launching, bool launched) = IMarket(diamond).marketState();
        if (launching || !launched) revert MarketNotLaunched();
        if (IGovernance(diamond).paused()) revert ProtocolPaused();
        if (IBuyback(diamond).buybackReserveEth() == 0) revert EmptyBuybackReserve();
    }
}
