// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {BurntatoOperatorRewardsRouter} from "../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IClaims} from "../src/interfaces/IClaims.sol";
import {IGame} from "../src/interfaces/IGame.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";
import {ITreasuryRewards} from "../src/interfaces/ITreasuryRewards.sol";
import {BuybackConfig, ProtocolConfig, Round} from "../src/shared/Types.sol";
import {Constants} from "../src/shared/Constants.sol";
import {LibMarketMath} from "../src/libraries/LibMarketMath.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {RobinhoodDeploymentConfig} from "./libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";
import {BurntatoMarketVerifier} from "./BurntatoMarketVerifier.sol";
import {BurntatoStructureVerifier} from "./BurntatoStructureVerifier.sol";

interface IOwnedPoolManager {
    function owner() external view returns (address);
}

contract BurntatoDeploymentVerifier {
    error VerificationFailed(bytes32 check);

    BurntatoStructureVerifier private immutable STRUCTURE_VERIFIER;
    BurntatoMarketVerifier private immutable MARKET_VERIFIER;

    constructor() {
        STRUCTURE_VERIFIER = new BurntatoStructureVerifier();
        MARKET_VERIFIER = new BurntatoMarketVerifier();
    }

    function verify(GenesisConfig memory config, BurntatoDeployment memory deployment) external view returns (bool) {
        _check(
            config.operatorRewardShareBps == 0 && config.protocol.operatorPurchaseBps == 0,
            "OPERATOR_CANONICAL_REQUIRED"
        );
        _verifyCommon(config, deployment);
        _check(IOwnedPoolManager(deployment.poolManager).owner() == config.finalAdmin, "POOL_MANAGER_OWNER");
        return true;
    }

    function verifyCanonical(
        GenesisConfig memory config,
        BurntatoDeployment memory deployment,
        CanonicalV4Dependencies memory dependencies
    ) external view returns (bool) {
        _check(
            config.operatorRewardShareBps == 0 && config.protocol.operatorPurchaseBps == 0,
            "OPERATOR_DEPENDENCIES_REQUIRED"
        );
        RobinhoodDeploymentConfig.validate(dependencies);
        _verifyCanonicalAddresses(deployment, dependencies);
        _verifyCommon(config, deployment);
        return true;
    }

    function verifyCanonical(
        GenesisConfig memory config,
        BurntatoDeployment memory deployment,
        CanonicalV4Dependencies memory dependencies,
        StaticsOperatorDependencies memory operatorDependencies
    ) external view returns (bool) {
        _check(
            config.operatorRewardShareBps != 0 || config.protocol.operatorPurchaseBps != 0, "OPERATOR_REWARDS_REQUIRED"
        );
        RobinhoodDeploymentConfig.validate(dependencies);
        StaticsOperatorDeploymentConfig.validate(operatorDependencies);
        _verifyCanonicalAddresses(deployment, dependencies);
        _verifyCommon(config, deployment);
        BurntatoOperatorRewardsRouter router = BurntatoOperatorRewardsRouter(payable(deployment.operatorRewardsRouter));
        _check(address(router.operators()) == operatorDependencies.operatorsNft, "OPERATOR_NFT");
        _check(address(router.activationRegistry()) == operatorDependencies.activationRegistry, "ACTIVATION_REGISTRY");
        return true;
    }

    function _verifyCommon(GenesisConfig memory config, BurntatoDeployment memory deployment) private view {
        _verifyConfigDomain(config);
        STRUCTURE_VERIFIER.verify(deployment);
        _verifyAuthority(config, deployment);
        _verifyProtocolState(config, deployment);
        MARKET_VERIFIER.verify(config, deployment);
    }

    function _verifyCanonicalAddresses(
        BurntatoDeployment memory deployment,
        CanonicalV4Dependencies memory dependencies
    ) private pure {
        _check(deployment.poolManager == dependencies.poolManager, "CANONICAL_POOL_MANAGER");
        _check(deployment.positionDescriptor == dependencies.positionDescriptor, "CANONICAL_DESCRIPTOR");
        _check(deployment.positionManager == dependencies.positionManager, "CANONICAL_POSITION_MANAGER");
        _check(deployment.quoter == dependencies.quoter, "CANONICAL_QUOTER");
        _check(deployment.stateView == dependencies.stateView, "CANONICAL_STATE_VIEW");
        _check(deployment.reservesLens == dependencies.reservesLens, "CANONICAL_RESERVES_LENS");
        _check(deployment.universalRouter == dependencies.universalRouter, "CANONICAL_ROUTER");
        _check(deployment.permit2 == dependencies.permit2, "CANONICAL_PERMIT2");
        _check(deployment.weth9 == dependencies.weth, "CANONICAL_WETH");
    }

    function _verifyAuthority(GenesisConfig memory config, BurntatoDeployment memory deployment) private view {
        IGovernance governance = IGovernance(deployment.diamond);
        _check(deployment.admin == config.finalAdmin, "FINAL_ADMIN");
        _check(governance.authority() == config.finalAdmin, "DIAMOND_AUTHORITY");
        _check(BurntatoSwapFeeHook(payable(deployment.hook)).owner() == config.finalAdmin, "HOOK_OWNER");
    }

    function _verifyProtocolState(GenesisConfig memory config, BurntatoDeployment memory deployment) private view {
        IGovernance governance = IGovernance(deployment.diamond);
        IClaims claims = IClaims(deployment.diamond);
        IPotatoToken token = IPotatoToken(deployment.diamond);
        IGame game = IGame(deployment.diamond);
        IBuyback buyback = IBuyback(deployment.diamond);
        ITreasuryRewards rewards = ITreasuryRewards(deployment.diamond);
        _check(governance.guardian() == config.guardian, "GUARDIAN");
        _check(!governance.purchasesPaused(), "PURCHASES_UNPAUSED");
        _check(!governance.commitmentsPaused(), "COMMITMENTS_UNPAUSED");
        _check(!governance.protocolFinalized(), "NOT_FINALIZED");
        _check(governance.foundationConfigured(), "FOUNDATION_CONFIGURED");
        _check(!governance.purchasesInitialized(), "PURCHASES_NOT_INITIALIZED");
        ProtocolConfig memory protocol = governance.protocolConfig();
        ProtocolConfig memory expected = config.protocol;
        _check(protocol.startingPrice == expected.startingPrice, "STARTING_PRICE");
        _check(protocol.priceIncreaseBps == expected.priceIncreaseBps, "PRICE_INCREASE_BPS");
        _check(protocol.roundTimeout == expected.roundTimeout, "ROUND_TIMEOUT");
        _check(protocol.roundTimeoutDecay == expected.roundTimeoutDecay, "ROUND_TIMEOUT_DECAY");
        _check(protocol.minimumRoundTimeout == expected.minimumRoundTimeout, "MINIMUM_ROUND_TIMEOUT");
        _check(protocol.roundEmissionBudget == expected.roundEmissionBudget, "ROUND_EMISSION_BUDGET");
        _check(protocol.emissionStepBps == expected.emissionStepBps, "EMISSION_STEP_BPS");
        _check(protocol.emissionVestingDuration == expected.emissionVestingDuration, "EMISSION_VESTING_DURATION");
        _check(protocol.winnerBps == expected.winnerBps, "WINNER_BPS");
        _check(protocol.recoveryBps == expected.recoveryBps, "RECOVERY_BPS");
        _check(protocol.treasuryBps == expected.treasuryBps, "TREASURY_BPS");
        _check(protocol.buybackBps == expected.buybackBps, "BUYBACK_BPS");
        _check(protocol.operatorPurchaseBps == expected.operatorPurchaseBps, "OPERATOR_PURCHASE_BPS");
        _check(protocol.recoveryBurnBps == expected.recoveryBurnBps, "RECOVERY_BURN_BPS");
        _check(protocol.recoveryTreasuryBps == expected.recoveryTreasuryBps, "RECOVERY_TREASURY_BPS");
        _check(claims.treasuryRecipient() == config.treasuryRecipient, "TREASURY_RECIPIENT");
        _check(rewards.rewardAllocator() == config.rewardAllocator, "REWARD_ALLOCATOR");
        _check(rewards.treasuryRewardsReserved() == 0, "REWARD_RESERVE");
        _check(claims.treasuryEthAvailable() == 0, "TREASURY_ETH_AVAILABLE");
        _check(claims.treasuryPotatoAvailable() == 0, "TREASURY_POTATO_AVAILABLE");
        _check(keccak256(bytes(token.name())) == keccak256("Burntato Potato"), "TOKEN_NAME");
        _check(keccak256(bytes(token.symbol())) == keccak256("POTATO"), "TOKEN_SYMBOL");
        _check(token.decimals() == 18, "TOKEN_DECIMALS");
        _check(token.totalSupply() == config.potatoSeed, "TOKEN_SUPPLY");
        _check(token.balanceOf(deployment.diamond) == config.potatoSeed, "GENESIS_MARKET_BALANCE");
        _check(token.canonicalHook() == deployment.hook, "TOKEN_CANONICAL_HOOK");
        _check(token.tokenPoolManager() == deployment.poolManager, "TOKEN_POOL_MANAGER");
        _check(token.isDistributor(config.treasuryRecipient), "TREASURY_DISTRIBUTOR");
        BuybackConfig memory buybackConfig = buyback.buybackConfig();
        _check(buybackConfig.maxSpend == config.buyback.maxSpend, "BUYBACK_MAX_SPEND");
        _check(buybackConfig.callerRewardBps == config.buyback.callerRewardBps, "BUYBACK_REWARD_BPS");
        _check(buybackConfig.delayBlocks == config.buyback.delayBlocks, "BUYBACK_DELAY_BLOCKS");
        _check(buyback.buybackReserveEth() == 0, "BUYBACK_RESERVE");
        _check(buyback.lastBuybackBlock() == 0, "BUYBACK_LAST_BLOCK");
        _check(game.currentRoundId() == 0, "ROUND_NOT_STARTED");
        _check(game.purchaseOperatorRewardsRouter() == deployment.operatorRewardsRouter, "PURCHASE_OPERATOR_ROUTER");
        Round memory emptyRound = game.getRound(0);
        _check(emptyRound.roundId == 0 && emptyRound.remainingEmission == 0, "EMPTY_GENESIS_ROUND");
    }

    function _verifyConfigDomain(GenesisConfig memory config) private pure {
        ProtocolConfig memory protocol = config.protocol;
        _check(protocol.startingPrice != 0, "STARTING_PRICE_DOMAIN");
        _check(
            protocol.roundTimeout != 0 && protocol.roundTimeout <= type(uint64).max && protocol.minimumRoundTimeout != 0
                && protocol.minimumRoundTimeout <= protocol.roundTimeout
                && protocol.roundTimeoutDecay <= protocol.roundTimeout && protocol.emissionVestingDuration != 0,
            "TIME_DOMAIN"
        );
        _check(protocol.priceIncreaseBps <= Constants.BPS, "PRICE_BPS_DOMAIN");
        _check(protocol.emissionStepBps <= Constants.BPS, "EMISSION_BPS_DOMAIN");
        _check(
            uint256(protocol.winnerBps) + protocol.recoveryBps + protocol.treasuryBps + protocol.buybackBps
                    + protocol.operatorPurchaseBps == Constants.BPS,
            "PURCHASE_SPLIT_DOMAIN"
        );
        _check(
            uint256(protocol.recoveryBurnBps) + protocol.recoveryTreasuryBps == Constants.BPS, "RECOVERY_SPLIT_DOMAIN"
        );
        _check(config.hookFeeBps <= Constants.MAX_HOOK_FEE_BPS, "HOOK_FEE_DOMAIN");
        _check(config.operatorRewardShareBps <= Constants.BPS, "OPERATOR_SHARE_DOMAIN");
        _check(config.buyback.callerRewardBps <= Constants.MAX_BUYBACK_CALLER_REWARD_BPS, "BUYBACK_REWARD_DOMAIN");
        _check(
            config.tickSpacing >= TickMath.MIN_TICK_SPACING && config.tickSpacing <= TickMath.MAX_TICK_SPACING,
            "TICK_SPACING_DOMAIN"
        );
        _check(config.tickLower >= TickMath.MIN_TICK && config.tickUpper < TickMath.MAX_TICK, "TICK_BOUNDS_DOMAIN");
        _check(config.tickLower < config.initialTick && config.initialTick == config.tickUpper, "INITIAL_TICK_DOMAIN");
        _check(
            config.tickLower % config.tickSpacing == 0 && config.tickUpper % config.tickSpacing == 0,
            "TICK_ALIGNMENT_DOMAIN"
        );
        _check(config.potatoSeed != 0, "SEED_DOMAIN");
        _check(
            LibMarketMath.launchLiquidity(config.potatoSeed, config.tickLower, config.tickUpper) != 0,
            "LAUNCH_LIQUIDITY_DOMAIN"
        );
    }

    function _check(bool condition, bytes32 check) private pure {
        if (!condition) revert VerificationFailed(check);
    }
}
