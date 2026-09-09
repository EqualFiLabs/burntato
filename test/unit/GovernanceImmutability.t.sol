// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";

contract ReplacementAuthorityFacet {
    function authority() external pure returns (address) {
        return address(1);
    }
}

contract GovernanceAdministrationTest is Test {
    uint256 internal constant DELAY = 1 days;

    address internal bootstrap = makeAddr("bootstrap");
    address internal proposer = makeAddr("proposer");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");

    BurntatoDiamond internal diamond;
    DiamondCutFacet internal cutFacet;
    GovernanceFacet internal governanceFacet;
    TimelockController internal timelock;

    function setUp() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(DELAY, proposers, executors, address(0));

        cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(bootstrap, address(cutFacet));
        governanceFacet = new GovernanceFacet();
        FoundationInit initializer = new FoundationInit();

        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(governanceFacet), FacetCutAction.Add, _governanceSelectors());
        vm.prank(bootstrap);
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts,
                address(initializer),
                abi.encodeCall(FoundationInit.initialize, (_config(0.01 ether, 1_000), treasury, address(0), 1 ether))
            );

        vm.startPrank(bootstrap);
        IGovernance(address(diamond)).setGuardian(guardian);
        IGovernance(address(diamond)).initializePurchases();
        IGovernance(address(diamond)).setAuthority(address(timelock));
        vm.stopPrank();
    }

    function test_TimelockIsSoleConfigurationAuthority() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, address(this)));
        IGovernance(address(diamond)).setProtocolConfig(_config(0.02 ether, 2_000));

        _scheduleAndExecute(abi.encodeCall(IGovernance.setProtocolConfig, (_config(0.02 ether, 2_000))));
        assertEq(IGovernance(address(diamond)).authority(), address(timelock));
    }

    function test_ProtocolConfigurationAcceptsZeroRatesAndEmissionBudget() public {
        ProtocolConfig memory config = _config(0.02 ether, 0);
        config.roundEmissionBudget = 0;
        config.emissionStepBps = 0;
        config.winnerBps = 0;
        config.recoveryBps = 0;
        config.treasuryBps = 10_000;
        config.buybackBps = 0;
        config.recoveryBurnBps = 0;
        config.recoveryTreasuryBps = 10_000;

        vm.prank(address(timelock));
        IGovernance(address(diamond)).setProtocolConfig(config);
        ProtocolConfig memory actual = IGovernance(address(diamond)).protocolConfig();
        assertEq(actual.startingPrice, config.startingPrice);
        assertEq(actual.priceIncreaseBps, 0);
        assertEq(actual.roundEmissionBudget, 0);
        assertEq(actual.emissionStepBps, 0);
        assertEq(actual.treasuryBps, 10_000);
        assertEq(actual.recoveryTreasuryBps, 10_000);
    }

    function test_ProtocolConfigurationRejectsInvalidDomains() public {
        ProtocolConfig memory config = _config(0.02 ether, 1_000);
        config.roundTimeout = 0;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.emissionVestingDuration = 0;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.roundTimeout = uint256(type(uint64).max) + 1;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.minimumRoundTimeout = 0;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.minimumRoundTimeout = config.roundTimeout + 1;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.roundTimeoutDecay = config.roundTimeout + 1;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.priceIncreaseBps = 10_001;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.winnerBps = 2_499;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.operatorPurchaseBps = 10_001;
        config.treasuryBps = 0;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.operatorPurchaseBps = 1;
        _expectInvalidConfig(config);

        config = _config(0.02 ether, 1_000);
        config.recoveryTreasuryBps = 999;
        _expectInvalidConfig(config);
    }

    function test_ProtocolConfigurationCannotEnablePurchaseRewardsWithoutRouter() public {
        ProtocolConfig memory config = _config(0.02 ether, 1_000);
        config.recoveryBps = 3_000;
        config.treasuryBps = 2_000;
        config.operatorPurchaseBps = 1_500;

        _expectInvalidConfig(config);
    }

    function test_GuardianCanPauseButCannotAdminister() public {
        vm.expectEmit(false, false, false, true, address(diamond));
        emit IGovernance.PauseStateUpdated(true);
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);
        assertTrue(IGovernance(address(diamond)).paused());

        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);
        assertTrue(IGovernance(address(diamond)).paused());

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, guardian));
        IGovernance(address(diamond)).setTreasuryRecipient(guardian);
    }

    function test_NonGuardianCannotChangePauseState() public {
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotGuardian.selector, proposer));
        IGovernance(address(diamond)).setPaused(true);
        assertFalse(IGovernance(address(diamond)).paused());
    }

    function test_GuardianCannotUnpauseButTimelockCan() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnpauseRequiresAuthority.selector, guardian));
        IGovernance(address(diamond)).setPaused(false);

        _scheduleAndExecute(abi.encodeCall(IGovernance.setPaused, (false)));
        assertFalse(IGovernance(address(diamond)).paused());
    }

    function test_AuthorityCanTransferRepeatedlyToAnyAddress() public {
        BurntatoDiamond candidate = _deployBootstrapGovernance();

        vm.prank(bootstrap);
        IGovernance(address(candidate)).setAuthority(proposer);
        assertEq(IGovernance(address(candidate)).authority(), proposer);

        vm.prank(proposer);
        IGovernance(address(candidate)).setAuthority(guardian);
        assertEq(IGovernance(address(candidate)).authority(), guardian);
    }

    function test_AuthorityCannotRelinquishBeforePurchaseInitialization() public {
        BurntatoDiamond candidate = _deployBootstrapGovernance();
        IGovernance candidateGovernance = IGovernance(address(candidate));
        assertFalse(candidateGovernance.purchasesInitialized());
        assertEq(candidateGovernance.guardian(), address(0));
        assertFalse(candidateGovernance.paused());

        vm.prank(bootstrap);
        vm.expectRevert(Errors.UnsafeAuthorityRenunciation.selector);
        candidateGovernance.setAuthority(address(0));
        assertEq(candidateGovernance.authority(), bootstrap);

        vm.startPrank(bootstrap);
        candidateGovernance.initializePurchases();
        candidateGovernance.setAuthority(address(0));
        vm.stopPrank();
        assertEq(candidateGovernance.authority(), address(0));
    }

    function test_AuthorityCannotRelinquishWhileGuardianRemains() public {
        vm.prank(address(timelock));
        vm.expectRevert(Errors.UnsafeAuthorityRenunciation.selector);
        IGovernance(address(diamond)).setAuthority(address(0));
        assertEq(IGovernance(address(diamond)).authority(), address(timelock));
    }

    function test_AuthorityCannotRelinquishWhilePaused() public {
        vm.startPrank(address(timelock));
        IGovernance(address(diamond)).setGuardian(address(0));
        IGovernance(address(diamond)).setPaused(true);
        vm.expectRevert(Errors.UnsafeAuthorityRenunciation.selector);
        IGovernance(address(diamond)).setAuthority(address(0));
        vm.stopPrank();

        assertEq(IGovernance(address(diamond)).authority(), address(timelock));
    }

    function test_AuthorityCanRelinquishAfterGuardianClearAndUnpause() public {
        vm.startPrank(address(timelock));
        IGovernance(address(diamond)).setPaused(true);
        IGovernance(address(diamond)).setGuardian(address(0));
        IGovernance(address(diamond)).setPaused(false);
        IGovernance(address(diamond)).setAuthority(address(0));
        vm.stopPrank();

        assertEq(IGovernance(address(diamond)).authority(), address(0));
        assertEq(IGovernance(address(diamond)).guardian(), address(0));
        assertFalse(IGovernance(address(diamond)).paused());

        vm.prank(address(timelock));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, address(timelock)));
        IGovernance(address(diamond)).setGuardian(guardian);
    }

    function test_SelectorReplacementWorksUntilFinalization() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGovernance.authority.selector;
        ReplacementAuthorityFacet replacement = new ReplacementAuthorityFacet();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(replacement), FacetCutAction.Replace, selectors);

        vm.prank(address(timelock));
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
        assertEq(IGovernance(address(diamond)).authority(), address(1));
    }

    function test_FinalizationOnlyDisablesDiamondCuts() public {
        vm.prank(guardian);
        IGovernance(address(diamond)).setPaused(true);

        _scheduleAndExecute(abi.encodeCall(IGovernance.finalizeProtocol, ()));
        IGovernance governance = IGovernance(address(diamond));
        assertTrue(governance.protocolFinalized());
        assertEq(governance.guardian(), guardian);
        assertTrue(governance.paused());

        address nextGuardian = makeAddr("nextGuardian");
        address nextTreasury = makeAddr("nextTreasury");
        vm.startPrank(address(timelock));
        governance.setProtocolConfig(_config(0.02 ether, 2_000));
        governance.setTreasuryRecipient(nextTreasury);
        governance.setGuardian(nextGuardian);
        governance.setPaused(false);
        governance.setAuthority(proposer);
        vm.stopPrank();

        assertEq(governance.guardian(), nextGuardian);
        assertEq(governance.authority(), proposer);
        assertFalse(governance.paused());

        FacetCut[] memory cuts = new FacetCut[](0);
        vm.prank(proposer);
        vm.expectRevert(Errors.CutsDisabled.selector);
        IDiamondCut(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _scheduleAndExecute(bytes memory data) internal {
        bytes32 salt = keccak256(data);
        vm.prank(proposer);
        timelock.schedule(address(diamond), 0, data, bytes32(0), salt, DELAY);
        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(diamond), 0, data, bytes32(0), salt);
    }

    function _expectInvalidConfig(ProtocolConfig memory config) internal {
        vm.prank(address(timelock));
        vm.expectRevert(Errors.InvalidProtocolConfig.selector);
        IGovernance(address(diamond)).setProtocolConfig(config);
    }

    function _deployBootstrapGovernance() internal returns (BurntatoDiamond candidate) {
        DiamondCutFacet candidateCut = new DiamondCutFacet();
        candidate = new BurntatoDiamond(bootstrap, address(candidateCut));
        GovernanceFacet candidateGovernance = new GovernanceFacet();
        FoundationInit initializer = new FoundationInit();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(candidateGovernance), FacetCutAction.Add, _governanceSelectors());
        vm.prank(bootstrap);
        IDiamondCut(address(candidate))
            .diamondCut(
                cuts,
                address(initializer),
                abi.encodeCall(FoundationInit.initialize, (_config(0.01 ether, 1_000), treasury, address(0), 1 ether))
            );
    }

    function _config(uint256 price, uint16 increaseBps) internal pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            startingPrice: price,
            priceIncreaseBps: increaseBps,
            roundTimeout: 1 hours,
            roundEmissionBudget: 100_000 ether,
            emissionStepBps: 1_000,
            emissionVestingDuration: 120 seconds,
            winnerBps: 2_500,
            recoveryBps: 4_000,
            treasuryBps: 2_500,
            buybackBps: 1_000,
            operatorPurchaseBps: 0,
            recoveryBurnBps: 9_000,
            recoveryTreasuryBps: 1_000,
            roundTimeoutDecay: 5 minutes,
            minimumRoundTimeout: 5 minutes
        });
    }

    function _governanceSelectors() internal pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](14);
        selectors[0] = IGovernance.authority.selector;
        selectors[1] = IGovernance.guardian.selector;
        selectors[2] = IGovernance.paused.selector;
        selectors[3] = IGovernance.protocolFinalized.selector;
        selectors[4] = IGovernance.protocolConfig.selector;
        selectors[5] = IGovernance.setAuthority.selector;
        selectors[6] = IGovernance.setGuardian.selector;
        selectors[7] = IGovernance.setPaused.selector;
        selectors[8] = IGovernance.setProtocolConfig.selector;
        selectors[9] = IGovernance.setTreasuryRecipient.selector;
        selectors[10] = IGovernance.finalizeProtocol.selector;
        selectors[11] = IGovernance.foundationConfigured.selector;
        selectors[12] = IGovernance.purchasesInitialized.selector;
        selectors[13] = IGovernance.initializePurchases.selector;
    }
}
