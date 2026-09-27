// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {
    PrepareBurntatoRobinhoodTestnet,
    StaticsTestnetHandoff
} from "../../script/PrepareBurntatoRobinhoodTestnet.s.sol";
import {DeployBurntatoRobinhoodTestnet} from "../../script/DeployBurntatoRobinhoodTestnet.s.sol";
import {IArbSys} from "../../script/libraries/RobinhoodBlockProvenance.sol";

contract HandoffOperatorCollection {
    address public activationRegistry;
    address public vault;
    bool public launchFinalized = true;

    function setActivationRegistry(address registry) external {
        activationRegistry = registry;
    }

    function setVault(address genesisVault) external {
        vault = genesisVault;
    }

    function setLaunchFinalized(bool finalized) external {
        launchFinalized = finalized;
    }
}

contract HandoffGenesisVault {
    uint256 public genesisEpochEnd;

    function setGenesisEpochEnd(uint256 epochEnd) external {
        genesisEpochEnd = epochEnd;
    }
}

contract HandoffActivationRegistry {
    address public genesisCollection;

    function setGenesisCollection(address collection) external {
        genesisCollection = collection;
    }
}

contract RobinhoodTestnetHandoffTest is Test {
    address private constant ARB_SYS = address(100);
    uint256 private constant CURRENT_BLOCK = 123_456;
    bytes32 private constant FINALIZED_BLOCK_HASH = keccak256("finalized-testnet-block");
    string private constant STATICS_SOURCE_COMMIT = "a2e7ad43f868b9ac59d70ac885d55e5b33ad88cb";

    PrepareBurntatoRobinhoodTestnet private prepare;
    HandoffOperatorCollection private operators;
    HandoffActivationRegistry private registry;
    HandoffGenesisVault private vault;

    function setUp() public {
        vm.chainId(46_630);
        prepare = new PrepareBurntatoRobinhoodTestnet();
        operators = new HandoffOperatorCollection();
        registry = new HandoffActivationRegistry();
        vault = new HandoffGenesisVault();
        operators.setActivationRegistry(address(registry));
        operators.setVault(address(vault));
        registry.setGenesisCollection(address(operators));
        vault.setGenesisEpochEnd(block.timestamp + 15 days);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(CURRENT_BLOCK));
        vm.mockCall(
            ARB_SYS, abi.encodeCall(IArbSys.arbBlockHash, (CURRENT_BLOCK - 1)), abi.encode(FINALIZED_BLOCK_HASH)
        );
    }

    function test_PrepareArtifactPinsFinalizedBindingsAndHashes() public view {
        string memory artifact = _artifact(block.timestamp + 15 days, prepare.EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT());
        StaticsTestnetHandoff memory handoff = prepare.prepareArtifact(artifact, STATICS_SOURCE_COMMIT);

        assertEq(handoff.operatorDependencies.chainId, 46_630);
        assertEq(handoff.operatorDependencies.finalizedBlock, CURRENT_BLOCK - 1);
        assertEq(handoff.operatorDependencies.finalizedBlockHash, FINALIZED_BLOCK_HASH);
        assertEq(handoff.operatorDependencies.operatorsNft, address(operators));
        assertEq(handoff.operatorDependencies.operatorsNftCodeHash, address(operators).codehash);
        assertEq(handoff.operatorDependencies.activationRegistry, address(registry));
        assertEq(handoff.operatorDependencies.activationRegistryCodeHash, address(registry).codehash);
        assertEq(handoff.genesisVault, address(vault));
        assertEq(handoff.genesisVaultCodeHash, address(vault).codehash);
        assertEq(handoff.genesisArtifactHash, keccak256(bytes(artifact)));
        assertEq(handoff.genesisEpochEnd, block.timestamp + 15 days);
    }

    function test_PrepareArtifactRejectsWrongChainBeforeArtifactParsing() public {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(PrepareBurntatoRobinhoodTestnet.InvalidTestnetChain.selector, 1));
        prepare.prepareArtifact("not-json", STATICS_SOURCE_COMMIT);
    }

    function test_PrepareArtifactRejectsInvalidSourceCommitsAndExpiredEpoch() public {
        string memory validArtifact =
            _artifact(block.timestamp + 15 days, prepare.EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT());
        vm.expectRevert(PrepareBurntatoRobinhoodTestnet.InvalidStaticsSourceCommit.selector);
        prepare.prepareArtifact(validArtifact, "not-a-commit");

        string memory wrongGenesisArtifact =
            _artifact(block.timestamp + 15 days, "0000000000000000000000000000000000000000");
        vm.expectRevert(
            abi.encodeWithSelector(
                PrepareBurntatoRobinhoodTestnet.InvalidGenesisSourceCommit.selector,
                prepare.EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT(),
                "0000000000000000000000000000000000000000"
            )
        );
        prepare.prepareArtifact(wrongGenesisArtifact, STATICS_SOURCE_COMMIT);

        string memory expiredArtifact = _artifact(block.timestamp, prepare.EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT());
        vm.expectRevert(
            abi.encodeWithSelector(
                PrepareBurntatoRobinhoodTestnet.ExpiredGenesisEpoch.selector, block.timestamp, block.timestamp
            )
        );
        prepare.prepareArtifact(expiredArtifact, STATICS_SOURCE_COMMIT);
    }

    function test_PrepareArtifactRejectsUnfinalizedOrMismatchedStatics() public {
        string memory artifact = _artifact(block.timestamp + 15 days, prepare.EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT());
        operators.setLaunchFinalized(false);
        vm.expectRevert(PrepareBurntatoRobinhoodTestnet.StaticsLaunchNotFinalized.selector);
        prepare.prepareArtifact(artifact, STATICS_SOURCE_COMMIT);

        operators.setLaunchFinalized(true);
        address wrongRegistry = makeAddr("wrong-registry");
        operators.setActivationRegistry(wrongRegistry);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrepareBurntatoRobinhoodTestnet.InvalidStaticsBinding.selector,
                bytes32("ACTIVATION_REGISTRY"),
                address(registry),
                wrongRegistry
            )
        );
        prepare.prepareArtifact(artifact, STATICS_SOURCE_COMMIT);

        operators.setActivationRegistry(address(registry));
        address wrongVault = makeAddr("wrong-vault");
        operators.setVault(wrongVault);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrepareBurntatoRobinhoodTestnet.InvalidStaticsBinding.selector,
                bytes32("GENESIS_VAULT"),
                address(vault),
                wrongVault
            )
        );
        prepare.prepareArtifact(artifact, STATICS_SOURCE_COMMIT);

        operators.setVault(address(vault));
        vault.setGenesisEpochEnd(block.timestamp + 14 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                PrepareBurntatoRobinhoodTestnet.InvalidGenesisEpochEnd.selector,
                block.timestamp + 15 days,
                block.timestamp + 14 days
            )
        );
        prepare.prepareArtifact(artifact, STATICS_SOURCE_COMMIT);
    }

    function test_PrepareArtifactRequiresHistoricalBlockHash() public {
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockHash, (CURRENT_BLOCK - 1)), abi.encode(bytes32(0)));
        string memory artifact = _artifact(block.timestamp + 15 days, prepare.EXPECTED_MAINNET_GENESIS_SOURCE_COMMIT());
        vm.expectRevert(
            abi.encodeWithSelector(
                PrepareBurntatoRobinhoodTestnet.MissingFinalizedBlockHash.selector, CURRENT_BLOCK - 1
            )
        );
        prepare.prepareArtifact(artifact, STATICS_SOURCE_COMMIT);
    }

    function test_BurntatoPreflightRequiresMatchingActiveGenesisVault() public {
        DeployBurntatoRobinhoodTestnet deploy = new DeployBurntatoRobinhoodTestnet();
        uint256 epochEnd = block.timestamp + 15 days;
        assertTrue(
            deploy.validateActiveStaticsReplica(address(operators), address(vault), address(vault).codehash, epochEnd)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBurntatoRobinhoodTestnet.InvalidStaticsGenesisVaultCodeHash.selector,
                bytes32(uint256(1)),
                address(vault).codehash
            )
        );
        deploy.validateActiveStaticsReplica(address(operators), address(vault), bytes32(uint256(1)), epochEnd);

        vault.setGenesisEpochEnd(block.timestamp);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBurntatoRobinhoodTestnet.ExpiredStaticsGenesisEpoch.selector, block.timestamp, block.timestamp
            )
        );
        deploy.validateActiveStaticsReplica(
            address(operators), address(vault), address(vault).codehash, block.timestamp
        );
    }

    function _artifact(uint256 genesisEpochEnd, string memory genesisSourceCommit)
        private
        view
        returns (string memory)
    {
        return string.concat(
            '{"chainId":46630,"mainnetGenesisSourceCommit":"',
            genesisSourceCommit,
            '","genesisEpochEnd":',
            vm.toString(genesisEpochEnd),
            ',"genesis":"',
            vm.toString(address(operators)),
            '","activationRegistry":"',
            vm.toString(address(registry)),
            '","genesisVault":"',
            vm.toString(address(vault)),
            '"}'
        );
    }
}
