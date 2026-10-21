// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {StaticsMarketDependencies, StaticsOperatorDependencies} from "../../script/DeploymentTypes.sol";
import {StaticsMarketDeploymentConfig} from "../../script/libraries/StaticsMarketDeploymentConfig.sol";
import {IArbSys} from "../../script/libraries/RobinhoodBlockProvenance.sol";
import {StaticsOperatorDeploymentConfig} from "../../script/libraries/StaticsOperatorDeploymentConfig.sol";

contract RobinhoodBlockValidationHarness {
    function validateMarket(StaticsMarketDependencies memory dependencies) external view {
        StaticsMarketDeploymentConfig.validate(dependencies);
    }

    function validateMarketAnvil(
        StaticsMarketDependencies memory dependencies,
        uint256 currentBlock,
        bytes32 actualBlockHash
    ) external view {
        StaticsMarketDeploymentConfig.validateAnvilFork(dependencies, currentBlock, actualBlockHash);
    }

    function validateStatics(StaticsOperatorDependencies memory dependencies) external view {
        StaticsOperatorDeploymentConfig.validate(dependencies);
    }

    function validateStaticsAnvil(
        StaticsOperatorDependencies memory dependencies,
        uint256 currentBlock,
        bytes32 actualBlockHash
    ) external view {
        StaticsOperatorDeploymentConfig.validateAnvilFork(dependencies, currentBlock, actualBlockHash);
    }
}

contract RobinhoodBlockProvenanceTest is Test {
    address private constant ARB_SYS = address(100);
    RobinhoodBlockValidationHarness private harness;

    function setUp() public {
        vm.chainId(4663);
        harness = new RobinhoodBlockValidationHarness();
    }

    function test_MarketValidatorUsesRobinhoodBlockNumber() public {
        StaticsMarketDependencies memory dependencies = StaticsMarketDeploymentConfig.load();
        uint256 priorBlock = dependencies.forkBlock - 1;
        vm.roll(dependencies.forkBlock + 1_000);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(priorBlock));

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsMarketDeploymentConfig.InvalidMarketBlock.selector, dependencies.forkBlock, priorBlock
            )
        );
        harness.validateMarket(dependencies);
    }

    function test_MarketValidatorUsesRobinhoodBlockHash() public {
        StaticsMarketDependencies memory dependencies = StaticsMarketDeploymentConfig.load();
        uint256 currentBlock = dependencies.forkBlock + 1;
        bytes32 incorrectHash = bytes32(uint256(dependencies.forkBlockHash) ^ 1);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(currentBlock));
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockHash, (dependencies.forkBlock)), abi.encode(incorrectHash));

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsMarketDeploymentConfig.InvalidMarketBlockHash.selector, dependencies.forkBlockHash, incorrectHash
            )
        );
        harness.validateMarket(dependencies);
    }

    function test_AnvilMarketValidatorRejectsBlockBeforeManifest() public {
        StaticsMarketDependencies memory dependencies = StaticsMarketDeploymentConfig.load();
        uint256 priorBlock = dependencies.forkBlock - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsMarketDeploymentConfig.InvalidMarketBlock.selector, dependencies.forkBlock, priorBlock
            )
        );
        harness.validateMarketAnvil(dependencies, priorBlock, dependencies.forkBlockHash);
    }

    function test_AnvilMarketValidatorRequiresHistoricalHash() public {
        StaticsMarketDependencies memory dependencies = StaticsMarketDeploymentConfig.load();
        bytes32 incorrectHash = bytes32(uint256(dependencies.forkBlockHash) ^ 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsMarketDeploymentConfig.InvalidMarketBlockHash.selector, dependencies.forkBlockHash, incorrectHash
            )
        );
        harness.validateMarketAnvil(dependencies, dependencies.forkBlock, incorrectHash);
    }

    function test_StaticsValidatorUsesRobinhoodBlockNumber() public {
        StaticsOperatorDependencies memory dependencies = StaticsOperatorDeploymentConfig.load();
        uint256 priorBlock = dependencies.finalizedBlock - 1;
        vm.roll(dependencies.finalizedBlock + 1_000);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(priorBlock));

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOperatorDeploymentConfig.InvalidStaticsBlock.selector, dependencies.finalizedBlock, priorBlock
            )
        );
        harness.validateStatics(dependencies);
    }

    function test_StaticsValidatorUsesRobinhoodBlockHash() public {
        StaticsOperatorDependencies memory dependencies = StaticsOperatorDeploymentConfig.load();
        uint256 currentBlock = dependencies.finalizedBlock + 1;
        bytes32 incorrectHash = bytes32(uint256(dependencies.finalizedBlockHash) ^ 1);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(currentBlock));
        vm.mockCall(
            ARB_SYS, abi.encodeCall(IArbSys.arbBlockHash, (dependencies.finalizedBlock)), abi.encode(incorrectHash)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOperatorDeploymentConfig.InvalidStaticsBlockHash.selector,
                dependencies.finalizedBlockHash,
                incorrectHash
            )
        );
        harness.validateStatics(dependencies);
    }

    function test_AnvilStaticsValidatorRejectsBlockBeforeFinalization() public {
        StaticsOperatorDependencies memory dependencies = StaticsOperatorDeploymentConfig.load();
        uint256 priorBlock = dependencies.finalizedBlock - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOperatorDeploymentConfig.InvalidStaticsBlock.selector, dependencies.finalizedBlock, priorBlock
            )
        );
        harness.validateStaticsAnvil(dependencies, priorBlock, dependencies.finalizedBlockHash);
    }

    function test_AnvilStaticsValidatorRequiresHistoricalHash() public {
        StaticsOperatorDependencies memory dependencies = StaticsOperatorDeploymentConfig.load();
        bytes32 incorrectHash = bytes32(uint256(dependencies.finalizedBlockHash) ^ 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOperatorDeploymentConfig.InvalidStaticsBlockHash.selector,
                dependencies.finalizedBlockHash,
                incorrectHash
            )
        );
        harness.validateStaticsAnvil(dependencies, dependencies.finalizedBlock, incorrectHash);
    }
}
