// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";

import {IGenesisActivationRegistryView, IStaticsOperators} from "../../src/interfaces/IOperatorRewards.sol";
import {StaticsOperatorDependencies} from "../DeploymentTypes.sol";

library StaticsOperatorDeploymentConfig {
    error InvalidStaticsChain(uint256 expected, uint256 actual);
    error InvalidStaticsBlock(uint256 expectedMinimum, uint256 actual);
    error InvalidStaticsBlockHash(bytes32 expected, bytes32 actual);
    error InvalidStaticsDependency(address dependency);
    error InvalidStaticsCodeHash(address dependency, bytes32 expected, bytes32 actual);
    error InvalidStaticsBinding(bytes32 binding, address expected, address actual);
    error InvalidStaticsManifest();
    error StaticsLaunchNotFinalized();

    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    string internal constant MANIFEST_PATH = "deployments/statics-operators-robinhood-4663.json";

    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function load() internal view returns (StaticsOperatorDependencies memory dependencies) {
        string memory manifest = vm.readFile(MANIFEST_PATH);
        dependencies.chainId = vm.parseJsonUint(manifest, ".chainId");
        dependencies.finalizedBlock = vm.parseJsonUint(manifest, ".finalizedBlock");
        dependencies.finalizedBlockHash = vm.parseJsonBytes32(manifest, ".finalizedBlockHash");
        dependencies.operatorsNft = vm.parseJsonAddress(manifest, ".contracts.operatorsNft.address");
        dependencies.operatorsNftCodeHash = vm.parseJsonBytes32(manifest, ".contracts.operatorsNft.runtimeCodeHash");
        dependencies.activationRegistry = vm.parseJsonAddress(manifest, ".contracts.activationRegistry.address");
        dependencies.activationRegistryCodeHash =
            vm.parseJsonBytes32(manifest, ".contracts.activationRegistry.runtimeCodeHash");
    }

    function requireManifest(StaticsOperatorDependencies memory dependencies) internal view {
        if (keccak256(abi.encode(dependencies)) != keccak256(abi.encode(load()))) revert InvalidStaticsManifest();
    }

    function validate(StaticsOperatorDependencies memory dependencies) internal view {
        requireManifest(dependencies);
        if (block.chainid != dependencies.chainId || dependencies.chainId != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert InvalidStaticsChain(dependencies.chainId, block.chainid);
        }
        if (block.number < dependencies.finalizedBlock) {
            revert InvalidStaticsBlock(dependencies.finalizedBlock, block.number);
        }
        uint256 blockDistance = block.number - dependencies.finalizedBlock;
        if (blockDistance > 0 && blockDistance <= 256) {
            bytes32 actualBlockHash = blockhash(dependencies.finalizedBlock);
            if (actualBlockHash != dependencies.finalizedBlockHash) {
                revert InvalidStaticsBlockHash(dependencies.finalizedBlockHash, actualBlockHash);
            }
        }

        _validateCode(dependencies.operatorsNft, dependencies.operatorsNftCodeHash);
        _validateCode(dependencies.activationRegistry, dependencies.activationRegistryCodeHash);
        IStaticsOperators operators = IStaticsOperators(dependencies.operatorsNft);
        IGenesisActivationRegistryView registry = IGenesisActivationRegistryView(dependencies.activationRegistry);
        _validateBinding("ACTIVATION_REGISTRY", dependencies.activationRegistry, operators.activationRegistry());
        _validateBinding("GENESIS_COLLECTION", dependencies.operatorsNft, registry.genesisCollection());
        if (!operators.launchFinalized()) revert StaticsLaunchNotFinalized();
    }

    function _validateCode(address dependency, bytes32 expectedCodeHash) private view {
        if (dependency.code.length == 0) revert InvalidStaticsDependency(dependency);
        bytes32 actualCodeHash = dependency.codehash;
        if (actualCodeHash != expectedCodeHash) {
            revert InvalidStaticsCodeHash(dependency, expectedCodeHash, actualCodeHash);
        }
    }

    function _validateBinding(bytes32 binding, address expected, address actual) private pure {
        if (actual != expected) revert InvalidStaticsBinding(binding, expected, actual);
    }
}
