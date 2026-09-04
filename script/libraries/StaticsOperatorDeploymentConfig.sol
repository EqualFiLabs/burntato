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
    uint256 internal constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    string internal constant MAINNET_MANIFEST_PATH = "deployments/statics-operators-robinhood-4663.json";
    string internal constant TESTNET_MANIFEST_PATH = "deployments/statics-operators-robinhood-testnet-46630.json";

    address private constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(VM_ADDRESS);

    function load() internal view returns (StaticsOperatorDependencies memory dependencies) {
        string memory manifest = vm.readFile(_manifestPath());
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
        if (block.chainid != dependencies.chainId || !_isSupportedChain(dependencies.chainId)) {
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

    function _manifestPath() private view returns (string memory) {
        if (block.chainid == ROBINHOOD_MAINNET_CHAIN_ID) return MAINNET_MANIFEST_PATH;
        if (block.chainid == ROBINHOOD_TESTNET_CHAIN_ID) return TESTNET_MANIFEST_PATH;
        revert InvalidStaticsChain(ROBINHOOD_MAINNET_CHAIN_ID, block.chainid);
    }

    function _isSupportedChain(uint256 chainId) private pure returns (bool) {
        return chainId == ROBINHOOD_MAINNET_CHAIN_ID || chainId == ROBINHOOD_TESTNET_CHAIN_ID;
    }
}
