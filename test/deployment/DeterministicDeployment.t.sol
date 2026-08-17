// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoDeploymentVerifier} from "../../script/BurntatoDeploymentVerifier.sol";
import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {BurntatoDeployment, GenesisConfig} from "../../script/DeploymentTypes.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Round} from "../../src/shared/Types.sol";

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
}
