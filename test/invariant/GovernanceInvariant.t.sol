// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {FacetCut, FacetCutAction} from "../../src/shared/Types.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract ReplacementGameFacet {
    function buyPotato() external payable {}
}

contract GovernanceHandler is Test {
    address internal immutable diamond;
    address internal immutable authority;
    address internal immutable originalGuardian;
    IGovernance internal immutable governance;
    ReplacementGameFacet internal immutable replacement;

    bool public administrationBlockedAfterFinalization;
    bool public cutSucceededAfterFinalization;
    bool public guardianAuthorityBypass;
    bool public guardianUnpauseBypass;

    constructor(address diamond_, address authority_, address guardian_) {
        diamond = diamond_;
        authority = authority_;
        originalGuardian = guardian_;
        governance = IGovernance(diamond_);
        replacement = new ReplacementGameFacet();
    }

    function guardianPause() external {
        vm.prank(originalGuardian);
        try governance.setPauseState(true, true) {} catch {}
    }

    function guardianAttemptUnpause() external {
        bool wasPaused = governance.purchasesPaused() || governance.commitmentsPaused();
        vm.prank(originalGuardian);
        try governance.setPauseState(false, false) {
            if (wasPaused) guardianUnpauseBypass = true;
        } catch {}
    }

    function mutateConfig(uint128 rawPrice, uint16 rawBps) external {
        uint256 price = bound(uint256(rawPrice), 1, 1_000 ether);
        uint16 bps = uint16(bound(uint256(rawBps), 1, 10_000));
        bool wasFinalized = governance.protocolFinalized();
        vm.prank(authority);
        try governance.setProtocolConfig(price, bps) {}
        catch {
            if (wasFinalized) administrationBlockedAfterFinalization = true;
        }
    }

    function authorityUnpause() external {
        bool wasFinalized = governance.protocolFinalized();
        vm.prank(authority);
        try governance.setPauseState(false, false) {}
        catch {
            if (wasFinalized) administrationBlockedAfterFinalization = true;
        }
    }

    function attemptGameReplacement() external {
        bool wasFinalized = governance.protocolFinalized();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGame.buyPotato.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(replacement), FacetCutAction.Replace, selectors);
        vm.prank(authority);
        try IDiamondCut(diamond).diamondCut(cuts, address(0), "") {
            if (wasFinalized) cutSucceededAfterFinalization = true;
        } catch {}
    }

    function attemptGuardianRedirect(uint256 rawRecipient) external {
        address recipient = address(uint160(rawRecipient));
        if (recipient == address(0)) recipient = address(1);
        vm.prank(originalGuardian);
        try governance.setTreasuryRecipient(recipient) {
            guardianAuthorityBypass = true;
        } catch {}
    }

    function finalize() external {
        vm.prank(authority);
        try governance.finalizeProtocol() {} catch {}
    }
}

contract GovernanceInvariantTest is DiamondTestSetup {
    GovernanceHandler internal handler;

    function setUp() public {
        _deployCore();
        handler = new GovernanceHandler(address(diamond), authority, guardian);
        targetContract(address(handler));
    }

    function invariant_FinalizationOnlyDisablesCuts() public view {
        assertFalse(handler.administrationBlockedAfterFinalization());
        assertFalse(handler.cutSucceededAfterFinalization());
        assertFalse(handler.guardianAuthorityBypass());
        assertFalse(handler.guardianUnpauseBypass());
    }
}
