// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {MockStatics} from "../../test/mocks/MockStatics.sol";
import {LocalWETH9} from "../../script/helpers/LocalWETH9.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {LibMath} from "../../src/libraries/LibMath.sol";
import {LibProtocolStorage} from "../../src/libraries/LibProtocolStorage.sol";
import {BuybackConfig, BuybackQuote} from "../../src/shared/Types.sol";

contract SymbolicBuybackPoolManager {
    enum Mode {
        FullFill,
        PartialFill,
        ZeroOutput,
        RevertCall,
        MalformedReturn
    }

    Mode public mode;
    uint256 public unlockCalls;

    function setMode(Mode mode_) external {
        mode = mode_;
    }

    uint256 private synced;
    address private syncedToken;

    function unlock(bytes calldata data) external returns (bytes memory result) {
        ++unlockCalls;
        if (mode == Mode.RevertCall) revert();
        if (mode == Mode.MalformedReturn) return abi.encode(uint256(1));
        return IUnlockCallback(msg.sender).unlockCallback(data);
    }

    function swap(PoolKey calldata, SwapParams calldata params, bytes calldata) external view returns (BalanceDelta) {
        uint256 input = uint256(-params.amountSpecified);
        if (mode == Mode.PartialFill) --input;
        uint256 output = mode == Mode.ZeroOutput ? 0 : 1;
        return params.zeroForOne
            ? toBalanceDelta(-int128(int256(input)), int128(int256(output)))
            : toBalanceDelta(int128(int256(output)), -int128(int256(input)));
    }

    function sync(Currency currency) external {
        syncedToken = Currency.unwrap(currency);
        synced = LocalWETH9(payable(syncedToken)).balanceOf(address(this));
    }

    function settle() external view returns (uint256) {
        return LocalWETH9(payable(syncedToken)).balanceOf(address(this)) - synced;
    }

    function take(Currency currency, address recipient, uint256 amount) external {
        MockStatics(Currency.unwrap(currency)).transfer(recipient, amount);
    }
}

/// @dev Controlled starting reserve and route; production callback, WETH and wrapper logic execute unsummarized.
contract SymbolicBuybackHarness is BuybackFacet, PotatoTokenFacet {
    function configure(
        address poolManager,
        address treasury,
        address statics,
        address weth,
        uint256 reserve,
        uint256 maxSpend,
        uint256 callerRewardBps
    ) external {
        require(callerRewardBps <= 100);
        LibProtocolStorage.BuybackMarketStorage storage market = LibProtocolStorage.buybackMarket();
        market.poolManager = poolManager;
        market.weth = weth;
        market.configured = true;
        (address c0, address c1) = statics < weth ? (statics, weth) : (weth, statics);
        market.key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 15000, 100, IHooks(address(0)));
        LibProtocolStorage.wrapper().underlying = statics;
        LibProtocolStorage.treasury().recipient = treasury;
        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth = reserve;
        bs.config = BuybackConfig({maxSpend: maxSpend, callerRewardBps: uint16(callerRewardBps), delayBlocks: 0});
        LibProtocolStorage.reentrancy().status = 1;
    }
}

contract BurntatoBuybackExecutionProperties is Test {
    address private constant KEEPER = address(0xA11CE);
    address private constant TREASURY = address(0xBEEF);

    SymbolicBuybackHarness private harness;
    SymbolicBuybackPoolManager private manager;
    IBuyback private buybacks;
    MockStatics private statics;
    LocalWETH9 private weth;

    function setUp() public {
        harness = new SymbolicBuybackHarness();
        manager = new SymbolicBuybackPoolManager();
        buybacks = IBuyback(address(harness));
        statics = new MockStatics();
        weth = new LocalWETH9();
        statics.mint(address(manager), 1);
    }

    function check_fullFillConservesReserve(uint96 reserve_, uint96 maxSpend_, uint16 callerRewardBps) public {
        vm.assume(reserve_ != 0 && maxSpend_ != 0);
        vm.assume(callerRewardBps <= 100);

        uint256 reserve = reserve_;
        uint256 maxSpend = maxSpend_;
        BuybackQuote memory quote = LibMath.quoteBuyback(reserve, maxSpend, callerRewardBps);
        vm.assume(quote.requestedInput != 0);

        harness.configure(
            address(manager), TREASURY, address(statics), address(weth), reserve, maxSpend, callerRewardBps
        );
        vm.deal(address(harness), reserve);
        uint256 keeperBefore = KEEPER.balance;

        vm.prank(KEEPER);
        uint256 amountOut = buybacks.buyback();

        assertEq(amountOut, 1);
        assertEq(harness.totalSupply(), 1);
        assertEq(harness.backingBalance(), 1);
        assertEq(harness.rewardReserve(), 1);
        assertEq(harness.publicWrapOutstanding(), 0);
        assertEq(manager.unlockCalls(), 1);
        assertEq(buybacks.buybackReserveEth(), reserve - quote.requestedInput - quote.callerReward);
        assertEq(KEEPER.balance, keeperBefore + quote.callerReward);
        assertEq(buybacks.lastBuybackBlock(), block.number);
    }

    function check_failedManagerOutcomeRollsBack(
        uint96 reserve_,
        uint96 maxSpend_,
        uint16 callerRewardBps,
        uint8 rawMode
    ) public {
        vm.assume(reserve_ != 0 && maxSpend_ != 0);
        vm.assume(callerRewardBps <= 100);
        uint256 reserve = reserve_;
        uint256 maxSpend = maxSpend_;
        BuybackQuote memory quote = LibMath.quoteBuyback(reserve, maxSpend, callerRewardBps);
        vm.assume(quote.requestedInput != 0);

        vm.assume(rawMode >= 1 && rawMode <= 4);
        SymbolicBuybackPoolManager.Mode mode = SymbolicBuybackPoolManager.Mode(rawMode);
        manager.setMode(mode);
        harness.configure(
            address(manager), TREASURY, address(statics), address(weth), reserve, maxSpend, callerRewardBps
        );
        vm.deal(address(harness), reserve);
        uint256 keeperBefore = KEEPER.balance;

        vm.prank(KEEPER);
        (bool success,) = address(buybacks).call(abi.encodeCall(IBuyback.buyback, ()));

        assertFalse(success);
        assertEq(harness.totalSupply(), 0);
        assertEq(harness.backingBalance(), 0);
        assertEq(harness.rewardReserve(), 0);
        assertEq(manager.unlockCalls(), 0);
        assertEq(buybacks.buybackReserveEth(), reserve);
        assertEq(buybacks.lastBuybackBlock(), 0);
        assertEq(address(harness).balance, reserve);
        assertEq(KEEPER.balance, keeperBefore);
    }
}
