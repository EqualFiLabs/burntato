// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

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

contract BurntatoSwapFeeHook is BaseHook, Ownable {
    using BalanceDeltaLibrary for BalanceDelta;

    address public immutable token;
    int24 public immutable tickSpacing;
    address public feeAddress;
    uint16 public feeBps;
    uint64 public deploymentBlock;

    event FeeAddressSet(address indexed feeAddress);
    event FeeBpsSet(uint16 feeBps);
    event PoolLaunched(bytes32 indexed poolId, uint256 deploymentBlock);
    event HookFee(bytes32 indexed poolId, address indexed sender, uint128 nativeFee, uint128 potatoFee);
    event Trade(bytes32 indexed poolId, address indexed sender, int128 nativeDelta, int128 potatoDelta);

    constructor(
        IPoolManager manager,
        address owner_,
        address token_,
        address feeAddress_,
        uint16 feeBps_,
        int24 tickSpacing_
    ) BaseHook(manager) {
        if (owner_ == address(0) || token_ == address(0)) {
            revert Errors.InvalidAddress();
        }
        _validateFeeAddress(feeAddress_, token_, address(manager));
        if (feeBps_ > Constants.BPS) revert Errors.InvalidBps();
        _initializeOwner(owner_);
        token = token_;
        feeAddress = feeAddress_;
        feeBps = feeBps_;
        tickSpacing = tickSpacing_;
    }

    function setFeeAddress(address newFeeAddress) external onlyOwner {
        _validateFeeAddress(newFeeAddress, token, address(poolManager));
        feeAddress = newFeeAddress;
        emit FeeAddressSet(newFeeAddress);
    }

    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > Constants.BPS) revert Errors.InvalidBps();
        feeBps = newFeeBps;
        emit FeeBpsSet(newFeeBps);
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
        IMarket.MarketConfig memory config = IMarket(token).marketConfig();
        if (!IMarket(token).marketLaunching() || sqrtPriceX96 != config.sqrtPriceX96) {
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
        if (!IMarket(token).marketLaunching()) revert Errors.MarketNotLaunching();
        int128 potatoDelta = delta.amount1();
        if (potatoDelta < 0) {
            IPotatoToken(token).authorizePoolManagerTransfer(uint256(-int256(potatoDelta)));
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
        int128 signedSwapAmount = specifiedTokenIs0 ? delta.amount1() : delta.amount0();
        uint256 swapAmount =
            signedSwapAmount < 0 ? uint256(-int256(signedSwapAmount)) : uint256(uint128(signedSwapAmount));

        uint256 allowanceForRouter;
        if (params.zeroForOne) {
            feeDelta = _handleBuy(key, swapAmount, sender);
            allowanceForRouter = swapAmount - uint256(uint128(feeDelta));
        } else {
            feeDelta = _handleSell(key, swapAmount, sender);
            allowanceForRouter = uint256(-int256(delta.amount1()));
        }
        if (allowanceForRouter != 0) {
            IPotatoToken(token).authorizePoolManagerTransfer(allowanceForRouter);
        }

        emit Trade(PoolId.unwrap(key.toId()), sender, delta.amount0(), delta.amount1());
        return (BaseHook.afterSwap.selector, feeDelta);
    }

    function _handleBuy(PoolKey calldata key, uint256 grossPotatoOut, address sender)
        private
        returns (int128 feeDelta)
    {
        uint256 fee = grossPotatoOut * feeBps / Constants.BPS;
        if (fee == 0) return 0;
        if (fee > uint256(uint128(type(int128).max))) revert Errors.InvalidMarketConfiguration();

        IPotatoToken(token).authorizePoolManagerTransfer(fee);
        poolManager.take(key.currency1, address(this), fee);
        emit HookFee(PoolId.unwrap(key.toId()), sender, 0, uint128(fee));

        uint256 nativeReceived = _swapPotatoToNative(key, fee);
        if (nativeReceived != 0) SafeTransferLib.forceSafeTransferETH(feeAddress, nativeReceived);
        return int128(uint128(fee));
    }

    function _handleSell(PoolKey calldata key, uint256 grossNativeOut, address sender)
        private
        returns (int128 feeDelta)
    {
        uint256 fee = grossNativeOut * feeBps / Constants.BPS;
        if (fee == 0) return 0;
        if (fee > uint256(uint128(type(int128).max))) revert Errors.InvalidMarketConfiguration();

        poolManager.take(key.currency0, address(this), fee);
        emit HookFee(PoolId.unwrap(key.toId()), sender, uint128(fee), 0);
        SafeTransferLib.forceSafeTransferETH(feeAddress, fee);
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

        uint256 potatoToSettle = uint256(-int256(delta.amount1()));
        if (potatoToSettle != 0) {
            IPotatoToken(token).authorizePoolManagerTransfer(potatoToSettle);
            poolManager.sync(key.currency1);
            if (!IPotatoToken(token).transfer(address(poolManager), potatoToSettle)) {
                revert Errors.TokenOperationFailed();
            }
            poolManager.settle();
        }
        uint256 nativeToTake = uint256(int256(delta.amount0()));
        if (nativeToTake != 0) poolManager.take(key.currency0, address(this), nativeToTake);
        nativeReceived = address(this).balance - nativeBefore;
    }

    function _validateKey(PoolKey calldata key) private view {
        if (
            !key.currency0.isAddressZero() || Currency.unwrap(key.currency1) != token
                || address(key.hooks) != address(this) || key.fee != Constants.POOL_LP_FEE
                || key.tickSpacing != tickSpacing
        ) revert Errors.InvalidMarketConfiguration();
    }

    function _validateFeeAddress(address candidate, address token_, address manager_) private view {
        if (candidate == address(0) || candidate == address(this) || candidate == token_ || candidate == manager_) {
            revert Errors.InvalidAddress();
        }
    }

    receive() external payable {}
}
