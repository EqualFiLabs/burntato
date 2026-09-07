// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IBuyback} from "../interfaces/IBuyback.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibMath} from "../libraries/LibMath.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";
import {BuybackConfig} from "../shared/Types.sol";

contract BuybackFacet is IBuyback {
    using BalanceDeltaLibrary for BalanceDelta;

    modifier nonReentrant() {
        LibProtocolStorage.ReentrancyStorage storage rs = LibProtocolStorage.reentrancy();
        if (rs.status == 2) revert Errors.Reentrancy();
        rs.status = 2;
        _;
        rs.status = 1;
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

    function buybackReserveEth() external view returns (uint256) {
        return LibProtocolStorage.buyback().reserveEth;
    }

    function lastBuybackBlock() external view returns (uint256) {
        return LibProtocolStorage.buyback().lastBuybackBlock;
    }

    function buyback() external nonReentrant returns (uint256 amountOut) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        if (!ms.launched) revert Errors.MarketNotLaunched();

        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        BuybackConfig memory config = bs.config;
        if (config.callerRewardBps > Constants.MAX_BUYBACK_CALLER_REWARD_BPS) revert Errors.InvalidBps();
        uint256 reserve = bs.reserveEth;
        if (reserve == 0 || config.maxSpend == 0) revert Errors.BuybackUnavailable();

        if (config.delayBlocks > type(uint256).max - bs.lastBuybackBlock) {
            revert Errors.BuybackTooSoon(type(uint256).max);
        }
        uint256 nextBlock = bs.lastBuybackBlock + config.delayBlocks;
        if (block.number < nextBlock) revert Errors.BuybackTooSoon(nextBlock);

        uint256 grossSlice = reserve < config.maxSpend ? reserve : config.maxSpend;
        uint256 requestedInput = Math.mulDiv(grossSlice, Constants.BPS, Constants.BPS + uint256(config.callerRewardBps));
        if (requestedInput > uint256(type(int256).max)) revert Errors.InvalidMarketConfiguration();
        bs.reserveEth = reserve - grossSlice;
        bs.lastBuybackBlock = block.number;

        uint256 ethSpent;
        address treasuryRecipient = LibProtocolStorage.treasury().recipient;
        if (requestedInput != 0) {
            bytes memory result = IPoolManager(ms.poolManager).unlock(abi.encode(requestedInput, treasuryRecipient));
            (ethSpent, amountOut) = abi.decode(result, (uint256, uint256));
        }
        if (ethSpent == 0 || amountOut == 0) revert Errors.BuybackNoExecution();

        uint256 callerReward = LibMath.mulBpsDown(ethSpent, config.callerRewardBps);
        bs.reserveEth += grossSlice - ethSpent - callerReward;
        if (callerReward != 0) SafeTransferLib.forceSafeTransferETH(msg.sender, callerReward);
        emit BuybackExecuted(
            msg.sender, treasuryRecipient, grossSlice, ethSpent, amountOut, callerReward, bs.reserveEth
        );
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        if (msg.sender != ms.poolManager || msg.sender == address(0)) revert Errors.InvalidAddress();
        (uint256 amountIn, address treasuryRecipient) = abi.decode(data, (uint256, address));

        IPoolManager manager = IPoolManager(ms.poolManager);
        PoolKey memory key = _poolKey(ms);
        BalanceDelta delta = manager.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );

        int128 nativeDelta = delta.amount0();
        int128 potatoDelta = delta.amount1();
        if (nativeDelta > 0 || potatoDelta < 0) revert Errors.InvalidMarketConfiguration();
        uint256 ethSpent = uint256(-int256(nativeDelta));
        uint256 amountOut = uint256(int256(potatoDelta));
        if (ethSpent > amountIn) revert Errors.InvalidMarketConfiguration();

        if (ethSpent != 0) manager.settle{value: ethSpent}();
        if (amountOut != 0) manager.take(key.currency1, treasuryRecipient, amountOut);
        return abi.encode(ethSpent, amountOut);
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
}
