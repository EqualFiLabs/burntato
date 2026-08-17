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
    bytes32 internal constant CONFIG_KEY = keccak256("burntato.parameter.protocol-config");

    address internal immutable diamond;
    address internal immutable authority;
    address internal immutable originalGuardian;
    IGovernance internal immutable governance;
    ReplacementGameFacet internal immutable replacement;

    bool public frozenMutationBypass;
    bool public finalizationBypass;
    bool public guardianAuthorityBypass;
    bool public selectorFreezeBypass;

    constructor(address diamond_, address authority_, address guardian_) {
        diamond = diamond_;
        authority = authority_;
        originalGuardian = guardian_;
        governance = IGovernance(diamond_);
        replacement = new ReplacementGameFacet();
    }

    function setPause(uint256 rawFlags) external {
        vm.prank(originalGuardian);
        try governance.setPauseState((rawFlags & 1) != 0, (rawFlags & 2) != 0) {
            if (governance.protocolFinalized()) finalizationBypass = true;
        } catch {}
    }

    function mutateConfig(uint128 rawPrice, uint16 rawBps) external {
        bool wasFrozen = governance.parameterFrozen(CONFIG_KEY);
        bool wasFinalized = governance.protocolFinalized();
        uint256 price = bound(uint256(rawPrice), 1, 1_000 ether);
        uint16 bps = uint16(bound(uint256(rawBps), 1, 10_000));
        vm.prank(authority);
        try governance.setProtocolConfig(price, bps) {
            if (wasFrozen) frozenMutationBypass = true;
            if (wasFinalized) finalizationBypass = true;
        } catch {}
    }

    function freezeConfig() external {
        vm.prank(authority);
        try governance.freezeParameter(CONFIG_KEY) {} catch {}
    }

    function freezeGameSelector() external {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGame.buyPotato.selector;
        vm.prank(authority);
        try governance.freezeSelectors(selectors) {} catch {}
    }

    function attemptGameReplacement() external {
        bool wasFrozen = governance.selectorFrozen(IGame.buyPotato.selector);
        bool wasFinalized = governance.protocolFinalized();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGame.buyPotato.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(replacement), FacetCutAction.Replace, selectors);
        vm.prank(authority);
        try IDiamondCut(diamond).diamondCut(cuts, address(0), "") {
            if (wasFrozen) selectorFreezeBypass = true;
            if (wasFinalized) finalizationBypass = true;
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

    function invariant_FrozenAndFinalizedAuthorityNeverRecovers() public view {
        assertFalse(handler.frozenMutationBypass());
        assertFalse(handler.selectorFreezeBypass());
        assertFalse(handler.finalizationBypass());
        assertFalse(handler.guardianAuthorityBypass());
    }

    function invariant_FinalizationAlwaysClearsEmergencyAuthority() public view {
        IGovernance governance = IGovernance(address(diamond));
        if (!governance.protocolFinalized()) return;
        assertEq(governance.guardian(), address(0));
        assertFalse(governance.purchasesPaused());
        assertFalse(governance.commitmentsPaused());
    }
}
