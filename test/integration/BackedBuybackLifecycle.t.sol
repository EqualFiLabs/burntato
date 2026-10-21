// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LocalWETH9} from "../../script/helpers/LocalWETH9.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "../../src/shared/Types.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {ProtocolConfig} from "../../src/shared/Types.sol";

contract RejectingBuybackCaller {
    function execute(address diamond) external {
        IBuyback(diamond).buyback();
    }

    receive() external payable {
        revert("tip rejected");
    }
}

contract ReentrantBuybackCaller {
    address internal diamond;
    uint256 public blocked;
    uint256 public validationChecks;

    function execute(address target) external returns (uint256) {
        diamond = target;
        return IBuyback(target).buyback();
    }

    receive() external payable {
        _probe(abi.encodeCall(IPotatoToken.unwrap, (1)), 0, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(ISettlement.settleRound, ()), 0, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(IGame.buyPotato, ()), 0, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(IBuyback.buyback, ()), 0, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(IClaims.claimTreasury, ()), 0, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(IGame.fundWinnerReserve, (1)), 1, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(IGame.fundRoundReserves, (1, 1, 0)), 1, Errors.Reentrancy.selector);
        _probe(abi.encodeCall(IRecovery.fundRecoveryReserve, (1)), 1, Errors.Reentrancy.selector);
        // Funding validates the request before entering the shared guard.
        _probe(abi.encodeCall(IGame.fundWinnerReserve, (1)), 0, Errors.ZeroAmount.selector);
        _probe(abi.encodeCall(IGame.fundRoundReserves, (1, 2, 0)), 1, Errors.IncorrectPayment.selector);
        _probe(abi.encodeCall(IRecovery.fundRecoveryReserve, (0)), 1, Errors.InvalidFutureRound.selector);
    }

    function _probe(bytes memory callData, uint256 value, bytes4 expected) private {
        (bool ok, bytes memory result) = diamond.call{value: value}(callData);
        require(!ok && result.length >= 4 && bytes4(result) == expected, "unexpected callback result");
        if (expected == Errors.Reentrancy.selector) ++blocked;
        else ++validationChecks;
    }
}

contract RejectReserveCreditFacet {
    function protocolCreditRewardReserve(uint256, uint256) external pure {
        revert("reserve credit failed");
    }
}

abstract contract BackedBuybackLifecycleTestBase is DiamondTestSetup {
    LocalWETH9 internal weth;
    IPoolManager internal manager;
    PoolKey internal key;
    IBuyback internal buybacks;
    IPotatoToken internal potato;
    address internal keeper = makeAddr("keeper");

    function _initialRewardFunding() internal pure override returns (uint256) {
        return 0;
    }

    function _initialConfig() internal pure override returns (ProtocolConfig memory config) {
        config = _defaultConfig();
        config.roundEmissionBudget = 0.5 ether;
    }

    function _wethAddress() internal pure virtual returns (address);

    function setUp() public {
        _deployCore();
        buybacks = IBuyback(address(diamond));
        potato = IPotatoToken(address(diamond));
        vm.etch(_wethAddress(), address(new LocalWETH9()).code);
        weth = LocalWETH9(payable(_wethAddress()));
        manager = IPoolManager(address(new PoolManager(address(this))));
        bool wethFirst = address(weth) < address(statics);
        key = PoolKey({
            currency0: Currency.wrap(wethFirst ? address(weth) : address(statics)),
            currency1: Currency.wrap(wethFirst ? address(statics) : address(weth)),
            fee: 15_000,
            tickSpacing: 100,
            hooks: IHooks(address(0))
        });
        manager.initialize(key, uint160(1 << 96));
        PoolModifyLiquidityTest liquidity = new PoolModifyLiquidityTest(manager);
        vm.deal(address(this), 2_000_000 ether);
        weth.deposit{value: 1_000_000 ether}();
        statics.mint(address(this), 1_000_000 ether);
        weth.approve(address(liquidity), 1_000_000 ether);
        statics.approve(address(liquidity), 1_000_000 ether);
        liquidity.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -887200, tickUpper: 887200, liquidityDelta: 1_000_000 ether, salt: 0}),
            ""
        );
        vm.prank(authority);
        buybacks.setBuybackMarket(address(manager), address(weth), key);
        buybacks.fundBuybackReserve{value: 2 ether}();
        vm.roll(block.number + 2);
    }

    function test_RealWethSettlementMintsExactBackedReserveWithoutPublicCapacity() public {
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 keeperBefore = keeper.balance;
        uint256 managerWeth = weth.balanceOf(address(manager));
        vm.prank(keeper);
        uint256 acquired = buybacks.buyback();
        uint256 input = uint256(1 ether) * 10_000 / 10_050;
        uint256 tip = input * 50 / 10_000;
        assertEq(weth.balanceOf(address(manager)), managerWeth + input);
        assertEq(weth.balanceOf(address(diamond)), 0);
        assertEq(potato.backingBalance(), acquired);
        assertEq(potato.totalSupply(), acquired);
        assertEq(potato.rewardReserve(), acquired);
        assertEq(potato.balanceOf(address(diamond)), acquired);
        assertEq(potato.publicWrapOutstanding(), 0);
        assertEq(keeper.balance, keeperBefore + tip);
        assertEq(buybacks.buybackReserveEth(), reserveBefore - input - tip);
        assertLt(acquired, input); // Ordinary 1.5% pool fee applies.
        assertEq(statics.balanceOf(treasury), 0);
        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        IGame(address(diamond)).buyPotato{value: 0.01 ether}();
        vm.warp(block.timestamp + 120);
        IGame(address(diamond)).materializeMaturedEmission();
        vm.prank(keeper);
        potato.unwrap(0.05 ether);
        assertEq(statics.balanceOf(keeper), 0.05 ether);
        assertEq(potato.backingBalance(), potato.totalSupply());
    }

    function test_BuybackEventReportsExecutedAmounts() public {
        vm.recordLogs();
        vm.prank(keeper);
        uint256 acquired = buybacks.buyback();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory executed = logs[logs.length - 1];
        assertEq(executed.emitter, address(diamond));
        assertEq(executed.topics.length, 3);
        assertEq(executed.topics[0], IBuyback.BuybackExecuted.selector);
        assertEq(executed.topics[1], bytes32(uint256(uint160(keeper))));
        assertEq(executed.topics[2], bytes32(uint256(uint160(address(diamond)))));
        uint256 input = uint256(1 ether) * 10_000 / 10_050;
        uint256 tip = input * 50 / 10_000;
        assertEq(executed.data, abi.encode(1 ether, input, acquired, acquired, tip, 2 ether - input - tip));
    }

    function test_CooldownAndCappedSpending() public {
        vm.prank(keeper);
        buybacks.buyback();
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(Errors.BuybackTooSoon.selector, block.number + 1));
        buybacks.buyback();
        vm.roll(block.number + 1);
        vm.prank(keeper);
        buybacks.buyback();
        assertLe(buybacks.buybackReserveEth(), 2);
    }

    function test_RejectingTipRevertsPoolBackingReserveAndCooldown() public {
        RejectingBuybackCaller caller = new RejectingBuybackCaller();
        uint256 managerWeth = weth.balanceOf(address(manager));
        uint256 managerStatics = statics.balanceOf(address(manager));
        vm.expectRevert();
        caller.execute(address(diamond));
        assertEq(buybacks.buybackReserveEth(), 2 ether);
        assertEq(buybacks.lastBuybackBlock(), 0);
        assertEq(potato.totalSupply(), 0);
        assertEq(potato.rewardReserve(), 0);
        assertEq(potato.backingBalance(), 0);
        assertEq(weth.balanceOf(address(manager)), managerWeth);
        assertEq(statics.balanceOf(address(manager)), managerStatics);
    }

    function test_AcquiredBackingFailureRevertsWethAndReserveSpend() public {
        statics.setFailure(true);
        uint256 managerWeth = weth.balanceOf(address(manager));
        vm.prank(keeper);
        vm.expectRevert();
        buybacks.buyback();
        assertEq(weth.balanceOf(address(manager)), managerWeth);
        assertEq(buybacks.buybackReserveEth(), 2 ether);
        assertEq(buybacks.lastBuybackBlock(), 0);
        assertEq(potato.totalSupply(), 0);
    }

    function test_PositivePartialFillRevertsActualPoolState() public {
        IPoolManager shallow = IPoolManager(address(new PoolManager(address(this))));
        shallow.initialize(key, uint160(1 << 96));
        PoolModifyLiquidityTest liquidity = new PoolModifyLiquidityTest(shallow);
        weth.deposit{value: 100 ether}();
        statics.mint(address(this), 100 ether);
        weth.approve(address(liquidity), 100 ether);
        statics.approve(address(liquidity), 100 ether);
        liquidity.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -100, tickUpper: 100, liquidityDelta: 100 ether, salt: 0}), ""
        );
        vm.prank(authority);
        buybacks.setBuybackMarket(address(shallow), address(weth), key);
        uint256 beforeWeth = weth.balanceOf(address(shallow));
        uint256 beforeStatics = statics.balanceOf(address(shallow));
        vm.expectRevert(Errors.BuybackNoExecution.selector);
        buybacks.buyback();
        assertEq(weth.balanceOf(address(shallow)), beforeWeth);
        assertEq(statics.balanceOf(address(shallow)), beforeStatics);
        assertEq(buybacks.buybackReserveEth(), 2 ether);
        assertEq(buybacks.lastBuybackBlock(), 0);
        assertEq(potato.totalSupply(), 0);
    }

    function test_BuybackReserveCreditIsIndependentOfFullPublicCap() public {
        statics.mint(keeper, 2_000_000 ether);
        vm.startPrank(keeper);
        statics.approve(address(diamond), 2_000_000 ether);
        potato.wrap(2_000_000 ether);
        assertEq(potato.availablePublicWrapCapacity(), 0);
        uint256 acquired = buybacks.buyback();
        vm.stopPrank();
        assertEq(potato.publicWrapOutstanding(), 2_000_000 ether);
        assertEq(potato.rewardReserve(), acquired);
        assertEq(potato.totalSupply(), 2_000_000 ether + acquired);
        assertEq(potato.backingBalance(), potato.totalSupply());
    }

    function test_ReserveCreditFailureRollsBackPoolBackingAndCooldown() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IPotatoToken.protocolCreditRewardReserve.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(new RejectReserveCreditFacet()), FacetCutAction.Replace, selectors);
        vm.prank(authority);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        uint256 managerWeth = weth.balanceOf(address(manager));
        uint256 managerStatics = statics.balanceOf(address(manager));
        vm.expectRevert("reserve credit failed");
        buybacks.buyback();
        assertEq(weth.balanceOf(address(manager)), managerWeth);
        assertEq(statics.balanceOf(address(manager)), managerStatics);
        assertEq(potato.backingBalance(), 0);
        assertEq(potato.totalSupply(), 0);
        assertEq(potato.rewardReserve(), 0);
        assertEq(buybacks.buybackReserveEth(), 2 ether);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function test_TipCallbackCannotReenterOtherFacets() public {
        ReentrantBuybackCaller caller = new ReentrantBuybackCaller();
        uint256 acquired = caller.execute(address(diamond));
        assertEq(caller.blocked(), 8);
        assertEq(caller.validationChecks(), 3);
        IGame(address(diamond)).fundWinnerReserve{value: 1}(1);
        IGame(address(diamond)).fundRoundReserves{value: 2}(1, 1, 1);
        IRecovery(address(diamond)).fundRecoveryReserve{value: 1}(1);
        assertEq(IGame(address(diamond)).winnerReserveEth(), 2);
        assertEq(IRecovery(address(diamond)).recoveryReserveEth(), 2);
        assertGt(acquired, 0);
        assertEq(potato.totalSupply(), acquired);
        assertEq(potato.rewardReserve(), acquired);
        assertEq(potato.backingBalance(), acquired);
        assertEq(IGame(address(diamond)).currentRoundId(), 0);
        assertGt(buybacks.lastBuybackBlock(), 0);
    }

    function test_CallbackRejectsUnsolicitedManagerInvocation() public {
        vm.prank(address(manager));
        vm.expectRevert(Errors.InvalidAddress.selector);
        buybacks.unlockCallback(abi.encode(1 ether));
    }
}

contract WethFirstBuybackLifecycleTest is BackedBuybackLifecycleTestBase {
    function _wethAddress() internal pure override returns (address) {
        return address(0x1000);
    }
}

contract StaticsFirstBuybackLifecycleTest is BackedBuybackLifecycleTestBase {
    function _wethAddress() internal pure override returns (address) {
        return address(type(uint160).max - 10);
    }
}
