// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {BurntatoDeploymentVerifier} from "./BurntatoDeploymentVerifier.sol";
import {BurntatoDeployment, GenesisConfig} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";

contract VerifyBurntato is Script {
    function run() external returns (bool) {
        GenesisConfig memory config = _environmentConfig();
        BurntatoDeployment memory deployment;
        deployment.diamond = vm.envAddress("BURNTATO_DIAMOND");
        deployment.timelock = vm.envAddress("BURNTATO_TIMELOCK");
        deployment.poolManager = vm.envAddress("BURNTATO_POOL_MANAGER");
        deployment.positionManager = vm.envAddress("BURNTATO_POSITION_MANAGER");
        deployment.permit2 = vm.envAddress("BURNTATO_PERMIT2");
        deployment.hook = vm.envAddress("BURNTATO_HOOK");

        IDiamondLoupe loupe = IDiamondLoupe(deployment.diamond);
        deployment.diamondCutFacet = loupe.facetAddress(BurntatoSelectors.diamondCut()[0]);
        deployment.diamondLoupeFacet = loupe.facetAddress(BurntatoSelectors.loupe()[0]);
        deployment.governanceFacet = loupe.facetAddress(BurntatoSelectors.governance()[0]);
        deployment.marketFacet = loupe.facetAddress(BurntatoSelectors.market()[0]);
        deployment.buybackFacet = loupe.facetAddress(BurntatoSelectors.buyback()[0]);
        deployment.potatoTokenFacet = loupe.facetAddress(BurntatoSelectors.token()[0]);
        deployment.gameFacet = loupe.facetAddress(BurntatoSelectors.game()[0]);
        deployment.recoveryFacet = loupe.facetAddress(BurntatoSelectors.recovery()[0]);
        deployment.settlementFacet = loupe.facetAddress(BurntatoSelectors.settlement()[0]);
        deployment.claimsFacet = loupe.facetAddress(BurntatoSelectors.claims()[0]);

        bool verified = (new BurntatoDeploymentVerifier()).verify(config, deployment);
        console2.log("Burntato deployment verified", verified);
        return verified;
    }

    function _environmentConfig() private view returns (GenesisConfig memory config) {
        config = BurntatoDeploymentConfig.localDefaults();
        config.deployer = vm.envOr("BURNTATO_DEPLOYER", config.deployer);
        config.proposer = vm.envOr("BURNTATO_PROPOSER", config.proposer);
        config.guardian = vm.envOr("BURNTATO_GUARDIAN", config.guardian);
        config.treasuryRecipient = vm.envOr("BURNTATO_TREASURY", config.treasuryRecipient);
        config.timelockDelay = vm.envOr("BURNTATO_TIMELOCK_DELAY", config.timelockDelay);
        config.protocol.startingPrice = vm.envOr("BURNTATO_STARTING_PRICE", config.protocol.startingPrice);
        config.protocol.priceIncreaseBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_PRICE_INCREASE_BPS", uint256(config.protocol.priceIncreaseBps))
        );
        config.protocol.roundTimeout = vm.envOr("BURNTATO_ROUND_TIMEOUT", config.protocol.roundTimeout);
        config.protocol.roundEmissionBudget =
            vm.envOr("BURNTATO_ROUND_EMISSION_BUDGET", config.protocol.roundEmissionBudget);
        config.protocol.emissionStepBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_EMISSION_STEP_BPS", uint256(config.protocol.emissionStepBps))
        );
        config.protocol.emissionVestingDuration =
            vm.envOr("BURNTATO_EMISSION_VESTING_DURATION", config.protocol.emissionVestingDuration);
        config.protocol.winnerBps =
            BurntatoDeploymentConfig.checkedUint16(vm.envOr("BURNTATO_WINNER_BPS", uint256(config.protocol.winnerBps)));
        config.protocol.recoveryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_BPS", uint256(config.protocol.recoveryBps))
        );
        config.protocol.treasuryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_TREASURY_BPS", uint256(config.protocol.treasuryBps))
        );
        config.protocol.buybackBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_BUYBACK_BPS", uint256(config.protocol.buybackBps))
        );
        config.buyback.maxSpend = vm.envOr("BURNTATO_BUYBACK_MAX_SPEND", config.buyback.maxSpend);
        config.buyback.callerRewardBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_BUYBACK_CALLER_REWARD_BPS", uint256(config.buyback.callerRewardBps))
        );
        config.buyback.delayBlocks = vm.envOr("BURNTATO_BUYBACK_DELAY_BLOCKS", config.buyback.delayBlocks);
        config.protocol.recoveryBurnBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_BURN_BPS", uint256(config.protocol.recoveryBurnBps))
        );
        config.protocol.recoveryTreasuryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_TREASURY_BPS", uint256(config.protocol.recoveryTreasuryBps))
        );
        config.hookFeeBps =
            BurntatoDeploymentConfig.checkedUint16(vm.envOr("BURNTATO_HOOK_FEE_BPS", uint256(config.hookFeeBps)));
        config.initialTick =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_INITIAL_TICK", int256(config.initialTick)));
        config.tickSpacing =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_TICK_SPACING", int256(config.tickSpacing)));
        config.tickLower =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_TICK_LOWER", int256(config.tickLower)));
        config.tickUpper =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_TICK_UPPER", int256(config.tickUpper)));
        config.potatoSeed = vm.envOr("BURNTATO_POTATO_SEED", config.potatoSeed);
    }
}
