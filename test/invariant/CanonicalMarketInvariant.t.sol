// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Round} from "../../src/shared/Types.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {PositionManagerTestSetup} from "../utils/PositionManagerTestSetup.sol";

interface IERC721OwnerView {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract CanonicalMarketHandler is Test {
    IPotatoToken internal immutable potato;
    IClaims internal immutable claims;
    IBuyback internal immutable buybacks;
    IPoolManager internal immutable manager;
    PoolSwapTest internal immutable swapRouter;
    BurntatoSwapFeeHook internal immutable hook;
    address internal immutable feeAddress;
    PoolKey internal key;
    address[3] internal actors;

    bool public transferBypass;
    bool public exactOutputBypass;
    bool public foreignPoolBypass;
    bool public treasuryRevenueDecreased;
    bool public feeMismatch;
    bool public buybackAccountingMismatch;
    uint256 public successfulBuys;
    uint256 public successfulSells;

    constructor(
        address diamond,
        IPoolManager manager_,
        PoolSwapTest swapRouter_,
        BurntatoSwapFeeHook hook_,
        PoolKey memory key_,
        address feeAddress_
    ) {
        potato = IPotatoToken(diamond);
        claims = IClaims(diamond);
        buybacks = IBuyback(diamond);
        manager = manager_;
        swapRouter = swapRouter_;
        hook = hook_;
        feeAddress = feeAddress_;
        key = key_;
        actors[0] = makeAddr("market-alice");
        actors[1] = makeAddr("market-bob");
        actors[2] = makeAddr("market-carol");
    }

    function buy(uint256 actorSeed, uint96 rawNativeIn) external {
        address trader = actors[actorSeed % actors.length];
        uint256 nativeIn = bound(uint256(rawNativeIn), 1e10, 0.0001 ether);
        vm.deal(trader, trader.balance + nativeIn);
        uint256 treasuryBefore = claims.treasuryEthAvailable();
        uint256 feeBefore = feeAddress.balance;
        uint256 potatoBefore = potato.balanceOf(trader);
        vm.recordLogs();
        vm.prank(trader);
        try swapRouter.swap{value: nativeIn}(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -int256(nativeIn), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) returns (
            BalanceDelta
        ) {
            ++successfulBuys;
            uint256 treasuryAfter = claims.treasuryEthAvailable();
            if (treasuryAfter < treasuryBefore) treasuryRevenueDecreased = true;
            (uint256 nativeFee, uint256 potatoFee) = _feeAccounting(vm.getRecordedLogs());
            uint256 bought = potato.balanceOf(trader) - potatoBefore;
            if (
                nativeFee != 0 || potatoFee != (bought + potatoFee) * 100 / 10_000 || treasuryAfter != treasuryBefore
                    || (potatoFee != 0 && feeAddress.balance <= feeBefore)
            ) feeMismatch = true;
        } catch {}
    }

    function sell(uint256 actorSeed, uint256 rawAmount) external {
        address trader = actors[actorSeed % actors.length];
        uint256 balance = potato.balanceOf(trader);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(trader);
        potato.approve(address(swapRouter), amount);
        uint256 treasuryBefore = claims.treasuryEthAvailable();
        uint256 feeBefore = feeAddress.balance;
        uint256 nativeBefore = trader.balance;
        vm.recordLogs();
        vm.prank(trader);
        try swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) returns (
            BalanceDelta
        ) {
            ++successfulSells;
            uint256 treasuryAfter = claims.treasuryEthAvailable();
            if (treasuryAfter < treasuryBefore) treasuryRevenueDecreased = true;
            (uint256 nativeFee, uint256 potatoFee) = _feeAccounting(vm.getRecordedLogs());
            uint256 received = trader.balance - nativeBefore;
            if (
                potatoFee != 0 || nativeFee != (received + nativeFee) * 100 / 10_000
                    || feeAddress.balance - feeBefore != nativeFee || treasuryAfter != treasuryBefore
            ) feeMismatch = true;
        } catch {}
    }

    function attemptWalletTransfer(uint256 actorSeed, uint256 rawAmount) external {
        address from = actors[actorSeed % actors.length];
        address to = actors[(actorSeed + 1) % actors.length];
        uint256 balance = potato.balanceOf(from);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(from);
        try potato.transfer(to, amount) returns (bool moved) {
            if (moved) transferBypass = true;
        } catch {}
    }

    function attemptDirectPoolManagerTransfer(uint256 actorSeed, uint256 rawAmount) external {
        address from = actors[actorSeed % actors.length];
        uint256 balance = potato.balanceOf(from);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(from);
        try potato.transfer(address(manager), amount) returns (bool moved) {
            if (moved) transferBypass = true;
        } catch {}
    }

    function attemptExactOutput(uint256 actorSeed, uint96 rawNativeBudget) external {
        address trader = actors[actorSeed % actors.length];
        uint256 budget = bound(uint256(rawNativeBudget), 1e10, 0.0001 ether);
        vm.deal(trader, trader.balance + budget);
        vm.prank(trader);
        try swapRouter.swap{value: budget}(
            key,
            SwapParams({zeroForOne: true, amountSpecified: int256(1), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) returns (
            BalanceDelta
        ) {
            exactOutputBypass = true;
        } catch {}
    }

    function attemptForeignPoolInitialization(uint160 rawPrice) external {
        PoolKey memory foreignKey = key;
        foreignKey.tickSpacing = 10;
        uint160 price = uint160(bound(uint256(rawPrice), TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1));
        try manager.initialize(foreignKey, price) returns (int24) {
            foreignPoolBypass = true;
        } catch {}
    }

    function executeBuyback() external {
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 treasuryPotatoBefore = potato.balanceOf(feeAddress);
        uint256 feeAddressBefore = feeAddress.balance;
        try buybacks.buyback() returns (uint256 amountOut) {
            uint256 reserveAfter = buybacks.buybackReserveEth();
            if (
                reserveAfter > reserveBefore || potato.balanceOf(feeAddress) - treasuryPotatoBefore != amountOut
                    || feeAddress.balance != feeAddressBefore || potato.transientPoolManagerAllowance() != 0
            ) buybackAccountingMismatch = true;
        } catch {}
    }

    function _feeAccounting(Vm.Log[] memory logs) internal view returns (uint256 nativeFee, uint256 potatoFee) {
        bytes32 feeTopic = keccak256("HookFee(bytes32,address,uint128,uint128)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == feeTopic) {
                (nativeFee, potatoFee) = abi.decode(logs[i].data, (uint128, uint128));
            }
        }
    }
}

contract CanonicalMarketInvariantTest is DiamondTestSetup, Deployers, PositionManagerTestSetup {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    CanonicalMarketHandler internal handler;
    BurntatoSwapFeeHook internal hook;
    IMarket internal market;
    IGame internal game;
    IRecovery internal recovery;
    ISettlement internal settlement;
    IPotatoToken internal potato;
    IClaims internal claims;
    uint256 internal treasuryFloor;

    function setUp() public {
        deployFreshManagerAndRouters();
        _deployPositionManager(IPoolManager(address(manager)));
        _deployCore();
        _deployHook();

        market = IMarket(address(diamond));
        game = IGame(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        potato = IPotatoToken(address(diamond));
        claims = IClaims(address(diamond));

        vm.prank(authority);
        market.configureMarket(
            IMarket.MarketConfig({
                hook: address(hook),
                poolManager: address(manager),
                positionManager: address(positionManager),
                permit2: PERMIT2_ADDRESS,
                sqrtPriceX96: TickMath.getSqrtPriceAtTick(69_060),
                tickLower: TickMath.minUsableTick(60),
                tickUpper: 69_060,
                tickSpacing: 60,
                potatoSeed: 1 ether
            })
        );
        _createTreasuryInventory();
        market.launchMarket();
        vm.prank(authority);
        hook.setExternalBuysEnabled(true);
        treasuryFloor = claims.treasuryEthAvailable();

        PoolKey memory canonicalKey = market.canonicalPoolKey();
        handler = new CanonicalMarketHandler(
            address(diamond), IPoolManager(address(manager)), swapRouter, hook, canonicalKey, treasury
        );
        handler.buy(0, 0.0001 ether);
        handler.sell(0, type(uint256).max);
        targetContract(address(handler));
    }

    function invariant_MarketRemainsCanonicalLockedAndTreasuryOnly() public view {
        (,, bool launching, bool launched) = market.marketState();
        assertFalse(launching);
        assertTrue(launched);
        assertEq(IERC721OwnerView(address(positionManager)).ownerOf(1), market.lockedLpRecipient());
        assertEq(positionManager.nextTokenId(), 2);
        assertEq(address(hook).balance, 0);
        assertEq(potato.transientPoolManagerAllowance(), 0);
        assertGe(claims.treasuryEthAvailable(), treasuryFloor);
        assertFalse(handler.treasuryRevenueDecreased());
        assertFalse(handler.feeMismatch());
        assertFalse(handler.buybackAccountingMismatch());
        assertGt(handler.successfulBuys(), 0);
        assertGt(handler.successfulSells(), 0);
    }

    function invariant_UnsupportedSettlementPathsNeverOpen() public view {
        assertFalse(handler.transferBypass());
        assertFalse(handler.exactOutputBypass());
        assertFalse(handler.foreignPoolBypass());
    }

    function _deployHook() internal {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory constructorArgs =
            abi.encode(manager, authority, address(diamond), treasury, uint16(100), int24(60));
        (address expected, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BurntatoSwapFeeHook).creationCode, constructorArgs);
        vm.prank(CREATE2_DEPLOYER);
        hook = new BurntatoSwapFeeHook{salt: salt}(
            IPoolManager(address(manager)), authority, address(diamond), treasury, 100, 60
        );
        assertEq(address(hook), expected);
    }

    function _createTreasuryInventory() internal {
        address alice = makeAddr("seed-alice");
        address bob = makeAddr("seed-bob");
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(vm.getBlockTimestamp() + 120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();
        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();
        _expireAndSettle();
        vm.deal(address(manager), 100 ether);
    }

    function _expireAndSettle() internal {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        settlement.settleRound();
    }
}
