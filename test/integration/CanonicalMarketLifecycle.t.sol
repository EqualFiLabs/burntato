// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Vm} from "forge-std/Vm.sol";

import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {BuybackConfig, FacetCut, FacetCutAction, Round} from "../../src/shared/Types.sol";
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

contract ForceNativeIntoPositionManager {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract FalseApproveFacet {
    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract NativeFeeReceiver {
    receive() external payable {}
}

contract IntegrationOperatorCollection {
    address public activationRegistry;
    bool public constant launchFinalized = true;
    mapping(uint256 operatorId => address owner) public ownerOf;

    function configure(address registry, uint256 operatorId, address owner) external {
        activationRegistry = registry;
        ownerOf[operatorId] = owner;
    }
}

contract IntegrationActivationRegistry {
    address public genesisCollection;
    mapping(uint256 operatorId => uint16 weight) public multiplierBps;

    function configure(address collection, uint256 operatorId, uint16 weight) external {
        genesisCollection = collection;
        multiplierBps[operatorId] = weight;
    }
}

contract CanonicalMarketLifecycleTest is DiamondTestSetup, Deployers, PositionManagerTestSetup {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    int24 internal constant TICK_SPACING = 60;
    int24 internal constant INITIAL_TICK = 69_060;
    uint256 internal constant POTATO_SEED = 1 ether;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal keeper = makeAddr("keeper");

    BurntatoSwapFeeHook internal hook;
    IBuyback internal buybacks;
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
        bytes memory constructorArgs = abi.encode(
            manager, authority, address(diamond), treasury, uint16(100), address(0), uint16(0), int24(TICK_SPACING)
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BurntatoSwapFeeHook).creationCode, constructorArgs);
        vm.prank(CREATE2_DEPLOYER);
        hook = new BurntatoSwapFeeHook{salt: salt}(
            IPoolManager(address(manager)), authority, address(diamond), treasury, 100, address(0), 0, TICK_SPACING
        );
        assertEq(address(hook), hookAddress);

        claims = IClaims(address(diamond));
        buybacks = IBuyback(address(diamond));
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
                tickUpper: INITIAL_TICK,
                tickSpacing: TICK_SPACING,
                potatoSeed: POTATO_SEED
            })
        );
        key = market.canonicalPoolKey();

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(address(manager), 100 ether);
    }

    function test_GenesisSupplyPermissionlesslyLaunchesLockedSingleSidedLiquidity() public {
        assertTrue(market.marketReady());
        uint256 treasuryEthBefore = claims.treasuryEthAvailable();
        uint256 diamondEthBefore = address(diamond).balance;

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
        assertEq(claims.treasuryEthAvailable(), treasuryEthBefore);
        assertEq(address(diamond).balance, diamondEthBefore);
        assertLe(potato.balanceOf(address(diamond)), 10);
    }

    function test_ForcedPositionManagerEthDoesNotCorruptLaunchAccounting() public {
        _createTreasuryInventory();
        uint256 treasuryBefore = claims.treasuryEthAvailable();
        uint256 forcedNative = 1 ether;
        vm.deal(address(this), forcedNative);
        new ForceNativeIntoPositionManager{value: forcedNative}(payable(address(positionManager)));
        assertEq(address(positionManager).balance, forcedNative);

        market.launchMarket();

        assertEq(address(positionManager).balance, forcedNative);
        assertEq(claims.treasuryEthAvailable(), treasuryBefore);
    }

    function test_LaunchRevertsWhenPotatoApprovalReturnsFalse() public {
        _createTreasuryInventory();
        _replaceSelector(address(new FalseApproveFacet()), IPotatoToken.approve.selector);

        vm.expectRevert(Errors.TokenOperationFailed.selector);
        market.launchMarket();
    }

    function test_BuyFeeConversionRevertsWhenPotatoTransferReturnsFalse() public {
        _createTreasuryInventory();
        market.launchMarket();
        _setExternalBuys(true);
        uint256 snapshot = vm.snapshotState();

        vm.recordLogs();
        _buy(alice, 0.0001 ether);
        (, uint256 potatoFee) = _feeAccounting(vm.getRecordedLogs());
        assertGt(potatoFee, 0);
        assertTrue(vm.revertToStateAndDelete(snapshot));

        vm.mockCall(
            address(diamond), abi.encodeCall(IPotatoToken.transfer, (address(manager), potatoFee)), abi.encode(false)
        );
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.afterSwap.selector,
                abi.encodeWithSelector(Errors.TokenOperationFailed.selector),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );
        swapRouter.swap{value: 0.0001 ether}(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(0.0001 ether), sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        vm.clearMockedCalls();
    }

    function test_RealBuyAndSellRouteBothOnePercentFeesDirectlyToTreasury() public {
        _createTreasuryInventory();
        market.launchMarket();
        _setExternalBuys(true);
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

    function test_RealBuyAndSellSplitExistingFeeWithOperatorRouter() public {
        NativeFeeReceiver operatorRouter = new NativeFeeReceiver();
        vm.prank(authority);
        hook.setOperatorRewards(address(operatorRouter), 4_000);
        _createTreasuryInventory();
        market.launchMarket();
        _setExternalBuys(true);

        uint256 operatorBefore = address(operatorRouter).balance;
        uint256 treasuryBefore = treasury.balance;
        uint256 buybackOperatorBefore = address(operatorRouter).balance;
        vm.prank(keeper);
        assertGt(buybacks.buyback(), 0);
        assertEq(address(operatorRouter).balance, buybackOperatorBefore);

        vm.recordLogs();
        uint256 bought = _buy(alice, 0.0001 ether);
        (uint256 buyNativeFee, uint256 buyOperatorAmount, uint256 buyTreasuryAmount) =
            _feeAllocation(vm.getRecordedLogs());
        assertGt(buyNativeFee, 0);
        assertEq(buyOperatorAmount, buyNativeFee * 4_000 / 10_000);
        assertEq(buyTreasuryAmount, buyNativeFee - buyOperatorAmount);
        assertEq(address(operatorRouter).balance - operatorBefore, buyOperatorAmount);
        assertEq(treasury.balance - treasuryBefore, buyTreasuryAmount);

        vm.prank(alice);
        potato.approve(address(swapRouter), bought);
        operatorBefore = address(operatorRouter).balance;
        treasuryBefore = treasury.balance;
        vm.recordLogs();
        _sell(alice, bought / 2);
        (uint256 sellNativeFee, uint256 sellOperatorAmount, uint256 sellTreasuryAmount) =
            _feeAllocation(vm.getRecordedLogs());
        assertGt(sellNativeFee, 0);
        assertEq(sellOperatorAmount, sellNativeFee * 4_000 / 10_000);
        assertEq(sellTreasuryAmount, sellNativeFee - sellOperatorAmount);
        assertEq(address(operatorRouter).balance - operatorBefore, sellOperatorAmount);
        assertEq(treasury.balance - treasuryBefore, sellTreasuryAmount);
        assertEq(address(hook).balance, 0);
    }

    function test_RealSwapsFundRouterAndRegisteredOperatorClaims() public {
        uint256 operatorId = 1;
        IntegrationOperatorCollection operators = new IntegrationOperatorCollection();
        IntegrationActivationRegistry registry = new IntegrationActivationRegistry();
        operators.configure(address(registry), operatorId, alice);
        registry.configure(address(operators), operatorId, 12_500);
        BurntatoOperatorRewardsRouter rewards =
            new BurntatoOperatorRewardsRouter(address(diamond), address(operators), address(registry));

        vm.prank(alice);
        rewards.register(operatorId);
        vm.prank(authority);
        hook.setOperatorRewards(address(rewards), 4_000);
        _createTreasuryInventory();
        market.launchMarket();
        _setExternalBuys(true);

        uint256 treasuryBefore = treasury.balance;
        vm.recordLogs();
        uint256 bought = _buy(alice, 0.0001 ether);
        (uint256 buyNativeFee, uint256 buyOperatorAmount, uint256 buyTreasuryAmount) =
            _feeAllocation(vm.getRecordedLogs());
        assertGt(buyNativeFee, 0);
        assertEq(address(rewards).balance, buyOperatorAmount);
        assertEq(rewards.pendingRevenue(), buyOperatorAmount);
        assertEq(treasury.balance - treasuryBefore, buyTreasuryAmount);

        vm.prank(authority);
        hook.setOperatorRewards(address(rewards), 10_000);
        vm.prank(alice);
        potato.approve(address(swapRouter), bought);
        treasuryBefore = treasury.balance;
        vm.recordLogs();
        _sell(alice, bought / 2);
        (uint256 sellNativeFee, uint256 sellOperatorAmount, uint256 sellTreasuryAmount) =
            _feeAllocation(vm.getRecordedLogs());
        assertGt(sellNativeFee, 0);
        assertEq(sellOperatorAmount, sellNativeFee);
        assertEq(sellTreasuryAmount, 0);
        assertEq(treasury.balance, treasuryBefore);
        assertEq(address(rewards).balance, buyOperatorAmount + sellOperatorAmount);

        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        assertEq(rewards.claim(operatorId, bob), buyOperatorAmount + sellOperatorAmount);
        assertEq(bob.balance - bobBefore, buyOperatorAmount + sellOperatorAmount);
        assertEq(address(rewards).balance, 0);
        assertEq(rewards.totalOperatorClaimed(), buyOperatorAmount + sellOperatorAmount);
        assertEq(address(hook).balance, 0);
    }

    function test_ConfiguredReservesCannotBeClaimedAndStillLaunchAfterExcessClaims() public {
        _createTreasuryInventory();
        assertEq(claims.treasuryEthAvailable(), 0.005 ether);
        assertEq(claims.treasuryPotatoAvailable(), 1_000 ether);
        assertEq(buybacks.buybackReserveEth(), 0.002 ether);

        claims.claimTreasury();
        claims.claimTreasuryPotato();
        assertEq(buybacks.buybackReserveEth(), 0.002 ether);
        assertTrue(market.marketReady());
        market.launchMarket();
        assertEq(claims.treasuryEthAvailable(), 0);
        assertLe(claims.treasuryPotatoAvailable(), 10);
    }

    function test_MarketConfigurationCanChangeBeforeLaunchButNotAfter() public {
        _createTreasuryInventory();
        IMarket.MarketConfig memory config = market.marketConfig();
        config.potatoSeed = 2 ether;
        vm.prank(authority);
        market.configureMarket(config);
        IMarket.MarketConfig memory actual = market.marketConfig();
        assertEq(actual.potatoSeed, 2 ether);

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
        hook.setExternalBuysEnabled(true);
        vm.stopPrank();

        uint256 originalBefore = treasury.balance;
        _buy(alice, 0.0001 ether);
        assertGt(nextTreasury.balance, 0);
        assertEq(treasury.balance, originalBefore);
        assertEq(hook.feeAddress(), nextTreasury);
        assertEq(hook.feeBps(), 500);
    }

    function test_HookSupportsZeroAndFullBilateralFees() public {
        vm.startPrank(authority);
        hook.setFeeBps(0);
        hook.setExternalBuysEnabled(true);
        vm.stopPrank();
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
        NativeFeeReceiver operatorRouter = new NativeFeeReceiver();
        vm.prank(alice);
        vm.expectRevert();
        hook.setFeeAddress(alice);
        vm.prank(alice);
        vm.expectRevert();
        hook.setFeeBps(500);
        vm.prank(alice);
        vm.expectRevert();
        hook.setExternalBuysEnabled(true);
        vm.prank(alice);
        vm.expectRevert();
        hook.setOperatorRewards(address(operatorRouter), 4_000);

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
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidBps.selector);
        hook.setOperatorRewards(address(operatorRouter), 10_001);
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setOperatorRewards(address(0), 1);
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setOperatorRewards(address(operatorRouter), 0);
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setOperatorRewards(alice, 1);
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setOperatorRewards(treasury, 1);

        vm.prank(authority);
        hook.setOperatorRewards(address(operatorRouter), 10_000);
        vm.prank(authority);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setFeeAddress(address(operatorRouter));
        vm.prank(authority);
        hook.setOperatorRewards(address(0), 0);
        assertEq(hook.operatorRewardsRouter(), address(0));
        assertEq(hook.operatorRewardShareBps(), 0);
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
                potatoSeed: POTATO_SEED
            })
        );
    }

    function test_ConfigurationRejectsTerminalUpperTickThatPoolManagerCannotInitialize() public {
        _deployCore();
        IMarket candidate = IMarket(address(diamond));
        CanonicalHookConfigStub stub = new CanonicalHookConfigStub(address(diamond), IPoolManager(address(manager)), 1);

        vm.prank(authority);
        vm.expectRevert(Errors.InvalidMarketConfiguration.selector);
        candidate.configureMarket(
            IMarket.MarketConfig({
                hook: address(stub),
                poolManager: address(manager),
                positionManager: address(positionManager),
                permit2: PERMIT2_ADDRESS,
                sqrtPriceX96: TickMath.getSqrtPriceAtTick(TickMath.MAX_TICK),
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                tickSpacing: 1,
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
                tickUpper: INITIAL_TICK,
                tickSpacing: TICK_SPACING,
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
        _setExternalBuys(true);
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
        _setExternalBuys(true);
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

    function test_ExternalBuysDefaultClosedAndOwnerCanToggleWhileSellsStayOpen() public {
        _createTreasuryInventory();
        market.launchMarket();
        assertFalse(hook.externalBuysEnabled());

        _expectBuyDisabled(alice, 0.0001 ether);

        _setExternalBuys(true);
        uint256 bought = _buy(alice, 0.0001 ether);
        assertGt(bought, 0);

        _setExternalBuys(false);
        _expectBuyDisabled(bob, 0.0001 ether);

        vm.prank(alice);
        potato.approve(address(swapRouter), bought);
        uint256 before = alice.balance;
        _sell(alice, bought);
        assertGt(alice.balance, before);

        _setExternalBuys(true);
        assertGt(_buy(bob, 0.0001 ether), 0);
    }

    function test_PermissionlessBuybackWorksWhileExternalBuysStayClosedAndPaysCaller() public {
        _createTreasuryInventory();
        market.launchMarket();
        assertFalse(hook.externalBuysEnabled());
        assertEq(buybacks.buybackReserveEth(), 0.002 ether);

        uint256 treasuryPotatoBefore = potato.balanceOf(treasury);
        uint256 treasuryNativeBefore = treasury.balance;
        uint256 keeperBefore = keeper.balance;
        vm.recordLogs();
        vm.prank(keeper);
        uint256 amountOut = buybacks.buyback();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 grossSlice, uint256 ethSpent, uint256 bought, uint256 reward, uint256 reserveAfter) =
            _buybackAccounting(logs);

        assertGt(amountOut, 0);
        assertEq(amountOut, bought);
        assertEq(grossSlice, 0.002 ether);
        assertEq(reward, 0.00001 ether);
        assertGt(ethSpent, 0);
        assertLe(ethSpent, grossSlice - reward);
        assertEq(reserveAfter, grossSlice - reward - ethSpent);
        assertEq(potato.balanceOf(treasury) - treasuryPotatoBefore, amountOut);
        assertEq(keeper.balance - keeperBefore, 0.00001 ether);
        assertEq(treasury.balance, treasuryNativeBefore);
        assertEq(buybacks.lastBuybackBlock(), block.number);
        assertEq(buybacks.buybackReserveEth(), reserveAfter);
        assertEq(potato.transientPoolManagerAllowance(), 0);
        assertFalse(hook.externalBuysEnabled());

        _expectBuyDisabled(alice, 0.0001 ether);

        vm.prank(treasury);
        potato.transfer(alice, amountOut / 2);
        vm.prank(alice);
        potato.approve(address(swapRouter), type(uint256).max);
        uint256 nativeBefore = alice.balance;
        _sell(alice, amountOut / 2);
        assertGt(alice.balance, nativeBefore);
        assertFalse(hook.externalBuysEnabled());
    }

    function test_BuybackHonorsCapDelayAndTreasuryCanReusePurchasedPotato() public {
        vm.prank(authority);
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 0.001 ether, callerRewardBps: 50, delayBlocks: 1}));
        _createTreasuryInventory();
        market.launchMarket();

        vm.prank(keeper);
        uint256 firstOut = buybacks.buyback();
        assertGt(firstOut, 0);
        assertEq(keeper.balance, 0.000005 ether);
        assertEq(buybacks.buybackReserveEth(), 0.001 ether);

        vm.prank(keeper);
        vm.expectRevert();
        buybacks.buyback();

        vm.roll(block.number + 1);
        vm.prank(keeper);
        uint256 secondOut = buybacks.buyback();
        assertGt(secondOut, 0);
        assertEq(keeper.balance, 0.00001 ether);
        assertEq(buybacks.buybackReserveEth(), 0);

        uint256 treasuryPotato = potato.balanceOf(treasury);
        uint256 bobBefore = potato.balanceOf(bob);
        vm.prank(treasury);
        potato.transfer(bob, treasuryPotato / 4);
        vm.prank(treasury);
        potato.burn(treasuryPotato / 4);
        assertEq(potato.balanceOf(bob) - bobBefore, treasuryPotato / 4);
    }

    function test_PositiveBuybackDelayCannotRepeatAtTerminalBlock() public {
        vm.prank(authority);
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 0.001 ether, callerRewardBps: 10_000, delayBlocks: 1}));
        _createTreasuryInventory();
        market.launchMarket();

        vm.roll(type(uint256).max);
        vm.prank(keeper);
        assertEq(buybacks.buyback(), 0);
        assertEq(buybacks.buybackReserveEth(), 0.001 ether);

        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Errors.BuybackTooSoon.selector, type(uint256).max));
        buybacks.buyback();
    }

    function test_BuybackConfigurationRemainsGovernedAfterFinalization() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, alice));
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 1 ether, callerRewardBps: 0, delayBlocks: 0}));

        vm.prank(authority);
        vm.expectRevert(Errors.InvalidBps.selector);
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 1 ether, callerRewardBps: 10_001, delayBlocks: 0}));

        vm.startPrank(authority);
        IGovernance(address(diamond)).finalizeProtocol();
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 3 ether, callerRewardBps: 100, delayBlocks: 2}));
        vm.stopPrank();

        BuybackConfig memory config = buybacks.buybackConfig();
        assertEq(config.maxSpend, 3 ether);
        assertEq(config.callerRewardBps, 100);
        assertEq(config.delayBlocks, 2);
    }

    function test_BuybackRequiresLaunchAndPoolManagerCallback() public {
        vm.expectRevert(Errors.MarketNotLaunched.selector);
        buybacks.buyback();

        vm.expectRevert(Errors.InvalidAddress.selector);
        buybacks.unlockCallback(abi.encode(1 ether, treasury));
    }

    function test_FullCallerRewardCanDisableSwapWithoutStrandingReserve() public {
        vm.prank(authority);
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 2 ether, callerRewardBps: 10_000, delayBlocks: 0}));
        _createTreasuryInventory();
        market.launchMarket();

        uint256 supplyBefore = potato.totalSupply();
        vm.prank(keeper);
        assertEq(buybacks.buyback(), 0);
        assertEq(keeper.balance, 0.002 ether);
        assertEq(buybacks.buybackReserveEth(), 0);
        assertEq(potato.totalSupply(), supplyBefore);
    }

    function test_PartialBuybackRestoresUnspentInputToReserve() public {
        IMarket.MarketConfig memory config = market.marketConfig();
        config.tickLower = INITIAL_TICK - TICK_SPACING;
        config.tickUpper = INITIAL_TICK;
        vm.prank(authority);
        market.configureMarket(config);
        _createTreasuryInventory();
        market.launchMarket();

        vm.recordLogs();
        vm.prank(keeper);
        uint256 amountOut = buybacks.buyback();
        (uint256 gross, uint256 spent, uint256 bought, uint256 reward, uint256 reserve) =
            _buybackAccounting(vm.getRecordedLogs());

        assertEq(amountOut, bought);
        assertGt(amountOut, 0);
        assertLt(spent, gross - reward);
        assertEq(reserve, gross - reward - spent);
        assertEq(buybacks.buybackReserveEth(), reserve);
    }

    function test_BuybackUsesCurrentTreasuryWithoutImplicitDistributorGrant() public {
        _createTreasuryInventory();
        market.launchMarket();
        address nextTreasury = makeAddr("buybackTreasury");
        vm.prank(authority);
        IGovernance(address(diamond)).setTreasuryRecipient(nextTreasury);
        assertFalse(potato.isDistributor(nextTreasury));

        vm.prank(keeper);
        uint256 amountOut = buybacks.buyback();
        assertGt(amountOut, 0);
        assertEq(potato.balanceOf(nextTreasury), amountOut);
        assertEq(potato.transientPoolManagerAllowance(), 0);
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
        assertEq(potato.balanceOf(address(diamond)), 1_001 ether);
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

    function _setExternalBuys(bool enabled) internal {
        vm.prank(authority);
        hook.setExternalBuysEnabled(enabled);
    }

    function _replaceSelector(address facet, bytes4 selector) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: selectors});
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _expectBuyDisabled(address buyer, uint256 nativeIn) internal {
        vm.prank(buyer);
        vm.expectRevert();
        swapRouter.swap{value: nativeIn}(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(nativeIn), sqrtPriceLimitX96: MIN_PRICE_LIMIT}),
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

    function _feeAllocation(Vm.Log[] memory logs)
        internal
        view
        returns (uint256 nativeFee, uint256 operatorAmount, uint256 treasuryAmount)
    {
        bytes32 topic = keccak256("HookFeeAllocated(bytes32,uint128,uint128,uint128)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == topic) {
                return abi.decode(logs[i].data, (uint128, uint128, uint128));
            }
        }
    }

    function _buybackAccounting(Vm.Log[] memory logs)
        internal
        view
        returns (uint256 gross, uint256 spent, uint256 bought, uint256 reward, uint256 reserve)
    {
        bytes32 topic = keccak256("BuybackExecuted(address,address,uint256,uint256,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(diamond) && logs[i].topics[0] == topic) {
                return abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256));
            }
        }
    }
}
