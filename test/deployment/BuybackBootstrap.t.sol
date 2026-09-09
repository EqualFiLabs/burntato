// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BootstrapBurntatoBuyback} from "../../script/BootstrapBurntatoBuyback.s.sol";
import {BuybackConfig} from "../../src/shared/Types.sol";

contract BuybackBootstrapStateMock {
    bool internal purchasesActive;
    bool internal marketLaunching;
    bool internal marketLaunched;
    uint256 internal reserve;
    uint256 internal lastExecutionBlock;
    BuybackConfig internal config;

    function configure(
        bool purchasesActive_,
        bool marketLaunching_,
        bool marketLaunched_,
        uint256 maxSpend_,
        uint256 reserve_,
        uint256 lastExecutionBlock_
    ) external {
        purchasesActive = purchasesActive_;
        marketLaunching = marketLaunching_;
        marketLaunched = marketLaunched_;
        config = BuybackConfig({maxSpend: maxSpend_, callerRewardBps: 50, delayBlocks: 1});
        reserve = reserve_;
        lastExecutionBlock = lastExecutionBlock_;
    }

    function marketState() external view returns (bytes32, bool, bool, bool) {
        return (bytes32(0), marketLaunched, marketLaunching, marketLaunched);
    }

    function purchasesInitialized() external view returns (bool) {
        return purchasesActive;
    }

    function buybackConfig() external view returns (BuybackConfig memory) {
        return config;
    }

    function buybackReserveEth() external view returns (uint256) {
        return reserve;
    }

    function lastBuybackBlock() external view returns (uint256) {
        return lastExecutionBlock;
    }
}

contract BuybackBootstrapTest is Test {
    BootstrapBurntatoBuyback internal bootstrap;
    BuybackBootstrapStateMock internal state;

    function setUp() public {
        bootstrap = new BootstrapBurntatoBuyback();
        state = new BuybackBootstrapStateMock();
        state.configure(false, false, true, 2 ether, 0, 0);
    }

    function test_EmptyReserveRequiresFunding() public view {
        assertTrue(bootstrap.checkBootstrapState(address(state), 1 ether));
    }

    function test_ExactExistingFundingResumesAtBuyback() public {
        state.configure(false, false, true, 2 ether, 1 ether, 0);
        assertFalse(bootstrap.checkBootstrapState(address(state), 1 ether));
    }

    function test_RejectsMissingOrLaunchingMarket() public {
        state.configure(false, false, false, 2 ether, 0, 0);
        vm.expectRevert(BootstrapBurntatoBuyback.MarketNotLaunched.selector);
        bootstrap.checkBootstrapState(address(state), 1 ether);

        state.configure(false, true, true, 2 ether, 0, 0);
        vm.expectRevert(BootstrapBurntatoBuyback.MarketNotLaunched.selector);
        bootstrap.checkBootstrapState(address(state), 1 ether);
    }

    function test_RejectsActivePurchasesOrPriorBuyback() public {
        state.configure(true, false, true, 2 ether, 0, 0);
        vm.expectRevert(BootstrapBurntatoBuyback.PurchasesAlreadyInitialized.selector);
        bootstrap.checkBootstrapState(address(state), 1 ether);

        state.configure(false, false, true, 2 ether, 0, 123);
        vm.expectRevert(abi.encodeWithSelector(BootstrapBurntatoBuyback.BuybackAlreadyExecuted.selector, 123));
        bootstrap.checkBootstrapState(address(state), 1 ether);
    }

    function test_RejectsZeroOrAboveCapAmount() public {
        vm.expectRevert(abi.encodeWithSelector(BootstrapBurntatoBuyback.InvalidBootstrapAmount.selector, 0, 2 ether));
        bootstrap.checkBootstrapState(address(state), 0);

        vm.expectRevert(
            abi.encodeWithSelector(BootstrapBurntatoBuyback.InvalidBootstrapAmount.selector, 3 ether, 2 ether)
        );
        bootstrap.checkBootstrapState(address(state), 3 ether);
    }

    function test_RejectsUnexpectedExistingReserve() public {
        state.configure(false, false, true, 2 ether, 0.5 ether, 0);
        vm.expectRevert(
            abi.encodeWithSelector(BootstrapBurntatoBuyback.UnexpectedBuybackReserve.selector, 1 ether, 0.5 ether)
        );
        bootstrap.checkBootstrapState(address(state), 1 ether);
    }

    function test_RejectsAddressWithoutCode() public {
        address missing = address(0xBEEF);
        vm.expectRevert(abi.encodeWithSelector(BootstrapBurntatoBuyback.InvalidDiamond.selector, missing));
        bootstrap.checkBootstrapState(missing, 1 ether);
    }
}
