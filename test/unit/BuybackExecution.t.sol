// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {LibProtocolStorage} from "../../src/libraries/LibProtocolStorage.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {BuybackConfig} from "../../src/shared/Types.sol";

contract PartialFillPoolManager {
    uint256 public unlockCalls;

    function unlock(bytes calldata data) external returns (bytes memory) {
        ++unlockCalls;
        (uint256 amountIn,) = abi.decode(data, (uint256, address));
        return abi.encode(amountIn - 1, uint256(1));
    }
}

contract BuybackExecutionHarness is BuybackFacet {
    function configure(
        address poolManager,
        address treasury,
        uint256 reserve,
        BuybackConfig calldata config,
        uint256 lastExecutionBlock,
        bool paused_
    ) external {
        LibProtocolStorage.MarketStorage storage ms = LibProtocolStorage.market();
        ms.poolManager = poolManager;
        ms.launched = true;
        LibProtocolStorage.treasury().recipient = treasury;

        LibProtocolStorage.BuybackStorage storage bs = LibProtocolStorage.buyback();
        bs.reserveEth = reserve;
        bs.config = config;
        bs.lastBuybackBlock = lastExecutionBlock;
        LibProtocolStorage.governance().paused = paused_;
    }
}

contract BuybackExecutionTest is Test {
    address internal keeper = makeAddr("buyback-keeper");
    address internal treasury = makeAddr("buyback-treasury");

    BuybackExecutionHarness internal harness;
    PartialFillPoolManager internal manager;

    function setUp() public {
        harness = new BuybackExecutionHarness();
        manager = new PartialFillPoolManager();
        harness.configure(
            address(manager),
            treasury,
            1 ether,
            BuybackConfig({maxSpend: 1 ether, callerRewardBps: 50, delayBlocks: 1}),
            0,
            false
        );
        vm.deal(address(harness), 1 ether);
    }

    function test_PositivePartialFillRevertsAtomically() public {
        IBuyback buybacks = IBuyback(address(harness));
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 harnessBefore = address(harness).balance;
        uint256 keeperBefore = keeper.balance;
        uint256 treasuryBefore = treasury.balance;

        vm.prank(keeper);
        vm.expectRevert(Errors.BuybackNoExecution.selector);
        buybacks.buyback();

        assertEq(buybacks.buybackReserveEth(), reserveBefore);
        assertEq(buybacks.lastBuybackBlock(), 0);
        assertEq(address(harness).balance, harnessBefore);
        assertEq(keeper.balance, keeperBefore);
        assertEq(treasury.balance, treasuryBefore);
        assertEq(manager.unlockCalls(), 0);
    }

    function test_PausePrecedesMarketAndReserveValidation() public {
        harness.configure(
            address(0), treasury, 0, BuybackConfig({maxSpend: 0, callerRewardBps: 50, delayBlocks: 1}), 17, true
        );

        vm.prank(keeper);
        vm.expectRevert(Errors.ProtocolPaused.selector);
        IBuyback(address(harness)).buyback();

        assertEq(IBuyback(address(harness)).buybackReserveEth(), 0);
        assertEq(IBuyback(address(harness)).lastBuybackBlock(), 17);
    }
}
