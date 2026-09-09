// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";

import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {BurntatoOperatorRewardsRouter} from "../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {BurntatoDeployment, GenesisConfig} from "./DeploymentTypes.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";

contract BurntatoMarketVerifier {
    error VerificationFailed(bytes32 check);

    function verify(GenesisConfig memory config, BurntatoDeployment memory deployment) external view returns (bool) {
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
        _check(actual.potatoSeed == config.potatoSeed, "MARKET_POTATO_SEED");

        (bytes32 poolId, bool configured, bool launching, bool launched) = market.marketState();
        _check(poolId == bytes32(0) && configured && !launching && !launched, "MARKET_STATE");
        _check(market.marketReady(), "MARKET_READY");
        _check(market.lockedLpRecipient() == 0x000000000000000000000000000000000000dEaD, "LOCKED_LP");

        PoolKey memory key = market.canonicalPoolKey();
        _check(Currency.unwrap(key.currency0) == address(0), "POOL_NATIVE");
        _check(Currency.unwrap(key.currency1) == deployment.diamond, "POOL_POTATO");
        _check(key.fee == 0, "POOL_ZERO_LP_FEE");
        _check(key.tickSpacing == config.tickSpacing, "POOL_TICK_SPACING");
        _check(address(key.hooks) == deployment.hook, "POOL_HOOK");

        BurntatoSwapFeeHook hook = BurntatoSwapFeeHook(payable(deployment.hook));
        _check(hook.owner() == config.finalAdmin, "HOOK_OWNER");
        _check(hook.token() == deployment.diamond, "HOOK_TOKEN");
        _check(hook.feeAddress() == config.treasuryRecipient, "HOOK_FEE_ADDRESS");
        _check(hook.feeBps() == config.hookFeeBps, "HOOK_FEE_BPS");
        address expectedHookRouter = BurntatoDeploymentConfig.hookOperatorRewardsRouter(
            config.operatorRewardShareBps, deployment.operatorRewardsRouter
        );
        _check(hook.operatorRewardsRouter() == expectedHookRouter, "HOOK_OPERATOR_ROUTER");
        _check(hook.operatorRewardShareBps() == config.operatorRewardShareBps, "HOOK_OPERATOR_SHARE");
        _check(hook.tickSpacing() == config.tickSpacing, "HOOK_TICK_SPACING");
        _check(address(hook.poolManager()) == deployment.poolManager, "HOOK_POOL_MANAGER");
        _check(hook.deploymentBlock() == 0, "HOOK_POOL_UNINITIALIZED");
        _check(!hook.externalBuysEnabled(), "EXTERNAL_BUYS_DISABLED");
        if (config.operatorRewardShareBps == 0 && config.protocol.operatorPurchaseBps == 0) {
            _check(deployment.operatorRewardsRouter == address(0), "OPERATOR_ROUTER_DISABLED");
        } else {
            BurntatoOperatorRewardsRouter router =
                BurntatoOperatorRewardsRouter(payable(deployment.operatorRewardsRouter));
            _check(router.burntato() == deployment.diamond, "OPERATOR_ROUTER_BURNTATO");
            _check(router.totalRegisteredWeight() == 0, "OPERATOR_ROUTER_WEIGHT");
            _check(router.totalReceived() == 0, "OPERATOR_ROUTER_REVENUE");
            _check(address(router).balance == 0, "OPERATOR_ROUTER_BALANCE");
        }
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
        return true;
    }

    function _check(bool condition, bytes32 check) private pure {
        if (!condition) revert VerificationFailed(check);
    }
}
