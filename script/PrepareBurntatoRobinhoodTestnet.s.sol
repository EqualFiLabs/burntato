// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";

import {StaticsOperatorDependencies} from "./DeploymentTypes.sol";
import {IGenesisActivationRegistryView, IStaticsOperators} from "../src/interfaces/IOperatorRewards.sol";
import {RobinhoodBlockProvenance} from "./libraries/RobinhoodBlockProvenance.sol";

struct StaticsTestnetHandoff {
    StaticsOperatorDependencies operatorDependencies;
    address genesisVault;
    bytes32 genesisVaultCodeHash;
    bytes32 genesisArtifactHash;
    uint256 genesisEpochEnd;
}

interface IStaticsGenesisHandoff {
    function vault() external view returns (address);
}

interface IStaticsGenesisVaultHandoff {
    function genesisEpochEnd() external view returns (uint256);
}

/// @notice Validates a fresh Statics Genesis replica and records its public Burntato handoff.
contract PrepareBurntatoRobinhoodTestnet is Script {
    uint256 public constant CHAIN_ID = 46_630;
    string public constant EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT = "43018f109006aa2c2eef2808adc2aa74dfc9a6d4";
    string public constant OUTPUT_PATH = "artifacts/robinhood-testnet/statics-handoff.json";

    error InvalidTestnetChain(uint256 actualChainId);
    error InvalidStaticsSourceCommit();
    error InvalidGenesisSourceCommit(string expected, string actual);
    error ExpiredGenesisEpoch(uint256 epochEnd, uint256 currentTimestamp);
    error InvalidStaticsDependency(address dependency);
    error InvalidStaticsBinding(bytes32 binding, address expected, address actual);
    error InvalidGenesisEpochEnd(uint256 expected, uint256 actual);
    error StaticsLaunchNotFinalized();
    error InvalidFinalizedBlock(uint256 blockNumber);
    error MissingFinalizedBlockHash(uint256 blockNumber);

    function run() external returns (StaticsTestnetHandoff memory handoff) {
        if (block.chainid != CHAIN_ID) revert InvalidTestnetChain(block.chainid);
        string memory artifact = vm.readFile(vm.envString("STATICS_GENESIS_TESTNET_ARTIFACT"));
        string memory staticsSourceCommit = vm.envString("STATICS_SOURCE_COMMIT");
        handoff = prepareArtifact(artifact, staticsSourceCommit);

        vm.createDir("artifacts/robinhood-testnet", true);
        vm.writeJson(artifact, OUTPUT_PATH);
        vm.writeJson(_quoted(staticsSourceCommit), OUTPUT_PATH, ".staticsSourceCommit");
        vm.writeJson(_quoted(vm.toString(handoff.genesisArtifactHash)), OUTPUT_PATH, ".genesisArtifactHash");
        vm.writeJson(vm.toString(handoff.operatorDependencies.finalizedBlock), OUTPUT_PATH, ".finalizedBlock");
        vm.writeJson(
            _quoted(vm.toString(handoff.operatorDependencies.finalizedBlockHash)), OUTPUT_PATH, ".finalizedBlockHash"
        );
        vm.writeJson(
            _quoted(vm.toString(handoff.operatorDependencies.operatorsNftCodeHash)),
            OUTPUT_PATH,
            ".operatorsNftRuntimeCodeHash"
        );
        vm.writeJson(
            _quoted(vm.toString(handoff.operatorDependencies.activationRegistryCodeHash)),
            OUTPUT_PATH,
            ".activationRegistryRuntimeCodeHash"
        );
        vm.writeJson(_quoted(vm.toString(handoff.genesisVaultCodeHash)), OUTPUT_PATH, ".genesisVaultRuntimeCodeHash");
    }

    function prepareArtifact(string memory artifact, string memory staticsSourceCommit)
        public
        view
        returns (StaticsTestnetHandoff memory handoff)
    {
        if (block.chainid != CHAIN_ID) revert InvalidTestnetChain(block.chainid);
        if (!_isCommit(staticsSourceCommit)) revert InvalidStaticsSourceCommit();

        uint256 artifactChainId = vm.parseJsonUint(artifact, ".chainId");
        if (artifactChainId != CHAIN_ID) revert InvalidTestnetChain(artifactChainId);

        string memory genesisSourceCommit = vm.parseJsonString(artifact, ".mainnetGenesisSourceCommit");
        if (keccak256(bytes(genesisSourceCommit)) != keccak256(bytes(EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT))) {
            revert InvalidGenesisSourceCommit(EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT, genesisSourceCommit);
        }

        handoff.genesisEpochEnd = vm.parseJsonUint(artifact, ".genesisEpochEnd");
        if (handoff.genesisEpochEnd <= block.timestamp) {
            revert ExpiredGenesisEpoch(handoff.genesisEpochEnd, block.timestamp);
        }

        address operatorsNft = vm.parseJsonAddress(artifact, ".genesis");
        address activationRegistry = vm.parseJsonAddress(artifact, ".activationRegistry");
        handoff.genesisVault = vm.parseJsonAddress(artifact, ".genesisVault");
        _validateStaticsBindings(operatorsNft, activationRegistry, handoff.genesisVault, handoff.genesisEpochEnd);

        uint256 currentBlock = RobinhoodBlockProvenance.blockNumber();
        if (currentBlock == 0) revert InvalidFinalizedBlock(currentBlock);
        uint256 finalizedBlock = currentBlock - 1;
        bytes32 finalizedBlockHash = RobinhoodBlockProvenance.blockHash(finalizedBlock);
        if (finalizedBlockHash == bytes32(0)) revert MissingFinalizedBlockHash(finalizedBlock);

        handoff.operatorDependencies = StaticsOperatorDependencies({
            chainId: CHAIN_ID,
            finalizedBlock: finalizedBlock,
            finalizedBlockHash: finalizedBlockHash,
            operatorsNft: operatorsNft,
            operatorsNftCodeHash: operatorsNft.codehash,
            activationRegistry: activationRegistry,
            activationRegistryCodeHash: activationRegistry.codehash
        });
        handoff.genesisVaultCodeHash = handoff.genesisVault.codehash;
        handoff.genesisArtifactHash = keccak256(bytes(artifact));
    }

    function _validateStaticsBindings(
        address operatorsNft,
        address activationRegistry,
        address genesisVault,
        uint256 genesisEpochEnd
    ) private view {
        if (operatorsNft == address(0) || operatorsNft.code.length == 0) {
            revert InvalidStaticsDependency(operatorsNft);
        }
        if (activationRegistry == address(0) || activationRegistry.code.length == 0) {
            revert InvalidStaticsDependency(activationRegistry);
        }
        if (genesisVault == address(0) || genesisVault.code.length == 0) {
            revert InvalidStaticsDependency(genesisVault);
        }

        IStaticsOperators operators = IStaticsOperators(operatorsNft);
        IGenesisActivationRegistryView registry = IGenesisActivationRegistryView(activationRegistry);
        address actualRegistry = operators.activationRegistry();
        if (actualRegistry != activationRegistry) {
            revert InvalidStaticsBinding("ACTIVATION_REGISTRY", activationRegistry, actualRegistry);
        }
        address actualCollection = registry.genesisCollection();
        if (actualCollection != operatorsNft) {
            revert InvalidStaticsBinding("GENESIS_COLLECTION", operatorsNft, actualCollection);
        }
        address actualVault = IStaticsGenesisHandoff(operatorsNft).vault();
        if (actualVault != genesisVault) {
            revert InvalidStaticsBinding("GENESIS_VAULT", genesisVault, actualVault);
        }
        uint256 actualEpochEnd = IStaticsGenesisVaultHandoff(genesisVault).genesisEpochEnd();
        if (actualEpochEnd != genesisEpochEnd) revert InvalidGenesisEpochEnd(genesisEpochEnd, actualEpochEnd);
        if (!operators.launchFinalized()) revert StaticsLaunchNotFinalized();
    }

    function _isCommit(string memory value) private pure returns (bool) {
        bytes memory encoded = bytes(value);
        if (encoded.length != 40) return false;
        for (uint256 index; index < encoded.length; ++index) {
            bytes1 character = encoded[index];
            bool decimal = character >= bytes1("0") && character <= bytes1("9");
            bool hexLetter = character >= bytes1("a") && character <= bytes1("f");
            if (!decimal && !hexLetter) return false;
        }
        return true;
    }

    function _quoted(string memory value) private pure returns (string memory) {
        return string.concat('"', value, '"');
    }
}
