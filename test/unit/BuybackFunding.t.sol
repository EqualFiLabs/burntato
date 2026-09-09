// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract BuybackFundingTest is DiamondTestSetup {
    event BuybackReserveFunded(address indexed funder, uint256 amount, uint256 reserveEth);

    address internal alice = makeAddr("funding-alice");
    address internal bob = makeAddr("funding-bob");

    IBuyback internal buybacks;
    IGovernance internal governance;

    function setUp() public {
        _deployCoreWithoutPurchaseInitialization();
        buybacks = IBuyback(address(diamond));
        governance = IGovernance(address(diamond));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_AnyoneCanFundReserveWithExactAdditiveAccounting() public {
        vm.expectEmit(true, false, false, true, address(diamond));
        emit BuybackReserveFunded(alice, 1 ether, 1 ether);
        vm.prank(alice);
        buybacks.fundBuybackReserve{value: 1 ether}();

        vm.expectEmit(true, false, false, true, address(diamond));
        emit BuybackReserveFunded(bob, 2 ether, 3 ether);
        vm.prank(bob);
        buybacks.fundBuybackReserve{value: 2 ether}();

        assertEq(buybacks.buybackReserveEth(), 3 ether);
        assertEq(address(diamond).balance, 3 ether);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function test_ZeroFundingRevertsWithoutChangingAccounting() public {
        vm.prank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        buybacks.fundBuybackReserve();

        assertEq(buybacks.buybackReserveEth(), 0);
        assertEq(address(diamond).balance, 0);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function test_RawNativeTransferDoesNotCreditReserve() public {
        vm.prank(alice);
        (bool success,) = address(diamond).call{value: 1 ether}("");

        assertTrue(success);
        assertEq(address(diamond).balance, 1 ether);
        assertEq(buybacks.buybackReserveEth(), 0);
    }

    function test_DirectFacetCallCannotTrapNativeFunding() public {
        BuybackFacet facet = new BuybackFacet();
        uint256 aliceBefore = alice.balance;

        vm.prank(alice);
        vm.expectRevert(Errors.InvalidAddress.selector);
        facet.fundBuybackReserve{value: 1 ether}();

        assertEq(address(facet).balance, 0);
        assertEq(alice.balance, aliceBefore);
    }

    function test_FundingIgnoresPurchaseActivationPauseLaunchAndFinalization() public {
        assertFalse(governance.purchasesInitialized());

        vm.prank(alice);
        buybacks.fundBuybackReserve{value: 1 ether}();

        vm.prank(guardian);
        governance.setPaused(true);
        vm.prank(bob);
        buybacks.fundBuybackReserve{value: 2 ether}();

        vm.prank(authority);
        governance.finalizeProtocol();
        vm.prank(alice);
        buybacks.fundBuybackReserve{value: 3 ether}();

        assertFalse(governance.purchasesInitialized());
        assertTrue(governance.paused());
        assertTrue(governance.protocolFinalized());
        assertEq(buybacks.buybackReserveEth(), 6 ether);
        assertEq(address(diamond).balance, 6 ether);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }
}
