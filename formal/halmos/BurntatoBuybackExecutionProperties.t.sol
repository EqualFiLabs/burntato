// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

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

    function unlock(bytes calldata data) external returns (bytes memory result) {
        ++unlockCalls;
        (uint256 requestedInput,) = abi.decode(data, (uint256, address));
        if (mode == Mode.RevertCall) revert();
        if (mode == Mode.MalformedReturn) return abi.encode(requestedInput);
        if (mode == Mode.PartialFill) return abi.encode(requestedInput - 1, uint256(1));
        if (mode == Mode.ZeroOutput) return abi.encode(requestedInput, uint256(0));
        return abi.encode(requestedInput, uint256(1));
    }
}

contract SymbolicBuybackHarness is BuybackFacet {
    function configure(
        address poolManager,
        address treasury,
        uint256 reserve,
        uint256 maxSpend,
        uint16 callerRewardBps
    ) external {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        ms.poolManager = poolManager;
        ms.launched = true;
        LibProtocolStorage.treasury().recipient = treasury;

        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth = reserve;
        bs.config = BuybackConfig({maxSpend: maxSpend, callerRewardBps: callerRewardBps, delayBlocks: 0});
        bs.lastBuybackBlock = 0;
        LibProtocolStorage.reentrancy().status = 1;
    }
}

contract BurntatoBuybackExecutionProperties is Test {
    address private constant KEEPER = address(0xA11CE);
    address private constant TREASURY = address(0xBEEF);

    SymbolicBuybackHarness private harness;
    SymbolicBuybackPoolManager private manager;
    IBuyback private buybacks;

    function setUp() public {
        harness = new SymbolicBuybackHarness();
        manager = new SymbolicBuybackPoolManager();
        buybacks = IBuyback(address(harness));
    }

    function check_fullFillConservesReserve(uint96 reserve_, uint96 maxSpend_, uint16 callerRewardBps) public {
        vm.assume(reserve_ != 0 && maxSpend_ != 0);
        vm.assume(callerRewardBps <= 100);

        uint256 reserve = reserve_;
        uint256 maxSpend = maxSpend_;
        BuybackQuote memory quote = LibMath.quoteBuyback(reserve, maxSpend, callerRewardBps);
        vm.assume(quote.requestedInput != 0);

        harness.configure(address(manager), TREASURY, reserve, maxSpend, callerRewardBps);
        vm.deal(address(harness), reserve);
        uint256 keeperBefore = KEEPER.balance;

        vm.prank(KEEPER);
        uint256 amountOut = buybacks.buyback();

        assertEq(amountOut, 1);
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

        SymbolicBuybackPoolManager.Mode mode = SymbolicBuybackPoolManager.Mode(uint8(bound(rawMode, 1, 4)));
        manager.setMode(mode);
        harness.configure(address(manager), TREASURY, reserve, maxSpend, callerRewardBps);
        vm.deal(address(harness), reserve);
        uint256 keeperBefore = KEEPER.balance;

        vm.prank(KEEPER);
        (bool success,) = address(buybacks).call(abi.encodeCall(IBuyback.buyback, ()));

        assertFalse(success);
        assertEq(manager.unlockCalls(), 0);
        assertEq(buybacks.buybackReserveEth(), reserve);
        assertEq(buybacks.lastBuybackBlock(), 0);
        assertEq(address(harness).balance, reserve);
        assertEq(KEEPER.balance, keeperBefore);
    }
}
