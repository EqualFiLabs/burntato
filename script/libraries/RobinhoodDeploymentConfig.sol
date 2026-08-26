// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IStateView} from "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";

import {CanonicalV4Dependencies} from "../DeploymentTypes.sol";

interface IPositionManagerBindings {
    function poolManager() external view returns (address);
    function permit2() external view returns (address);
    function tokenDescriptor() external view returns (address);
    function WETH9() external view returns (address);
}

interface IUniversalRouterBinding {
    function poolManager() external view returns (address);
}

library RobinhoodDeploymentConfig {
    error InvalidCanonicalChain(uint256 expected, uint256 actual);
    error InvalidCanonicalBlock(uint256 expectedMinimum, uint256 actual);
    error InvalidCanonicalBlockHash(bytes32 expected, bytes32 actual);
    error InvalidCanonicalDependency(address dependency);
    error InvalidCanonicalCodeHash(address dependency, bytes32 expected, bytes32 actual);
    error InvalidCanonicalBinding(bytes32 binding, address expected, address actual);

    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    string internal constant MANIFEST_PATH = "deployments/robinhood-chain-4663.json";

    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function load() internal view returns (CanonicalV4Dependencies memory dependencies) {
        string memory manifest = vm.readFile(MANIFEST_PATH);
        dependencies.chainId = vm.parseJsonUint(manifest, ".chainId");
        dependencies.forkBlock = vm.parseJsonUint(manifest, ".forkBlock");
        dependencies.forkBlockHash = vm.parseJsonBytes32(manifest, ".forkBlockHash");
        dependencies.poolManager = vm.parseJsonAddress(manifest, ".contracts.poolManager.address");
        dependencies.poolManagerCodeHash = vm.parseJsonBytes32(manifest, ".contracts.poolManager.runtimeCodeHash");
        dependencies.positionDescriptor = vm.parseJsonAddress(manifest, ".contracts.positionDescriptor.address");
        dependencies.positionDescriptorCodeHash =
            vm.parseJsonBytes32(manifest, ".contracts.positionDescriptor.runtimeCodeHash");
        dependencies.positionManager = vm.parseJsonAddress(manifest, ".contracts.positionManager.address");
        dependencies.positionManagerCodeHash =
            vm.parseJsonBytes32(manifest, ".contracts.positionManager.runtimeCodeHash");
        dependencies.quoter = vm.parseJsonAddress(manifest, ".contracts.quoter.address");
        dependencies.quoterCodeHash = vm.parseJsonBytes32(manifest, ".contracts.quoter.runtimeCodeHash");
        dependencies.stateView = vm.parseJsonAddress(manifest, ".contracts.stateView.address");
        dependencies.stateViewCodeHash = vm.parseJsonBytes32(manifest, ".contracts.stateView.runtimeCodeHash");
        dependencies.reservesLens = vm.parseJsonAddress(manifest, ".contracts.reservesLens.address");
        dependencies.reservesLensCodeHash = vm.parseJsonBytes32(manifest, ".contracts.reservesLens.runtimeCodeHash");
        dependencies.universalRouter = vm.parseJsonAddress(manifest, ".contracts.universalRouter.address");
        dependencies.universalRouterCodeHash =
            vm.parseJsonBytes32(manifest, ".contracts.universalRouter.runtimeCodeHash");
        dependencies.permit2 = vm.parseJsonAddress(manifest, ".contracts.permit2.address");
        dependencies.permit2CodeHash = vm.parseJsonBytes32(manifest, ".contracts.permit2.runtimeCodeHash");
        dependencies.weth = vm.parseJsonAddress(manifest, ".contracts.weth.address");
        dependencies.wethCodeHash = vm.parseJsonBytes32(manifest, ".contracts.weth.runtimeCodeHash");
    }

    function validate(CanonicalV4Dependencies memory dependencies) internal view {
        if (block.chainid != dependencies.chainId || dependencies.chainId != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert InvalidCanonicalChain(dependencies.chainId, block.chainid);
        }
        if (block.number < dependencies.forkBlock) revert InvalidCanonicalBlock(dependencies.forkBlock, block.number);
        uint256 blockDistance = block.number - dependencies.forkBlock;
        if (blockDistance > 0 && blockDistance <= 256) {
            bytes32 actualBlockHash = blockhash(dependencies.forkBlock);
            if (actualBlockHash != dependencies.forkBlockHash) {
                revert InvalidCanonicalBlockHash(dependencies.forkBlockHash, actualBlockHash);
            }
        }

        _validateCode(dependencies.poolManager, dependencies.poolManagerCodeHash);
        _validateCode(dependencies.positionDescriptor, dependencies.positionDescriptorCodeHash);
        _validateCode(dependencies.positionManager, dependencies.positionManagerCodeHash);
        _validateCode(dependencies.quoter, dependencies.quoterCodeHash);
        _validateCode(dependencies.stateView, dependencies.stateViewCodeHash);
        _validateCode(dependencies.reservesLens, dependencies.reservesLensCodeHash);
        _validateCode(dependencies.universalRouter, dependencies.universalRouterCodeHash);
        _validateCode(dependencies.permit2, dependencies.permit2CodeHash);
        _validateCode(dependencies.weth, dependencies.wethCodeHash);

        IPositionManagerBindings positionManager = IPositionManagerBindings(dependencies.positionManager);
        _validateBinding("PM_POOL", dependencies.poolManager, positionManager.poolManager());
        _validateBinding("PM_PERMIT2", dependencies.permit2, positionManager.permit2());
        _validateBinding("PM_DESCRIPTOR", dependencies.positionDescriptor, positionManager.tokenDescriptor());
        _validateBinding("PM_WETH", dependencies.weth, positionManager.WETH9());
        _validateBinding(
            "DESCRIPTOR_POOL",
            dependencies.poolManager,
            address(IPositionDescriptor(dependencies.positionDescriptor).poolManager())
        );
        _validateBinding(
            "DESCRIPTOR_WETH", dependencies.weth, IPositionDescriptor(dependencies.positionDescriptor).wrappedNative()
        );
        _validateBinding("QUOTER_POOL", dependencies.poolManager, address(IV4Quoter(dependencies.quoter).poolManager()));
        _validateBinding(
            "STATE_VIEW_POOL", dependencies.poolManager, address(IStateView(dependencies.stateView).poolManager())
        );
        _validateBinding(
            "ROUTER_POOL", dependencies.poolManager, IUniversalRouterBinding(dependencies.universalRouter).poolManager()
        );
    }

    function _validateCode(address dependency, bytes32 expectedCodeHash) private view {
        if (dependency.code.length == 0) revert InvalidCanonicalDependency(dependency);
        bytes32 actualCodeHash = dependency.codehash;
        if (actualCodeHash != expectedCodeHash) {
            revert InvalidCanonicalCodeHash(dependency, expectedCodeHash, actualCodeHash);
        }
    }

    function _validateBinding(bytes32 binding, address expected, address actual) private pure {
        if (actual != expected) revert InvalidCanonicalBinding(binding, expected, actual);
    }
}
