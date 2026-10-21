// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LibGuard} from "../libraries/LibGuard.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IBuyback} from "../interfaces/IBuyback.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibMath} from "../libraries/LibMath.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";
import {BuybackConfig, BuybackQuote} from "../shared/Types.sol";

contract BuybackFacet is IBuyback, LibGuard {
    using BalanceDeltaLibrary for BalanceDelta;

    modifier onlyDiamond() {
        if (LibDiamond.diamondStorage().selectorData[msg.sig].facet == address(0)) revert Errors.InvalidAddress();
        _;
    }

    /// @notice Authority selects an existing STATICS/WETH market; no wrapper pool is created.
    function setBuybackMarket(address poolManager, address weth, PoolKey calldata key) external {
        LibDiamond.enforceAuthority();
        LibDiamond.enforceHasCode(poolManager);
        LibDiamond.enforceHasCode(weth);
        address statics = LibProtocolStorage.wrapper().underlying;
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        if (
            statics == address(0) || weth == statics || poolManager == address(this) || weth == address(this)
                || currency0 >= currency1 || key.tickSpacing <= 0
                || !((currency0 == weth && currency1 == statics) || (currency0 == statics && currency1 == weth))
        ) {
            revert Errors.InvalidMarketConfiguration();
        }
        if (address(key.hooks) != address(0)) LibDiamond.enforceHasCode(address(key.hooks));
        address treasury = LibProtocolStorage.treasury().recipient;
        if (treasury == poolManager || treasury == weth || treasury == address(key.hooks)) {
            revert Errors.InvalidAddress();
        }
        LibProtocolStorage.BuybackMarketStorage storage market = LibProtocolStorage.buybackMarket();
        market.poolManager = poolManager;
        market.weth = weth;
        market.key = key;
        market.configured = true;
        emit BuybackMarketSet(poolManager, weth, PoolId.unwrap(PoolIdLibrary.toId(key)));
    }

    function buybackMarket() external view returns (address poolManager, address weth, PoolKey memory key) {
        LibProtocolStorage.BuybackMarketStorage storage market = LibProtocolStorage.buybackMarket();
        return (market.poolManager, market.weth, market.key);
    }

    function setBuybackConfig(BuybackConfig calldata config) external {
        LibDiamond.enforceAuthority();
        if (config.callerRewardBps > Constants.MAX_BUYBACK_CALLER_REWARD_BPS) revert Errors.InvalidBps();
        LibProtocolStorage.buyback().config = config;
        emit BuybackConfigUpdated(config);
    }

    function buybackConfig() external view returns (BuybackConfig memory config) {
        return LibProtocolStorage.buyback().config;
    }

    function fundBuybackReserve() external payable onlyDiamond nonReentrant {
        if (msg.value == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth += msg.value;
        emit BuybackReserveFunded(msg.sender, msg.value, bs.reserveEth);
    }

    function buybackReserveEth() external view returns (uint256) {
        return LibProtocolStorage.buyback().reserveEth;
    }

    function lastBuybackBlock() external view returns (uint256) {
        return LibProtocolStorage.buyback().lastBuybackBlock;
    }

    function buyback() external nonReentrant returns (uint256 amountOut) {
        if (LibProtocolStorage.governance().paused) revert Errors.ProtocolPaused();

        LibProtocolStorage.BuybackMarketStorage storage market = LibProtocolStorage.buybackMarket();
        if (!market.configured) revert Errors.MarketNotConfigured();

        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        BuybackQuote memory quote = _prepareBuyback(bs);
        uint256 ethSpent;
        (ethSpent, amountOut) = _executeBuyback(market, quote.requestedInput);

        bs.reserveEth += quote.grossSlice - ethSpent - quote.callerReward;
        if (quote.callerReward != 0) SafeTransferLib.safeTransferETH(msg.sender, quote.callerReward);
        emit BuybackExecuted(
            msg.sender,
            address(this),
            quote.grossSlice,
            ethSpent,
            amountOut,
            amountOut,
            quote.callerReward,
            bs.reserveEth
        );
    }

    function _prepareBuyback(LibProtocolStorage.BuybackStorage storage bs) private returns (BuybackQuote memory quote) {
        BuybackConfig memory config = bs.config;
        if (config.callerRewardBps > Constants.MAX_BUYBACK_CALLER_REWARD_BPS) revert Errors.InvalidBps();
        uint256 reserve = bs.reserveEth;
        if (reserve == 0 || config.maxSpend == 0) revert Errors.BuybackUnavailable();

        if (config.delayBlocks > type(uint256).max - bs.lastBuybackBlock) {
            revert Errors.BuybackTooSoon(type(uint256).max);
        }
        uint256 nextBlock = bs.lastBuybackBlock + config.delayBlocks;
        if (block.number < nextBlock) revert Errors.BuybackTooSoon(nextBlock);

        quote = LibMath.quoteBuyback(reserve, config.maxSpend, config.callerRewardBps);
        if (quote.requestedInput > uint256(type(int256).max)) revert Errors.InvalidMarketConfiguration();
        bs.reserveEth = reserve - quote.grossSlice;
        bs.lastBuybackBlock = block.number;
    }

    function _executeBuyback(LibProtocolStorage.BuybackMarketStorage storage market, uint256 requestedInput)
        private
        returns (uint256 ethSpent, uint256 amountOut)
    {
        uint256 backingBefore = IPotatoToken(address(this)).backingBalance();
        if (requestedInput != 0) {
            market.callbackPending = true;
            bytes memory result = IPoolManager(market.poolManager).unlock(abi.encode(requestedInput));
            (ethSpent, amountOut) = abi.decode(result, (uint256, uint256));
        }
        if (
            market.callbackPending || ethSpent != requestedInput || amountOut == 0
                || IPotatoToken(address(this)).backingBalance() != backingBefore + amountOut
        ) revert Errors.BuybackNoExecution();
        IPotatoToken(address(this)).protocolCreditRewardReserve(amountOut, backingBefore);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        LibProtocolStorage.BuybackMarketStorage storage market = LibProtocolStorage.buybackMarket();
        if (
            msg.sender != market.poolManager || msg.sender == address(0) || !market.callbackPending
                || LibProtocolStorage.reentrancy().status != 2
        ) revert Errors.InvalidAddress();
        market.callbackPending = false;
        uint256 amountIn = abi.decode(data, (uint256));
        IPoolManager manager = IPoolManager(market.poolManager);
        PoolKey memory key = market.key;
        bool zeroForOne = Currency.unwrap(key.currency0) == market.weth;
        BalanceDelta delta = manager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );
        int128 inputDelta = zeroForOne ? delta.amount0() : delta.amount1();
        int128 outputDelta = zeroForOne ? delta.amount1() : delta.amount0();
        if (inputDelta > 0 || outputDelta < 0) revert Errors.InvalidMarketConfiguration();
        uint256 ethSpent = uint256(-int256(inputDelta));
        uint256 amountOut = uint256(int256(outputDelta));
        if (ethSpent != amountIn || amountOut == 0) revert Errors.BuybackNoExecution();
        IWETH9(market.weth).deposit{value: ethSpent}();
        manager.sync(Currency.wrap(market.weth));
        SafeTransferLib.safeTransfer(market.weth, address(manager), ethSpent);
        if (manager.settle() != ethSpent) revert Errors.BuybackNoExecution();
        manager.take(zeroForOne ? key.currency1 : key.currency0, address(this), amountOut);
        return abi.encode(ethSpent, amountOut);
    }
}
