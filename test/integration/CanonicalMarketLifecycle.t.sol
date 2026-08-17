// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Vm} from "forge-std/Vm.sol";

import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {Round} from "../../src/shared/Types.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {PositionManagerTestSetup} from "../utils/PositionManagerTestSetup.sol";

interface IERC721Owner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract CanonicalHookConfigStub {
    address public immutable token;
    IPoolManager public immutable poolManager;
    int24 public immutable tickSpacing;

    constructor(address token_, IPoolManager poolManager_, int24 tickSpacing_) {
        token = token_;
        poolManager = poolManager_;
        tickSpacing = tickSpacing_;
    }
}

contract CanonicalMarketLifecycleTest is DiamondTestSetup, Deployers, PositionManagerTestSetup {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    int24 internal constant TICK_SPACING = 60;
    int24 internal constant INITIAL_TICK = 69_060;
    uint256 internal constant NATIVE_SEED = 0.004 ether;
    uint256 internal constant POTATO_SEED = 1 ether;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    BurntatoSwapFeeHook internal hook;
    IClaims internal claims;
    IGame internal game;
    IMarket internal market;
    IPotatoToken internal potato;
    IRecovery internal recovery;
    ISettlement internal settlement;

    function setUp() public {
        deployFreshManagerAndRouters();
        _deployPositionManager(IPoolManager(address(manager)));
        _deployCore();

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory constructorArgs =
            abi.encode(manager, authority, address(diamond), treasury, uint16(100), int24(TICK_SPACING));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BurntatoSwapFeeHook).creationCode, constructorArgs);
        vm.prank(CREATE2_DEPLOYER);
        hook = new BurntatoSwapFeeHook{salt: salt}(
            IPoolManager(address(manager)), authority, address(diamond), treasury, 100, TICK_SPACING
        );
        assertEq(address(hook), hookAddress);

        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        market = IMarket(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));

        vm.prank(authority);
        market.configureMarket(
            IMarket.MarketConfig({
                hook: address(hook),
                poolManager: address(manager),
                positionManager: address(positionManager),
                permit2: PERMIT2_ADDRESS,
                sqrtPriceX96: TickMath.getSqrtPriceAtTick(INITIAL_TICK),
                tickLower: TickMath.minUsableTick(TICK_SPACING),
                tickUpper: TickMath.maxUsableTick(TICK_SPACING),
                tickSpacing: TICK_SPACING,
                nativeSeed: NATIVE_SEED,
                potatoSeed: POTATO_SEED
            })
        );
        key = market.canonicalPoolKey();

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(address(manager), 100 ether);
    }

    function test_RecoveryRevenuePermissionlesslyLaunchesLockedTwoSidedLiquidity() public {
        _createTreasuryInventory();
        assertTrue(market.marketReady());

        vm.prank(keeper);
        (bytes32 poolId, uint128 liquidity) = market.launchMarket();

        (bytes32 storedPoolId,, bool launching, bool launched) = market.marketState();
        assertEq(storedPoolId, poolId);
        assertGt(liquidity, 0);
        assertFalse(launching);
        assertTrue(launched);
        assertEq(IERC721Owner(address(positionManager)).ownerOf(1), market.lockedLpRecipient());
        assertEq(market.lockedLpRecipient(), 0x000000000000000000000000000000000000dEaD);
        assertEq(address(positionManager).balance, 0);
        assertGt(claims.treasuryEthAvailable(), 0);
    }

    function test_RealBuyAndSellRouteBothOnePercentFeesDirectlyToTreasury() public {
        _createTreasuryInventory();
        market.launchMarket();
        uint256 claimableBefore = claims.treasuryEthAvailable();
        uint256 treasuryBefore = treasury.balance;
        uint256 diamondBefore = address(diamond).balance;

        vm.recordLogs();
        uint256 bought = _buy(alice, 0.0001 ether);
        Vm.Log[] memory buyLogs = vm.getRecordedLogs();
        (uint256 nativeBuyFee, uint256 potatoBuyFee) = _feeAccounting(buyLogs);
        assertGt(bought, 0);
        assertEq(nativeBuyFee, 0);
        assertEq(potatoBuyFee, (bought + potatoBuyFee) * 100 / 10_000);
        assertGt(treasury.balance, treasuryBefore);
        uint256 treasuryAfterBuy = treasury.balance;
        assertEq(claims.treasuryEthAvailable(), claimableBefore);
        assertEq(address(diamond).balance, diamondBefore);
        assertEq(address(hook).balance, 0);

        vm.prank(alice);
        potato.approve(address(swapRouter), type(uint256).max);
        uint256 nativeBefore = alice.balance;
        vm.recordLogs();
        _sell(alice, bought / 2);
        Vm.Log[] memory sellLogs = vm.getRecordedLogs();
        (uint256 nativeSellFee, uint256 potatoSellFee) = _feeAccounting(sellLogs);
        uint256 nativeReceived = alice.balance - nativeBefore;
        assertGt(nativeReceived, 0);
        assertEq(potatoSellFee, 0);
        assertEq(nativeSellFee, (nativeReceived + nativeSellFee) * 100 / 10_000);
        assertEq(treasury.balance - treasuryAfterBuy, nativeSellFee);
        assertEq(claims.treasuryEthAvailable(), claimableBefore);
        assertEq(address(diamond).balance, diamondBefore);
        assertEq(address(hook).balance, 0);
        assertEq(potato.transientPoolManagerAllowance(), 0);
        assertEq(positionManager.nextTokenId(), 2);
    }

    function test_ConfiguredReservesCannotBeClaimedAndStillLaunchAfterExcessClaims() public {
        _createTreasuryInventory();
        assertEq(claims.treasuryEthAvailable(), 0.001 ether);
        assertEq(claims.treasuryPotatoAvailable(), 999 ether);

        claims.claimTreasury();
        claims.claimTreasuryPotato();
        assertTrue(market.marketReady());
        market.launchMarket();
        assertGt(claims.treasuryEthAvailable(), 0);
        assertLt(claims.treasuryPotatoAvailable(), 0.003 ether);
    }

    function test_MarketConfigurationCanChangeBeforeLaunchButNotAfter() public {
        IMarket.MarketConfig memory config = market.marketConfig();
        config.nativeSeed = 0.003 ether;
        config.potatoSeed = 2 ether;
        vm.prank(authority);
        market.configureMarket(config);
        IMarket.MarketConfig memory actual = market.marketConfig();
        assertEq(actual.nativeSeed, 0.003 ether);
        assertEq(actual.potatoSeed, 2 ether);

        _createTreasuryInventory();
        market.launchMarket();
        vm.prank(authority);
        vm.expectRevert(Errors.AlreadyLaunched.selector);
        market.configureMarket(config);
    }

    function test_FeeAdministrationRemainsAvailableAfterDiamondFinalization() public {
        _createTreasuryInventory();
        market.launchMarket();

        vm.prank(authority);
        IGovernance(address(diamond)).finalizeProtocol();
        address nextTreasury = makeAddr("nextTreasury");
        vm.startPrank(authority);
        hook.setFeeAddress(nextTreasury);
        hook.setFeeBps(500);
        vm.stopPrank();

        uint256 originalBefore = treasury.balance;
        _buy(alice, 0.0001 ether);
        assertGt(nextTreasury.balance, 0);
        assertEq(treasury.balance, originalBefore);
        assertEq(hook.feeAddress(), nextTreasury);
        assertEq(hook.feeBps(), 500);
    }

    function test_HookSupportsZeroAndFullBilateralFees() public {
        vm.prank(authority);
        hook.setFeeBps(0);
        _createTreasuryInventory();
        market.launchMarket();

        uint256 treasuryBefore = treasury.balance;
        uint256 bought = _buy(alice, 0.0001 ether);
        assertGt(bought, 0);
        assertEq(treasury.balance, treasuryBefore);

        vm.prank(authority);
        hook.setFeeBps(10_000);
        vm.prank(alice);
        potato.approve(address(swapRouter), bought);
        uint256 aliceBefore = alice.balance;
        _sell(alice, bought / 2);
        assertEq(alice.balance, aliceBefore);
        assertGt(treasury.balance, treasuryBefore);
    }

    function test_OnlyHookOwnerCanConfigureRevenueCapture() public {
        vm.prank(alice);
        vm.expectRevert();
        hook.setFeeAddress(alice);
        vm.prank(alice);
        vm.expectRevert();
        hook.setFeeBps(500);

        vm.prank(authority);
        vm.expectRevert(Errors.InvalidBps.selector);
        hook.setFeeBps(10_001);
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setFeeAddress(address(0));
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setFeeAddress(address(hook));
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setFeeAddress(address(diamond));
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setFeeAddress(address(manager));
    }

    function test_ConfigurationRejectsTickSpacingOutsidePoolManagerDomain() public {
        _deployCore();
        IMarket candidate = IMarket(address(diamond));
        CanonicalHookConfigStub stub = new CanonicalHookConfigStub(
            address(diamond), IPoolManager(address(manager)), TickMath.MAX_TICK_SPACING + 1
        );

        vm.prank(authority);
        vm.expectRevert(Errors.InvalidMarketConfiguration.selector);
        candidate.configureMarket(
            IMarket.MarketConfig({
                hook: address(stub),
                poolManager: address(manager),
                positionManager: address(positionManager),
                permit2: PERMIT2_ADDRESS,
                sqrtPriceX96: TickMath.getSqrtPriceAtTick(0),
                tickLower: -655_360,
                tickUpper: 655_360,
                tickSpacing: TickMath.MAX_TICK_SPACING + 1,
                nativeSeed: NATIVE_SEED,
                potatoSeed: POTATO_SEED
            })
        );
    }

    function test_ConfigurationRejectsTreasuryRecipientAsSystemCustody() public {
        _deployCore();
        IMarket candidate = IMarket(address(diamond));
        CanonicalHookConfigStub stub =
            new CanonicalHookConfigStub(address(diamond), IPoolManager(address(manager)), TICK_SPACING);
        vm.startPrank(authority);
        IGovernance(address(diamond)).setTreasuryRecipient(address(manager));
        vm.expectRevert(Errors.InvalidMarketConfiguration.selector);
        candidate.configureMarket(
            IMarket.MarketConfig({
                hook: address(stub),
                poolManager: address(manager),
                positionManager: address(positionManager),
                permit2: PERMIT2_ADDRESS,
                sqrtPriceX96: TickMath.getSqrtPriceAtTick(INITIAL_TICK),
                tickLower: TickMath.minUsableTick(TICK_SPACING),
                tickUpper: TickMath.maxUsableTick(TICK_SPACING),
                tickSpacing: TICK_SPACING,
                nativeSeed: NATIVE_SEED,
                potatoSeed: POTATO_SEED
            })
        );
        vm.stopPrank();
    }

    function test_RejectsForeignInitializationExactOutputAndRepeatedLaunch() public {
        PoolKey memory foreignKey = key;
        foreignKey.tickSpacing = 10;
        vm.expectRevert();
        manager.initialize(foreignKey, TickMath.getSqrtPriceAtTick(INITIAL_TICK));

        _createTreasuryInventory();
        market.launchMarket();
        vm.expectRevert(Errors.AlreadyLaunched.selector);
        market.launchMarket();

        vm.prank(alice);
        vm.expectRevert();
        swapRouter.swap{value: 0.0001 ether}(
            key,
            SwapParams({zeroForOne: true, amountSpecified: int256(1 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
    }

    function test_TransientAuthorizationCannotBeReusedForDirectPoolMovement() public {
        _createTreasuryInventory();
        market.launchMarket();
        uint256 bought = _buy(alice, 0.0001 ether);
        assertEq(potato.transientPoolManagerAllowance(), 0);

        vm.prank(alice);
        potato.approve(address(this), bought);
        vm.expectRevert(abi.encodeWithSelector(Errors.PoolManagerAllowanceExceeded.selector, 0, bought));
        potato.transferFrom(alice, address(manager), bought);
    }

    function test_TransientAuthorizationAggregatesWithinOneTransaction() public {
        _createTreasuryInventory();
        market.launchMarket();

        vm.startPrank(address(hook));
        potato.authorizePoolManagerTransfer(1);
        potato.authorizePoolManagerTransfer(2);
        vm.stopPrank();
        assertEq(potato.transientPoolManagerAllowance(), 3);

        vm.prank(address(manager));
        potato.transfer(alice, 3);
        assertEq(potato.transientPoolManagerAllowance(), 0);
    }

    function test_GuardianPauseCannotDisableCanonicalMarketSettlement() public {
        _createTreasuryInventory();
        market.launchMarket();
        vm.prank(guardian);
        IGovernance(address(diamond)).setPauseState(true, true);

        uint256 bought = _buy(alice, 0.0001 ether);
        assertGt(bought, 0);
        vm.prank(alice);
        potato.approve(address(swapRouter), bought);
        uint256 nativeBefore = alice.balance;
        _sell(alice, bought);
        assertGt(alice.balance, nativeBefore);
    }

    function _createTreasuryInventory() internal {
        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(block.timestamp + 120);
        game.materializeMaturedEmission();
        vm.prank(alice);
        recovery.commitRecovery(10_000 ether);
        _expireAndSettle();

        vm.prank(bob);
        game.buyPotato{value: 0.01 ether}();
        _expireAndSettle();
        assertEq(potato.balanceOf(address(diamond)), 1_000 ether);
    }

    function _expireAndSettle() internal {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        settlement.settleRound();
    }

    function _buy(address buyer, uint256 nativeIn) internal returns (uint256 bought) {
        uint256 beforeBalance = potato.balanceOf(buyer);
        vm.prank(buyer);
        swapRouter.swap{value: nativeIn}(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(nativeIn), sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        bought = potato.balanceOf(buyer) - beforeBalance;
    }

    function _sell(address seller, uint256 amount) internal {
        vm.prank(seller);
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: MAX_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
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
