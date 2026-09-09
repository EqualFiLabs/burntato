// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";

contract BurntatoPauseProperties is Test {
    address private constant FINAL_ADMIN = address(0xA11CE);
    address private constant GUARDIAN = address(0xB0B);
    address private constant RECIPIENT = address(0xCAFE);
    address private constant TREASURY = address(0xBEEF);

    BurntatoDiamond private diamond;
    IGovernance private governance;
    IPotatoToken private potato;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));

        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut({
            facetAddress: address(new GovernanceFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.governance()
        });
        cuts[1] = FacetCut({
            facetAddress: address(new PotatoTokenFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.token()
        });

        FoundationInit foundation = new FoundationInit();
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts,
                address(foundation),
                abi.encodeCall(FoundationInit.initialize, (_config(), TREASURY, address(0), 1 ether))
            );

        governance = IGovernance(address(diamond));
        potato = IPotatoToken(address(diamond));
        governance.setGuardian(GUARDIAN);
        governance.initializePurchases();
        governance.setAuthority(FINAL_ADMIN);
    }

    function check_guardianCanPauseButCannotUnpause() public {
        vm.prank(GUARDIAN);
        governance.setPaused(true);
        assertTrue(governance.paused());

        vm.prank(GUARDIAN);
        (bool success, bytes memory reason) = address(governance).call(abi.encodeCall(IGovernance.setPaused, (false)));
        assertFalse(success);
        assertEq(_selector(reason), Errors.UnpauseRequiresAuthority.selector);
        assertTrue(governance.paused());
    }

    function check_unauthorizedCallerCannotPause(address caller) public {
        vm.assume(caller != address(0) && caller != FINAL_ADMIN && caller != GUARDIAN);
        vm.prank(caller);
        (bool success, bytes memory reason) = address(governance).call(abi.encodeCall(IGovernance.setPaused, (true)));
        assertFalse(success);
        assertEq(_selector(reason), Errors.NotGuardian.selector);
        assertFalse(governance.paused());
    }

    function check_authorityCanUnpause() public {
        vm.prank(GUARDIAN);
        governance.setPaused(true);

        vm.prank(FINAL_ADMIN);
        governance.setPaused(false);
        assertFalse(governance.paused());
    }

    function check_pausedProtocolMintRevertsWithoutSupplyChange(uint96 amount) public {
        vm.prank(GUARDIAN);
        governance.setPaused(true);
        uint256 supplyBefore = potato.totalSupply();
        uint256 balanceBefore = potato.balanceOf(RECIPIENT);

        vm.prank(address(diamond));
        (bool success, bytes memory reason) =
            address(potato).call(abi.encodeCall(IPotatoToken.protocolMint, (RECIPIENT, uint256(amount))));

        assertFalse(success);
        assertEq(_selector(reason), Errors.ProtocolPaused.selector);
        assertEq(potato.totalSupply(), supplyBefore);
        assertEq(potato.balanceOf(RECIPIENT), balanceBefore);
    }

    function check_authorityCannotRelinquishBeforeGuardianClear() public {
        vm.prank(FINAL_ADMIN);
        (bool success, bytes memory reason) =
            address(governance).call(abi.encodeCall(IGovernance.setAuthority, (address(0))));
        assertFalse(success);
        assertEq(_selector(reason), Errors.UnsafeAuthorityRenunciation.selector);
        assertEq(governance.authority(), FINAL_ADMIN);
    }

    function _config() private pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            startingPrice: 1,
            priceIncreaseBps: 0,
            roundTimeout: 1,
            roundEmissionBudget: 0,
            emissionStepBps: 0,
            emissionVestingDuration: 1,
            winnerBps: 10_000,
            recoveryBps: 0,
            treasuryBps: 0,
            buybackBps: 0,
            operatorPurchaseBps: 0,
            recoveryBurnBps: 10_000,
            recoveryTreasuryBps: 0,
            roundTimeoutDecay: 0,
            minimumRoundTimeout: 1
        });
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
