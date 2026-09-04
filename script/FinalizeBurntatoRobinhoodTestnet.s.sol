// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";

contract FinalizeBurntatoRobinhoodTestnet is Script {
    uint256 private constant CHAIN_ID = 46_630;
    bytes32 private constant PREDECESSOR = bytes32(0);
    bytes32 private constant EXTERNAL_BUYS_SALT = keccak256("burntato.robinhood-testnet.external-buys.v1");
    string private constant OUTPUT_PATH = "artifacts/robinhood-testnet/deployment.json";

    error InvalidTestnetChain(uint256 actualChainId);
    error MarketNotLaunched();
    error ExternalBuysNotEnabled();

    function launchMarket() external {
        _requireChain();
        (address diamond,) = _addresses();
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        (bytes32 poolId, uint128 liquidity) = IMarket(diamond).launchMarket();
        vm.stopBroadcast();
        console2.logBytes32(poolId);
        console2.log("Locked market liquidity", liquidity);
    }

    function scheduleExternalBuys() external {
        _requireChain();
        (, address timelock) = _addresses();
        address hook = _hook();
        bytes memory data = abi.encodeCall(BurntatoSwapFeeHook.setExternalBuysEnabled, (true));
        TimelockController controller = TimelockController(payable(timelock));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        controller.schedule(hook, 0, data, PREDECESSOR, EXTERNAL_BUYS_SALT, controller.getMinDelay());
        vm.stopBroadcast();
        console2.log("External buys ready at", controller.getTimestamp(operationId()));
    }

    function executeExternalBuys() external {
        _requireChain();
        (, address timelock) = _addresses();
        address hook = _hook();
        bytes memory data = abi.encodeCall(BurntatoSwapFeeHook.setExternalBuysEnabled, (true));
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);
        TimelockController(payable(timelock)).execute(hook, 0, data, PREDECESSOR, EXTERNAL_BUYS_SALT);
        vm.stopBroadcast();
    }

    function checkFinalized() external view returns (bool) {
        _requireChain();
        (address diamond,) = _addresses();
        (,, bool launching, bool launched) = IMarket(diamond).marketState();
        if (launching || !launched) revert MarketNotLaunched();
        if (!BurntatoSwapFeeHook(payable(_hook())).externalBuysEnabled()) revert ExternalBuysNotEnabled();
        return true;
    }

    function operationId() public view returns (bytes32) {
        (, address timelock) = _addresses();
        bytes memory data = abi.encodeCall(BurntatoSwapFeeHook.setExternalBuysEnabled, (true));
        return TimelockController(payable(timelock)).hashOperation(_hook(), 0, data, PREDECESSOR, EXTERNAL_BUYS_SALT);
    }

    function _addresses() private view returns (address diamond, address timelock) {
        string memory json = vm.readFile(OUTPUT_PATH);
        diamond = vm.parseJsonAddress(json, ".diamond");
        timelock = vm.parseJsonAddress(json, ".timelock");
    }

    function _hook() private view returns (address) {
        return vm.parseJsonAddress(vm.readFile(OUTPUT_PATH), ".hook");
    }

    function _requireChain() private view {
        if (block.chainid != CHAIN_ID) revert InvalidTestnetChain(block.chainid);
    }
}
