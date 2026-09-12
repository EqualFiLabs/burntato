// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {BuybackConfig, ProtocolConfig, Round} from "../../src/shared/Types.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {PositionManagerTestSetup} from "../utils/PositionManagerTestSetup.sol";

contract DefaultLaunchEconomicsTest is DiamondTestSetup, Deployers, PositionManagerTestSetup {
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    int24 internal constant TICK_SPACING = 60;
    int24 internal constant INITIAL_TICK = 170_280;
    uint256 internal constant POTATO_SEED = 100_000_000 ether;

    address internal buyer = makeAddr("buyer");
    address internal funder = makeAddr("funder");
    address internal keeper = makeAddr("keeper");

    BurntatoSwapFeeHook internal hook;
    IBuyback internal buybacks;
    IGame internal game;
    IMarket internal market;
    IPotatoToken internal potato;

    function setUp() public {
        deployFreshManagerAndRouters();
        _deployPositionManager(IPoolManager(address(manager)));
        _deployCore();

        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory constructorArgs = abi.encode(
            manager, authority, address(diamond), treasury, uint16(100), address(0), uint16(0), TICK_SPACING
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BurntatoSwapFeeHook).creationCode, constructorArgs);
        vm.prank(CREATE2_DEPLOYER);
        hook = new BurntatoSwapFeeHook{salt: salt}(
            IPoolManager(address(manager)), authority, address(diamond), treasury, 100, address(0), 0, TICK_SPACING
        );
        assertEq(address(hook), hookAddress);

        buybacks = IBuyback(address(diamond));
        game = IGame(address(diamond));
        market = IMarket(address(diamond));
        potato = IPotatoToken(address(diamond));

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

        vm.deal(buyer, 1 ether);
        vm.deal(funder, 2.01 ether);
        vm.deal(address(manager), 100 ether);
    }

    function test_DefaultBootstrapCoversFirstFullyVestedEmissionSell() public {
        market.launchMarket();
        assertFalse(hook.externalBuysEnabled());

        vm.prank(funder);
        buybacks.fundBuybackReserve{value: 2 ether}();

        uint256 treasuryPotatoBefore = potato.balanceOf(treasury);
        uint256 keeperNativeBefore = keeper.balance;
        vm.prank(keeper);
        uint256 bootstrapBought = buybacks.buyback();

        assertGe(bootstrapBought, 6_700_000 ether);
        assertLe(bootstrapBought, 6_750_000 ether);
        assertEq(potato.balanceOf(treasury) - treasuryPotatoBefore, bootstrapBought);
        assertGt(keeper.balance - keeperNativeBefore, 0);

        vm.prank(funder);
        game.buyPotato{value: 0.01 ether}();
        uint256 reserveBeforePurchase = buybacks.buybackReserveEth();
        vm.prank(buyer);
        game.buyPotato{value: 0.011 ether}();
        uint256 purchaseBuybackContribution = buybacks.buybackReserveEth() - reserveBeforePurchase;
        assertEq(purchaseBuybackContribution, 0.0011 ether);

        Round memory round = game.getRound(1);
        assertEq(round.config.emissionVestingDuration, 4 minutes);
        vm.warp(round.holderSince + 4 minutes);
        game.materializeMaturedEmission();
        assertEq(round.config.roundEmissionBudget, 10_000 ether);
        assertEq(potato.balanceOf(buyer), 1_000 ether);

        vm.prank(buyer);
        potato.approve(address(swapRouter), 1_000 ether);
        uint256 buyerNativeBefore = buyer.balance;
        vm.prank(buyer);
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -int256(1_000 ether), sqrtPriceLimitX96: MAX_PRICE_LIMIT}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );
        uint256 sellProceeds = buyer.balance - buyerNativeBefore;

        assertGt(sellProceeds, 0.00064 ether);
        assertLt(sellProceeds, 0.000645 ether);
        assertLt(sellProceeds, purchaseBuybackContribution);
        assertFalse(hook.externalBuysEnabled());
    }

    function test_TreasuryBuybacksCrossAggressiveCurveBands() public {
        vm.prank(authority);
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 2 ether, callerRewardBps: 50, delayBlocks: 0}));
        market.launchMarket();
        uint256[5] memory grossTargets = [uint256(2 ether), 5 ether, 10 ether, 25 ether, 50 ether];
        uint256[5] memory minimumPotato =
            [uint256(6_700_000 ether), 10_200_000 ether, 13_500_000 ether, 17_900_000 ether, 22_400_000 ether];
        uint256[5] memory maximumPotato =
            [uint256(6_800_000 ether), 10_400_000 ether, 13_800_000 ether, 18_300_000 ether, 22_900_000 ether];

        for (uint256 index; index < grossTargets.length; ++index) {
            uint256 snapshot = vm.snapshotState();
            uint256 bought = _executeBuybackTarget(grossTargets[index]);
            assertGe(bought, minimumPotato[index]);
            assertLe(bought, maximumPotato[index]);
            assertFalse(hook.externalBuysEnabled());
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function _executeBuybackTarget(uint256 grossTarget) private returns (uint256 bought) {
        vm.deal(funder, grossTarget);
        vm.prank(funder);
        buybacks.fundBuybackReserve{value: grossTarget}();

        uint256 calls = (grossTarget + 2 ether - 1) / 2 ether;
        for (uint256 index; index < calls; ++index) {
            vm.prank(keeper);
            bought += buybacks.buyback();
        }
        assertLe(buybacks.buybackReserveEth(), calls);
    }

    function _initialConfig() internal pure override returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.roundEmissionBudget = 10_000 ether;
        config.emissionVestingDuration = 4 minutes;
    }

    function _genesisMarketSupply() internal pure override returns (uint256) {
        return POTATO_SEED;
    }
}
