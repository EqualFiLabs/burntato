// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IAllowanceTransfer} from "@uniswap/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPoolInitializer_v4} from "@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";

import {IMarket} from "../interfaces/IMarket.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";

interface ICanonicalHookConfig {
    function token() external view returns (address);
    function poolManager() external view returns (IPoolManager);
    function tickSpacing() external view returns (int24);
}

contract MarketFacet is IMarket {
    function configureMarket(MarketConfig calldata config) external {
        LibDiamond.enforceAuthority();
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        if (ms.launched) revert Errors.AlreadyLaunched();
        _validateConfiguration(config);
        if (
            ICanonicalHookConfig(config.hook).token() != address(this)
                || address(ICanonicalHookConfig(config.hook).poolManager()) != config.poolManager
                || ICanonicalHookConfig(config.hook).tickSpacing() != config.tickSpacing
        ) revert Errors.InvalidMarketConfiguration();
        address treasuryRecipient = LibProtocolStorage.treasury().recipient;
        if (
            treasuryRecipient == config.hook || treasuryRecipient == config.poolManager
                || treasuryRecipient == config.positionManager || treasuryRecipient == config.permit2
        ) revert Errors.InvalidMarketConfiguration();

        uint256 previousSeed = ms.potatoSeed;
        LibProtocolStorage.TreasuryStorage storage treasuryStorage = LibProtocolStorage.treasury();
        if (config.potatoSeed > previousSeed) {
            uint256 additional = config.potatoSeed - previousSeed;
            uint256 available = treasuryStorage.potatoInventory - treasuryStorage.reservedPotato;
            if (additional > available) revert Errors.MarketNotReady();
            treasuryStorage.reservedPotato += additional;
        } else if (previousSeed > config.potatoSeed) {
            treasuryStorage.reservedPotato -= previousSeed - config.potatoSeed;
        }

        ms.hook = config.hook;
        ms.poolManager = config.poolManager;
        ms.positionManager = config.positionManager;
        ms.permit2 = config.permit2;
        ms.sqrtPriceX96 = config.sqrtPriceX96;
        ms.tickLower = config.tickLower;
        ms.tickUpper = config.tickUpper;
        ms.tickSpacing = config.tickSpacing;
        ms.potatoSeed = config.potatoSeed;
        ms.configured = true;

        LibProtocolStorage.TokenStorage storage token = LibProtocolStorage.token();
        token.canonicalHook = config.hook;
        token.poolManager = config.poolManager;

        emit MarketConfigured(
            config.hook,
            config.poolManager,
            config.positionManager,
            config.permit2,
            config.sqrtPriceX96,
            config.tickLower,
            config.tickUpper,
            config.tickSpacing,
            config.potatoSeed
        );
    }

    function launchMarket() external returns (bytes32 poolId, uint128 liquidity) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        if (!ms.configured) revert Errors.MarketNotConfigured();
        if (ms.launched) revert Errors.AlreadyLaunched();
        if (!_marketReady(ms)) revert Errors.MarketNotReady();

        PoolKey memory key = _poolKey(ms);
        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(ms.tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(ms.tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtLower, sqrtUpper, ms.potatoSeed);
        if (liquidity == 0) revert Errors.InvalidMarketConfiguration();

        uint256 potatoBefore = IPotatoToken(address(this)).balanceOf(address(this));

        ms.launched = true;
        _setLaunching(true);
        if (!IPotatoToken(address(this)).approve(ms.permit2, type(uint256).max)) {
            revert Errors.TokenOperationFailed();
        }
        IAllowanceTransfer(ms.permit2).approve(address(this), ms.positionManager, type(uint160).max, type(uint48).max);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));
        bytes[] memory mintParams = new bytes[](2);
        mintParams[0] = abi.encode(
            key,
            ms.tickLower,
            ms.tickUpper,
            liquidity,
            uint256(0),
            ms.potatoSeed,
            Constants.LOCKED_LP_RECIPIENT,
            bytes("")
        );
        mintParams[1] = abi.encode(key.currency0, key.currency1);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, key, ms.sqrtPriceX96);
        calls[1] = abi.encodeWithSelector(
            IPositionManager.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );
        IPositionManager(ms.positionManager).multicall(calls);
        _setLaunching(false);

        uint256 potatoUsed = potatoBefore - IPotatoToken(address(this)).balanceOf(address(this));
        if (potatoUsed == 0) revert Errors.InvalidMarketConfiguration();

        LibProtocolStorage.TreasuryStorage storage treasuryStorage = LibProtocolStorage.treasury();
        treasuryStorage.potatoInventory -= potatoUsed;
        treasuryStorage.reservedPotato -= ms.potatoSeed;

        poolId = PoolId.unwrap(key.toId());
        ms.poolId = poolId;
        emit MarketLaunched(poolId, liquidity, potatoUsed, Constants.LOCKED_LP_RECIPIENT);
    }

    function marketConfig() external view returns (MarketConfig memory config) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        config = MarketConfig({
            hook: ms.hook,
            poolManager: ms.poolManager,
            positionManager: ms.positionManager,
            permit2: ms.permit2,
            sqrtPriceX96: ms.sqrtPriceX96,
            tickLower: ms.tickLower,
            tickUpper: ms.tickUpper,
            tickSpacing: ms.tickSpacing,
            potatoSeed: ms.potatoSeed
        });
    }

    function canonicalPoolKey() external view returns (PoolKey memory key) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        if (!ms.configured) revert Errors.MarketNotConfigured();
        return _poolKey(ms);
    }

    function marketState() external view returns (bytes32 poolId, bool configured, bool launching, bool launched) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        return (ms.poolId, ms.configured, _launching(), ms.launched);
    }

    function marketLaunching() external view returns (bool) {
        return _launching();
    }

    function marketReady() external view returns (bool) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        return ms.configured && !ms.launched && _marketReady(ms);
    }

    function lockedLpRecipient() external pure returns (address) {
        return Constants.LOCKED_LP_RECIPIENT;
    }

    function _validateConfiguration(MarketConfig calldata config) private view {
        if (
            config.hook == address(0) || config.poolManager == address(0) || config.positionManager == address(0)
                || config.permit2 == address(0) || config.potatoSeed == 0
                || config.tickSpacing < TickMath.MIN_TICK_SPACING || config.tickSpacing > TickMath.MAX_TICK_SPACING
                || config.tickLower >= config.tickUpper || config.tickLower % config.tickSpacing != 0
                || config.tickUpper % config.tickSpacing != 0 || config.tickLower < TickMath.MIN_TICK
                || config.tickUpper > TickMath.MAX_TICK
        ) revert Errors.InvalidMarketConfiguration();
        if (config.sqrtPriceX96 != TickMath.getSqrtPriceAtTick(config.tickUpper)) {
            revert Errors.InvalidMarketConfiguration();
        }
        LibDiamond.enforceHasCode(config.hook);
        LibDiamond.enforceHasCode(config.poolManager);
        LibDiamond.enforceHasCode(config.positionManager);
        LibDiamond.enforceHasCode(config.permit2);
    }

    function _poolKey(LibProtocolStorage.MarketStorage storage ms) private view returns (PoolKey memory key) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(this)),
            fee: Constants.POOL_LP_FEE,
            tickSpacing: ms.tickSpacing,
            hooks: IHooks(ms.hook)
        });
    }

    function _marketReady(LibProtocolStorage.MarketStorage storage ms) private view returns (bool) {
        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        return ts.potatoInventory >= ms.potatoSeed && ts.reservedPotato >= ms.potatoSeed
            && IPotatoToken(address(this)).balanceOf(address(this)) >= ms.potatoSeed;
    }

    function _setLaunching(bool value) private {
        bytes32 slot = LibProtocolStorage.MARKET_LAUNCH_SLOT;
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }

    function _launching() private view returns (bool value) {
        bytes32 slot = LibProtocolStorage.MARKET_LAUNCH_SLOT;
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }
}
