// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";

contract FinalizeBurntatoRobinhoodTestnet is Script {
    uint256 private constant CHAIN_ID = 46_630;
    string private constant OUTPUT_PATH = "artifacts/robinhood-testnet/deployment.json";

    error InvalidTestnetChain(uint256 actualChainId);
    error PurchasesNotInitialized();
    error ProtocolPaused();
    error MarketNotLaunched();
    error ExternalBuysNotEnabled();

    function initializePurchases() external {
        _requireChain();
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        IGovernance(_diamond()).initializePurchases();
        vm.stopBroadcast();
    }

    function launchMarket() external {
        _requireChain();
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        (bytes32 poolId, uint256 positionCount, uint256 potatoUsed) = IMarket(_diamond()).launchMarket();
        vm.stopBroadcast();
        console2.logBytes32(poolId);
        console2.log("Locked market positions", positionCount);
        console2.log("POTATO used", potatoUsed);
    }

    function enableExternalBuys() external {
        _requireChain();
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        BurntatoSwapFeeHook(payable(_hook())).setExternalBuysEnabled(true);
        vm.stopBroadcast();
    }

    function checkFinalized() external view returns (bool) {
        _requireChain();
        return checkFinalizedDeployment(_diamond(), _hook());
    }

    function checkFinalizedDeployment(address diamond, address hook) public view returns (bool) {
        IGovernance governance = IGovernance(diamond);
        if (!governance.purchasesInitialized()) revert PurchasesNotInitialized();
        if (governance.paused()) revert ProtocolPaused();
        (,, bool launching, bool launched) = IMarket(diamond).marketState();
        if (launching || !launched) revert MarketNotLaunched();
        if (!BurntatoSwapFeeHook(payable(hook)).externalBuysEnabled()) revert ExternalBuysNotEnabled();
        return true;
    }

    function _diamond() private view returns (address) {
        return vm.parseJsonAddress(vm.readFile(OUTPUT_PATH), ".diamond");
    }

    function _hook() private view returns (address) {
        return vm.parseJsonAddress(vm.readFile(OUTPUT_PATH), ".hook");
    }

    function _requireChain() private view {
        if (block.chainid != CHAIN_ID) revert InvalidTestnetChain(block.chainid);
    }
}
