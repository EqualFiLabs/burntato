// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {IClaims} from "../src/interfaces/IClaims.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {IGame} from "../src/interfaces/IGame.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";
import {ProtocolConfig, Round} from "../src/shared/Types.sol";
import {Constants} from "../src/shared/Constants.sol";
import {BurntatoDeployment, GenesisConfig} from "./DeploymentTypes.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";

interface IOwnedPoolManager {
    function owner() external view returns (address);
}

contract BurntatoDeploymentVerifier {
    error VerificationFailed(bytes32 check);

    function verify(GenesisConfig memory config, BurntatoDeployment memory deployment) external view returns (bool) {
        _verifyConfigDomain(config);
        _verifyCode(deployment);
        _verifySelectors(deployment);
        _verifyAuthority(config, deployment);
        _verifyProtocolState(config, deployment);
        _verifyMarket(config, deployment);
        return true;
    }

    function _verifyCode(BurntatoDeployment memory deployment) private view {
        _check(deployment.diamond.code.length != 0, "DIAMOND_CODE");
        _check(deployment.timelock.code.length != 0, "TIMELOCK_CODE");
        _check(deployment.poolManager.code.length != 0, "POOL_MANAGER_CODE");
        _check(deployment.positionManager.code.length != 0, "POSITION_MANAGER_CODE");
        _check(deployment.permit2.code.length != 0, "PERMIT2_CODE");
        _check(deployment.hook.code.length != 0, "HOOK_CODE");
    }

    function _verifySelectors(BurntatoDeployment memory deployment) private view {
        IDiamondLoupe loupe = IDiamondLoupe(deployment.diamond);
        _check(loupe.facetAddresses().length == 9, "FACET_COUNT");
        _verifyGroup(loupe, deployment.diamondCutFacet, BurntatoSelectors.diamondCut());
        _verifyGroup(loupe, deployment.diamondLoupeFacet, BurntatoSelectors.loupe());
        _verifyGroup(loupe, deployment.governanceFacet, BurntatoSelectors.governance());
        _verifyGroup(loupe, deployment.marketFacet, BurntatoSelectors.market());
        _verifyGroup(loupe, deployment.potatoTokenFacet, BurntatoSelectors.token());
        _verifyGroup(loupe, deployment.gameFacet, BurntatoSelectors.game());
        _verifyGroup(loupe, deployment.recoveryFacet, BurntatoSelectors.recovery());
        _verifyGroup(loupe, deployment.settlementFacet, BurntatoSelectors.settlement());
        _verifyGroup(loupe, deployment.claimsFacet, BurntatoSelectors.claims());
    }

    function _verifyAuthority(GenesisConfig memory config, BurntatoDeployment memory deployment) private view {
        IGovernance governance = IGovernance(deployment.diamond);
        TimelockController timelock = TimelockController(payable(deployment.timelock));
        _check(governance.authority() == deployment.timelock, "DIAMOND_AUTHORITY");
        _check(IOwnedPoolManager(deployment.poolManager).owner() == deployment.timelock, "POOL_MANAGER_OWNER");
        _check(timelock.getMinDelay() == config.timelockDelay, "TIMELOCK_DELAY");
        _check(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployment.timelock), "TIMELOCK_SELF_ADMIN");
        _check(timelock.hasRole(timelock.PROPOSER_ROLE(), config.proposer), "PROPOSER_ROLE");
        _check(timelock.hasRole(timelock.CANCELLER_ROLE(), config.proposer), "CANCELLER_ROLE");
        _check(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "OPEN_EXECUTION");
        _check(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), config.deployer), "NO_DEPLOYER_ADMIN");
    }

    function _verifyProtocolState(GenesisConfig memory config, BurntatoDeployment memory deployment) private view {
        IGovernance governance = IGovernance(deployment.diamond);
        IClaims claims = IClaims(deployment.diamond);
        IPotatoToken token = IPotatoToken(deployment.diamond);
        IGame game = IGame(deployment.diamond);
        _check(governance.guardian() == config.guardian, "GUARDIAN");
        _check(!governance.purchasesPaused(), "PURCHASES_UNPAUSED");
        _check(!governance.commitmentsPaused(), "COMMITMENTS_UNPAUSED");
        _check(!governance.protocolFinalized(), "NOT_FINALIZED");
        ProtocolConfig memory protocol = governance.protocolConfig();
        ProtocolConfig memory expected = config.protocol;
        _check(protocol.startingPrice == expected.startingPrice, "STARTING_PRICE");
        _check(protocol.priceIncreaseBps == expected.priceIncreaseBps, "PRICE_INCREASE_BPS");
        _check(protocol.roundTimeout == expected.roundTimeout, "ROUND_TIMEOUT");
        _check(protocol.roundEmissionBudget == expected.roundEmissionBudget, "ROUND_EMISSION_BUDGET");
        _check(protocol.emissionStepBps == expected.emissionStepBps, "EMISSION_STEP_BPS");
        _check(protocol.emissionVestingDuration == expected.emissionVestingDuration, "EMISSION_VESTING_DURATION");
        _check(protocol.winnerBps == expected.winnerBps, "WINNER_BPS");
        _check(protocol.recoveryBps == expected.recoveryBps, "RECOVERY_BPS");
        _check(protocol.treasuryBps == expected.treasuryBps, "TREASURY_BPS");
        _check(protocol.buybackBps == expected.buybackBps, "BUYBACK_BPS");
        _check(protocol.recoveryBurnBps == expected.recoveryBurnBps, "RECOVERY_BURN_BPS");
        _check(protocol.recoveryTreasuryBps == expected.recoveryTreasuryBps, "RECOVERY_TREASURY_BPS");
        _check(claims.treasuryRecipient() == config.treasuryRecipient, "TREASURY_RECIPIENT");
        _check(claims.treasuryEthAvailable() == 0, "TREASURY_ETH_AVAILABLE");
        _check(claims.treasuryPotatoAvailable() == 0, "TREASURY_POTATO_AVAILABLE");
        _check(keccak256(bytes(token.name())) == keccak256("Burntato Potato"), "TOKEN_NAME");
        _check(keccak256(bytes(token.symbol())) == keccak256("POTATO"), "TOKEN_SYMBOL");
        _check(token.decimals() == 18, "TOKEN_DECIMALS");
        _check(token.totalSupply() == 0, "TOKEN_SUPPLY");
        _check(token.isDistributor(config.treasuryRecipient), "TREASURY_DISTRIBUTOR");
        _check(game.currentRoundId() == 0, "ROUND_NOT_STARTED");
        Round memory emptyRound = game.getRound(0);
        _check(emptyRound.roundId == 0 && emptyRound.remainingEmission == 0, "EMPTY_GENESIS_ROUND");
    }

    function _verifyMarket(GenesisConfig memory config, BurntatoDeployment memory deployment) private view {
        IMarket market = IMarket(deployment.diamond);
        IMarket.MarketConfig memory actual = market.marketConfig();
        _check(actual.hook == deployment.hook, "MARKET_HOOK");
        _check(actual.poolManager == deployment.poolManager, "MARKET_POOL_MANAGER");
        _check(actual.positionManager == deployment.positionManager, "MARKET_POSITION_MANAGER");
        _check(actual.permit2 == deployment.permit2, "MARKET_PERMIT2");
        _check(actual.sqrtPriceX96 == TickMath.getSqrtPriceAtTick(config.initialTick), "MARKET_PRICE");
        _check(actual.tickLower == config.tickLower, "MARKET_TICK_LOWER");
        _check(actual.tickUpper == config.tickUpper, "MARKET_TICK_UPPER");
        _check(actual.tickSpacing == config.tickSpacing, "MARKET_TICK_SPACING");
        _check(actual.nativeSeed == config.nativeSeed, "MARKET_NATIVE_SEED");
        _check(actual.potatoSeed == config.potatoSeed, "MARKET_POTATO_SEED");

        (bytes32 poolId, bool configured, bool launching, bool launched) = market.marketState();
        _check(poolId == bytes32(0) && configured && !launching && !launched, "MARKET_STATE");
        _check(!market.marketReady(), "MARKET_NOT_FUNDED");
        _check(market.lockedLpRecipient() == 0x000000000000000000000000000000000000dEaD, "LOCKED_LP");

        PoolKey memory key = market.canonicalPoolKey();
        _check(Currency.unwrap(key.currency0) == address(0), "POOL_NATIVE");
        _check(Currency.unwrap(key.currency1) == deployment.diamond, "POOL_POTATO");
        _check(key.fee == 0, "POOL_ZERO_LP_FEE");
        _check(key.tickSpacing == config.tickSpacing, "POOL_TICK_SPACING");
        _check(address(key.hooks) == deployment.hook, "POOL_HOOK");

        BurntatoSwapFeeHook hook = BurntatoSwapFeeHook(payable(deployment.hook));
        _check(hook.owner() == deployment.timelock, "HOOK_OWNER");
        _check(hook.token() == deployment.diamond, "HOOK_TOKEN");
        _check(hook.feeAddress() == config.treasuryRecipient, "HOOK_FEE_ADDRESS");
        _check(hook.feeBps() == config.hookFeeBps, "HOOK_FEE_BPS");
        _check(hook.tickSpacing() == config.tickSpacing, "HOOK_TICK_SPACING");
        _check(address(hook.poolManager()) == deployment.poolManager, "HOOK_POOL_MANAGER");
        _check(hook.deploymentBlock() == 0, "HOOK_POOL_UNINITIALIZED");
        _check(!hook.externalBuysEnabled(), "EXTERNAL_BUYS_DISABLED");
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        _check(uint160(deployment.hook) & Hooks.ALL_HOOK_MASK == flags, "HOOK_FLAGS");
        _check(
            address(PositionManager(payable(deployment.positionManager)).poolManager()) == deployment.poolManager,
            "PM_POOL"
        );
        _check(
            address(PositionManager(payable(deployment.positionManager)).permit2()) == deployment.permit2, "PM_PERMIT2"
        );
    }

    function _verifyConfigDomain(GenesisConfig memory config) private pure {
        ProtocolConfig memory protocol = config.protocol;
        _check(protocol.startingPrice != 0, "STARTING_PRICE_DOMAIN");
        _check(
            protocol.roundTimeout != 0 && protocol.roundTimeout <= type(uint64).max
                && protocol.emissionVestingDuration != 0,
            "TIME_DOMAIN"
        );
        _check(protocol.priceIncreaseBps <= Constants.BPS, "PRICE_BPS_DOMAIN");
        _check(protocol.emissionStepBps <= Constants.BPS, "EMISSION_BPS_DOMAIN");
        _check(
            uint256(protocol.winnerBps) + protocol.recoveryBps + protocol.treasuryBps + protocol.buybackBps
                == Constants.BPS,
            "PURCHASE_SPLIT_DOMAIN"
        );
        _check(
            uint256(protocol.recoveryBurnBps) + protocol.recoveryTreasuryBps == Constants.BPS, "RECOVERY_SPLIT_DOMAIN"
        );
        _check(config.hookFeeBps <= Constants.BPS, "HOOK_FEE_DOMAIN");
        _check(
            config.tickSpacing >= TickMath.MIN_TICK_SPACING && config.tickSpacing <= TickMath.MAX_TICK_SPACING,
            "TICK_SPACING_DOMAIN"
        );
        _check(config.tickLower >= TickMath.MIN_TICK && config.tickUpper <= TickMath.MAX_TICK, "TICK_BOUNDS_DOMAIN");
        _check(config.tickLower < config.initialTick && config.initialTick < config.tickUpper, "INITIAL_TICK_DOMAIN");
        _check(
            config.tickLower % config.tickSpacing == 0 && config.tickUpper % config.tickSpacing == 0,
            "TICK_ALIGNMENT_DOMAIN"
        );
        _check(config.nativeSeed != 0 && config.potatoSeed != 0, "SEED_DOMAIN");
    }

    function _verifyGroup(IDiamondLoupe loupe, address expectedFacet, bytes4[] memory selectors) private view {
        _check(expectedFacet != address(0) && expectedFacet.code.length != 0, "FACET_CODE");
        for (uint256 i; i < selectors.length; ++i) {
            _check(loupe.facetAddress(selectors[i]) == expectedFacet, "SELECTOR_ROUTING");
        }
        _check(loupe.facetFunctionSelectors(expectedFacet).length == selectors.length, "FACET_SELECTOR_COUNT");
    }

    function _check(bool condition, bytes32 check) private pure {
        if (!condition) revert VerificationFailed(check);
    }
}
