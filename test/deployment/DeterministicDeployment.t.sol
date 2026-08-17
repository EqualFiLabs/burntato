// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoDeploymentVerifier} from "../../script/BurntatoDeploymentVerifier.sol";
import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {BurntatoDeployment, GenesisConfig} from "../../script/DeploymentTypes.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Round} from "../../src/shared/Types.sol";

interface IPoolManagerAuthority {
    function owner() external view returns (address);
    function protocolFeeController() external view returns (address);
}

interface IPositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract DeploymentConfigHarness {
    function checkedUint16(uint256 value) external pure returns (uint16) {
        return BurntatoDeploymentConfig.checkedUint16(value);
    }

    function checkedInt24(int256 value) external pure returns (int24) {
        return BurntatoDeploymentConfig.checkedInt24(value);
    }
}

contract DeterministicDeploymentTest is Test {
    DeployBurntato internal deployScript;
    BurntatoDeploymentVerifier internal verifier;
    GenesisConfig internal config;
    BurntatoDeployment internal deployment;

    address internal buyer = makeAddr("deploymentBuyer");

    function setUp() public {
        deployScript = new DeployBurntato();
        verifier = new BurntatoDeploymentVerifier();
        config = deployScript.localDefaults();
        deployment = deployScript.deploy(config, address(deployScript));
    }

    function test_VerifierConfirmsCompleteGenesisDeployment() public view {
        assertTrue(verifier.verify(config, deployment));
        assertTrue(IGovernance(deployment.diamond).authorityLocked());
        assertEq(IPoolManagerAuthority(deployment.poolManager).owner(), address(0));
        assertEq(IPoolManagerAuthority(deployment.poolManager).protocolFeeController(), address(0));
    }

    function test_DeploymentRejectsDelayBelowProtocolMinimum() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.timelockDelay = 1 days - 1;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsTickSpacingOutsidePoolManagerDomain() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.tickSpacing = 32_768;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_EnvironmentNarrowingHelpersRejectTruncation() public {
        DeploymentConfigHarness harness = new DeploymentConfigHarness();

        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        harness.checkedUint16(uint256(type(uint16).max) + 1);
        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        harness.checkedInt24(int256(type(int24).max) + 1);
        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        harness.checkedInt24(int256(type(int24).min) - 1);
    }

    function test_VerifierRejectsProtocolConfigurationMismatch() public {
        GenesisConfig memory mismatched = config;
        mismatched.startingPrice += 1;

        vm.expectRevert(
            abi.encodeWithSelector(BurntatoDeploymentVerifier.VerificationFailed.selector, bytes32("STARTING_PRICE"))
        );
        verifier.verify(mismatched, deployment);
    }

    function test_GenesisPurchaseSnapshotsFixedEmissionBudget() public {
        vm.deal(buyer, config.startingPrice);
        vm.prank(buyer);
        IGame(deployment.diamond).buyPotato{value: config.startingPrice}();

        Round memory round = IGame(deployment.diamond).getRound(1);
        assertEq(round.roundId, 1);
        assertEq(round.currentHolder, buyer);
        assertEq(round.remainingEmission, 100_000 ether);
        assertEq(round.holderMaxReward, 10_000 ether);
        assertEq(round.nextPrice, 0.011 ether);
    }

    function test_TimelockIsOnlyPathToAdministrativeMutation() public {
        address replacementGuardian = makeAddr("replacementGuardian");
        bytes memory data = abi.encodeCall(IGovernance.setGuardian, (replacementGuardian));
        bytes32 predecessor;
        bytes32 salt = keccak256("replace guardian");
        TimelockController timelock = TimelockController(payable(deployment.timelock));

        vm.prank(config.deployer);
        vm.expectRevert();
        IGovernance(deployment.diamond).setGuardian(replacementGuardian);

        vm.prank(config.proposer);
        timelock.schedule(deployment.diamond, 0, data, predecessor, salt, config.timelockDelay);
        vm.warp(block.timestamp + config.timelockDelay);
        timelock.execute(deployment.diamond, 0, data, predecessor, salt);

        assertEq(IGovernance(deployment.diamond).guardian(), replacementGuardian);
    }

    function test_LocalDependenciesLaunchLockedTwoSidedMarket() public {
        GenesisConfig memory launchConfig = config;
        launchConfig.nativeSeed = 0.001 ether;
        launchConfig.potatoSeed = 1 ether;
        BurntatoDeployment memory launchDeployment = deployScript.deploy(launchConfig, address(deployScript));
        IGame game = IGame(launchDeployment.diamond);
        IRecovery recovery = IRecovery(launchDeployment.diamond);
        ISettlement settlement = ISettlement(launchDeployment.diamond);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.buyPotato{value: launchConfig.startingPrice}();
        vm.warp(block.timestamp + 120);
        game.materializeMaturedEmission();
        vm.prank(buyer);
        recovery.commitRecovery(10_000 ether);
        vm.warp(game.getRound(1).deadline);
        settlement.settleRound();

        vm.prank(buyer);
        game.buyPotato{value: launchConfig.startingPrice}();
        vm.warp(game.getRound(2).deadline);
        settlement.settleRound();

        IMarket market = IMarket(launchDeployment.diamond);
        assertEq(IPotatoToken(launchDeployment.diamond).balanceOf(launchDeployment.diamond), 1_000 ether);
        assertTrue(market.marketReady());
        (bytes32 poolId, uint128 liquidity) = market.launchMarket();
        assertNotEq(poolId, bytes32(0));
        assertGt(liquidity, 0);
        assertEq(IPositionOwner(launchDeployment.positionManager).ownerOf(1), market.lockedLpRecipient());
    }
}
