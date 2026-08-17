// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {IMarket} from "../interfaces/IMarket.sol";
import {IPotatoToken} from "../interfaces/IPotatoToken.sol";
import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";

contract BurntatoSwapFeeHook is BaseHook {
    using BalanceDeltaLibrary for BalanceDelta;

    address public immutable treasury;
    uint64 public deploymentBlock;

    event PoolLaunched(bytes32 indexed poolId, uint256 deploymentBlock);
    event HookFee(bytes32 indexed poolId, address indexed sender, uint128 nativeFee, uint128 potatoFee);
    event Trade(bytes32 indexed poolId, address indexed sender, int128 nativeDelta, int128 potatoDelta);

    constructor(IPoolManager manager, address treasury_) BaseHook(manager) {
        if (treasury_ == address(0)) revert Errors.InvalidAddress();
        treasury = treasury_;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96) internal override returns (bytes4) {
        _validateKey(key);
        IMarket.MarketConfig memory config = IMarket(treasury).marketConfig();
        if (!IMarket(treasury).marketLaunching() || sqrtPriceX96 != config.sqrtPriceX96) {
            revert Errors.MarketNotLaunching();
        }
        if (deploymentBlock != 0) revert Errors.PoolAlreadyInitialized();
        deploymentBlock = uint64(block.number);
        emit PoolLaunched(PoolId.unwrap(key.toId()), block.number);
        return BaseHook.beforeInitialize.selector;
    }

    function _afterAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, BalanceDelta) {
        _validateKey(key);
        if (!IMarket(treasury).marketLaunching()) revert Errors.MarketNotLaunching();
        int128 potatoDelta = delta.amount1();
        if (potatoDelta < 0) {
            IPotatoToken(treasury).authorizePoolManagerTransfer(uint256(int256(-potatoDelta)));
        }
        return (BaseHook.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128 feeDelta) {
        _validateKey(key);
        if (sender == address(this)) return (BaseHook.afterSwap.selector, 0);
        if (params.amountSpecified > 0) revert Errors.ExactOutputNotAllowed();

        bool specifiedTokenIs0 = (params.amountSpecified < 0 == params.zeroForOne);
        int128 swapAmount = specifiedTokenIs0 ? delta.amount1() : delta.amount0();
        if (swapAmount < 0) swapAmount = -swapAmount;

        uint256 allowanceForRouter;
        if (params.zeroForOne) {
            feeDelta = _handleBuy(key, uint128(swapAmount), sender);
            allowanceForRouter = uint256(uint128(swapAmount)) - uint256(uint128(feeDelta));
        } else {
            feeDelta = _handleSell(key, uint128(swapAmount), sender);
            allowanceForRouter = uint256(int256(-delta.amount1()));
        }
        if (allowanceForRouter != 0) {
            IPotatoToken(treasury).authorizePoolManagerTransfer(allowanceForRouter);
        }

        emit Trade(PoolId.unwrap(key.toId()), sender, delta.amount0(), delta.amount1());
        return (BaseHook.afterSwap.selector, feeDelta);
    }

    function _handleBuy(PoolKey calldata key, uint128 grossPotatoOut, address sender)
        private
        returns (int128 feeDelta)
    {
        uint256 fee = uint256(grossPotatoOut) * Constants.HOOK_FEE_BPS / Constants.BPS;
        if (fee == 0) return 0;

        IPotatoToken(treasury).authorizePoolManagerTransfer(fee);
        poolManager.take(key.currency1, address(this), fee);
        emit HookFee(PoolId.unwrap(key.toId()), sender, 0, uint128(fee));

        uint256 nativeReceived = _swapPotatoToNative(key, fee);
        if (nativeReceived != 0) _recordRevenue(nativeReceived);
        return int128(uint128(fee));
    }

    function _handleSell(PoolKey calldata key, uint128 grossNativeOut, address sender)
        private
        returns (int128 feeDelta)
    {
        uint256 fee = uint256(grossNativeOut) * Constants.HOOK_FEE_BPS / Constants.BPS;
        if (fee == 0) return 0;

        poolManager.take(key.currency0, address(this), fee);
        emit HookFee(PoolId.unwrap(key.toId()), sender, uint128(fee), 0);
        _recordRevenue(fee);
        return int128(uint128(fee));
    }

    function _swapPotatoToNative(PoolKey memory key, uint256 amount) private returns (uint256 nativeReceived) {
        uint256 nativeBefore = address(this).balance;
        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );

        uint256 potatoToSettle = uint256(int256(-delta.amount1()));
        if (potatoToSettle != 0) {
            IPotatoToken(treasury).authorizePoolManagerTransfer(potatoToSettle);
            poolManager.sync(key.currency1);
            IPotatoToken(treasury).transfer(address(poolManager), potatoToSettle);
            poolManager.settle();
        }
        uint256 nativeToTake = uint256(int256(delta.amount0()));
        if (nativeToTake != 0) poolManager.take(key.currency0, address(this), nativeToTake);
        nativeReceived = address(this).balance - nativeBefore;
    }

    function _recordRevenue(uint256 amount) private {
        IMarket(treasury).recordHookRevenue{value: amount}();
    }

    function _validateKey(PoolKey calldata key) private view {
        IMarket.MarketConfig memory config = IMarket(treasury).marketConfig();
        if (
            !key.currency0.isAddressZero() || Currency.unwrap(key.currency1) != treasury
                || address(key.hooks) != address(this) || key.fee != Constants.POOL_LP_FEE
                || key.tickSpacing != config.tickSpacing || config.hook != address(this)
                || config.poolManager != address(poolManager)
        ) revert Errors.InvalidMarketConfiguration();
    }

    receive() external payable {}
}
