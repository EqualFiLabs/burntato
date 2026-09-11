// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {CanonicalV4Dependencies, StaticsOperatorDependencies} from "../../script/DeploymentTypes.sol";
import {RobinhoodDeploymentConfig} from "../../script/libraries/RobinhoodDeploymentConfig.sol";
import {IArbSys} from "../../script/libraries/RobinhoodBlockProvenance.sol";
import {StaticsOperatorDeploymentConfig} from "../../script/libraries/StaticsOperatorDeploymentConfig.sol";

contract RobinhoodBlockValidationHarness {
    function validateCanonical(CanonicalV4Dependencies memory dependencies) external view {
        RobinhoodDeploymentConfig.validate(dependencies);
    }

    function validateStatics(StaticsOperatorDependencies memory dependencies) external view {
        StaticsOperatorDeploymentConfig.validate(dependencies);
    }
}

contract RobinhoodBlockProvenanceTest is Test {
    address private constant ARB_SYS = address(100);
    RobinhoodBlockValidationHarness private harness;

    function setUp() public {
        vm.chainId(RobinhoodDeploymentConfig.ROBINHOOD_MAINNET_CHAIN_ID);
        harness = new RobinhoodBlockValidationHarness();
    }

    function test_CanonicalValidatorUsesRobinhoodBlockNumber() public {
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        uint256 priorBlock = dependencies.forkBlock - 1;
        vm.roll(dependencies.forkBlock + 1_000);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(priorBlock));

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodDeploymentConfig.InvalidCanonicalBlock.selector, dependencies.forkBlock, priorBlock
            )
        );
        harness.validateCanonical(dependencies);
    }

    function test_CanonicalValidatorUsesRobinhoodBlockHash() public {
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        uint256 currentBlock = dependencies.forkBlock + 1;
        bytes32 incorrectHash = bytes32(uint256(dependencies.forkBlockHash) ^ 1);
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(currentBlock));
        vm.mockCall(ARB_SYS, abi.encodeCall(IArbSys.arbBlockHash, (dependencies.forkBlock)), abi.encode(incorrectHash));

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodDeploymentConfig.InvalidCanonicalBlockHash.selector, dependencies.forkBlockHash, incorrectHash
            )
        );
        harness.validateCanonical(dependencies);
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
}
