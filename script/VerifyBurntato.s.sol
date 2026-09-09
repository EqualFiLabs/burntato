// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {BurntatoDeploymentVerifier} from "./BurntatoDeploymentVerifier.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {BurntatoSourceCodeHashes} from "./libraries/BurntatoSourceCodeHashes.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract VerifyBurntato is Script {
    function run() external returns (bool) {
        GenesisConfig memory config = _environmentConfig();
        BurntatoDeployment memory deployment;
        deployment.diamond = vm.envAddress("BURNTATO_DIAMOND");
        deployment.admin = vm.envAddress("BURNTATO_ADMIN");
        deployment.diamondCutFacet = vm.envAddress("BURNTATO_DIAMOND_CUT_FACET");
        deployment.diamondLoupeFacet = vm.envAddress("BURNTATO_DIAMOND_LOUPE_FACET");
        deployment.governanceFacet = vm.envAddress("BURNTATO_GOVERNANCE_FACET");
        deployment.marketFacet = vm.envAddress("BURNTATO_MARKET_FACET");
        deployment.buybackFacet = vm.envAddress("BURNTATO_BUYBACK_FACET");
        deployment.potatoTokenFacet = vm.envAddress("BURNTATO_POTATO_TOKEN_FACET");
        deployment.gameFacet = vm.envAddress("BURNTATO_GAME_FACET");
        deployment.recoveryFacet = vm.envAddress("BURNTATO_RECOVERY_FACET");
        deployment.settlementFacet = vm.envAddress("BURNTATO_SETTLEMENT_FACET");
        deployment.claimsFacet = vm.envAddress("BURNTATO_CLAIMS_FACET");
        deployment.treasuryRewardsFacet = vm.envAddress("BURNTATO_TREASURY_REWARDS_FACET");
        deployment.foundationInit = vm.envAddress("BURNTATO_FOUNDATION_INIT");
        deployment.hookDeployer = vm.envAddress("BURNTATO_HOOK_DEPLOYER");
        deployment.poolManager = vm.envAddress("BURNTATO_POOL_MANAGER");
        deployment.positionManager = vm.envAddress("BURNTATO_POSITION_MANAGER");
        deployment.permit2 = vm.envAddress("BURNTATO_PERMIT2");
        deployment.hook = vm.envAddress("BURNTATO_HOOK");
        deployment.operatorRewardsRouter = vm.envOr("BURNTATO_OPERATOR_REWARDS_ROUTER", address(0));
        _loadCodeHashes(deployment);

        BurntatoDeploymentVerifier verifier = new BurntatoDeploymentVerifier();
        bool verified;
        if (config.operatorRewardShareBps == 0 && config.protocol.operatorPurchaseBps == 0) {
            verified = verifier.verify(config, deployment);
        } else {
            CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
            StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
            deployment.positionDescriptor = dependencies.positionDescriptor;
            deployment.quoter = dependencies.quoter;
            deployment.stateView = dependencies.stateView;
            deployment.reservesLens = dependencies.reservesLens;
            deployment.universalRouter = dependencies.universalRouter;
            deployment.weth9 = dependencies.weth;
            verified = verifier.verifyCanonical(config, deployment, dependencies, operatorDependencies);
        }
        console2.log("Burntato deployment verified", verified);
        return verified;
    }

    function _loadCodeHashes(BurntatoDeployment memory deployment) private view {
        deployment.codeHashes.diamond = BurntatoSourceCodeHashes.DIAMOND;
        deployment.codeHashes.diamondCutFacet = BurntatoSourceCodeHashes.DIAMOND_CUT_FACET;
        deployment.codeHashes.diamondLoupeFacet = BurntatoSourceCodeHashes.DIAMOND_LOUPE_FACET;
        deployment.codeHashes.governanceFacet = BurntatoSourceCodeHashes.GOVERNANCE_FACET;
        deployment.codeHashes.marketFacet = BurntatoSourceCodeHashes.MARKET_FACET;
        deployment.codeHashes.buybackFacet = BurntatoSourceCodeHashes.BUYBACK_FACET;
        deployment.codeHashes.potatoTokenFacet = BurntatoSourceCodeHashes.POTATO_TOKEN_FACET;
        deployment.codeHashes.gameFacet = BurntatoSourceCodeHashes.GAME_FACET;
        deployment.codeHashes.recoveryFacet = BurntatoSourceCodeHashes.RECOVERY_FACET;
        deployment.codeHashes.settlementFacet = BurntatoSourceCodeHashes.SETTLEMENT_FACET;
        deployment.codeHashes.claimsFacet = BurntatoSourceCodeHashes.CLAIMS_FACET;
        deployment.codeHashes.treasuryRewardsFacet = BurntatoSourceCodeHashes.TREASURY_REWARDS_FACET;
        deployment.codeHashes.foundationInit = BurntatoSourceCodeHashes.FOUNDATION_INIT;
        deployment.codeHashes.hookDeployer = vm.envBytes32("BURNTATO_HOOK_DEPLOYER_CODE_HASH");
        deployment.codeHashes.hook = vm.envBytes32("BURNTATO_HOOK_CODE_HASH");
        if (deployment.operatorRewardsRouter != address(0)) {
            deployment.codeHashes.operatorRewardsRouter = vm.envBytes32("BURNTATO_OPERATOR_REWARDS_ROUTER_CODE_HASH");
        }
    }

    function _environmentConfig() private view returns (GenesisConfig memory config) {
        config = BurntatoDeploymentConfig.localDefaults();
        config.deployer = vm.envOr("BURNTATO_DEPLOYER", config.deployer);
        config.finalAdmin = vm.envOr("BURNTATO_FINAL_ADMIN", config.finalAdmin);
        config.guardian = vm.envOr("BURNTATO_GUARDIAN", config.guardian);
        config.treasuryRecipient = vm.envOr("BURNTATO_TREASURY", config.treasuryRecipient);
        config.rewardAllocator = vm.envOr("BURNTATO_REWARD_ALLOCATOR", config.rewardAllocator);
        config.protocol.startingPrice = vm.envOr("BURNTATO_STARTING_PRICE", config.protocol.startingPrice);
        config.protocol.priceIncreaseBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_PRICE_INCREASE_BPS", uint256(config.protocol.priceIncreaseBps))
        );
        config.protocol.roundTimeout = vm.envOr("BURNTATO_ROUND_TIMEOUT", config.protocol.roundTimeout);
        config.protocol.roundTimeoutDecay = vm.envOr("BURNTATO_ROUND_TIMEOUT_DECAY", config.protocol.roundTimeoutDecay);
        config.protocol.minimumRoundTimeout =
            vm.envOr("BURNTATO_MINIMUM_ROUND_TIMEOUT", config.protocol.minimumRoundTimeout);
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
        config.protocol.operatorPurchaseBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_OPERATOR_PURCHASE_BPS", uint256(config.protocol.operatorPurchaseBps))
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
        config.operatorRewardShareBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_OPERATOR_REWARD_SHARE_BPS", uint256(config.operatorRewardShareBps))
        );
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
