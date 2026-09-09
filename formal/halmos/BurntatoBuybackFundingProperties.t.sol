// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction} from "../../src/shared/Types.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";

contract BurntatoBuybackFundingProperties is Test {
    address private constant FIRST_FUNDER = address(0xA11CE);
    address private constant SECOND_FUNDER = address(0xB0B);

    BurntatoDiamond private diamond;
    IBuyback private buybacks;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));

        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({
            facetAddress: address(new BuybackFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.buyback()
        });
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        buybacks = IBuyback(address(diamond));
    }

    function check_positiveFundingRequiresNoGameActivation(uint96 amount, address funder) public {
        vm.assume(amount != 0);
        vm.assume(funder != address(0) && funder != address(diamond));
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 balanceBefore = address(diamond).balance;

        vm.deal(funder, amount);
        vm.prank(funder);
        buybacks.fundBuybackReserve{value: amount}();

        assertEq(buybacks.buybackReserveEth(), reserveBefore + amount);
        assertEq(address(diamond).balance, balanceBefore + amount);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function check_repeatedFundingIsAdditive(uint96 first, uint96 second) public {
        vm.assume(first != 0 && second != 0);

        vm.deal(FIRST_FUNDER, first);
        vm.prank(FIRST_FUNDER);
        buybacks.fundBuybackReserve{value: first}();

        vm.deal(SECOND_FUNDER, second);
        vm.prank(SECOND_FUNDER);
        buybacks.fundBuybackReserve{value: second}();

        assertEq(buybacks.buybackReserveEth(), uint256(first) + uint256(second));
        assertEq(address(diamond).balance, uint256(first) + uint256(second));
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function check_zeroFundingRevertsWithoutMutation() public {
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 balanceBefore = address(diamond).balance;

        vm.prank(FIRST_FUNDER);
        (bool success, bytes memory reason) =
            address(buybacks).call(abi.encodeCall(IBuyback.fundBuybackReserve, ()));

        assertFalse(success);
        assertEq(_selector(reason), Errors.ZeroAmount.selector);
        assertEq(buybacks.buybackReserveEth(), reserveBefore);
        assertEq(address(diamond).balance, balanceBefore);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function check_rawNativeTransferDoesNotCreditReserve(uint96 amount) public {
        vm.assume(amount != 0);
        vm.deal(FIRST_FUNDER, amount);
        vm.prank(FIRST_FUNDER);
        (bool success,) = address(diamond).call{value: amount}("");

        assertTrue(success);
        assertEq(address(diamond).balance, amount);
        assertEq(buybacks.buybackReserveEth(), 0);
        assertEq(buybacks.lastBuybackBlock(), 0);
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
