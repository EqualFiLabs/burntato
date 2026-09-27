// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {BuybackFacet} from "../../src/facets/BuybackFacet.sol";
import {ClaimsFacet} from "../../src/facets/ClaimsFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {GameFacet} from "../../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {RecoveryFacet} from "../../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../../src/facets/SettlementFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {BuybackConfig, FacetCut, FacetCutAction, ProtocolConfig} from "../../src/shared/Types.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";

contract BurntatoPauseProperties is Test {
    address private constant FINAL_ADMIN = address(0xA11CE);
    address private constant GUARDIAN = address(0xB0B);
    address private constant RECIPIENT = address(0xCAFE);
    address private constant TREASURY = address(0xBEEF);

    BurntatoDiamond private diamond;
    IGovernance private governance;
    IBuyback private buybacks;
    IClaims private claims;
    IGame private game;
    IPotatoToken private potato;
    IRecovery private recovery;
    ISettlement private settlement;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));

        FacetCut[] memory cuts = new FacetCut[](7);
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
        cuts[2] = FacetCut({
            facetAddress: address(new BuybackFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.buyback()
        });
        cuts[3] = FacetCut({
            facetAddress: address(new GameFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.game()
        });
        cuts[4] = FacetCut({
            facetAddress: address(new RecoveryFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.recovery()
        });
        cuts[5] = FacetCut({
            facetAddress: address(new SettlementFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.settlement()
        });
        cuts[6] = FacetCut({
            facetAddress: address(new ClaimsFacet()),
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.claims()
        });

        FoundationInit foundation = new FoundationInit();
        IDiamondCut(address(diamond))
            .diamondCut(
                cuts,
                address(foundation),
                abi.encodeCall(FoundationInit.initialize, (_config(), TREASURY, address(0), 1 ether, 0))
            );

        governance = IGovernance(address(diamond));
        buybacks = IBuyback(address(diamond));
        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        buybacks.setBuybackConfig(BuybackConfig({maxSpend: 1 ether, callerRewardBps: 50, delayBlocks: 1}));
        vm.deal(address(this), 1 ether);
        buybacks.fundBuybackReserve{value: 1 ether}();
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

    function check_pausedBuybackRevertsWithoutAccountingChange() public {
        vm.prank(GUARDIAN);
        governance.setPaused(true);
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 lastExecutionBlock = buybacks.lastBuybackBlock();
        uint256 callerBefore = RECIPIENT.balance;
        uint256 treasuryBefore = potato.balanceOf(TREASURY);

        vm.prank(RECIPIENT);
        (bool success, bytes memory reason) = address(buybacks).call(abi.encodeCall(IBuyback.buyback, ()));

        assertFalse(success);
        assertEq(_selector(reason), Errors.ProtocolPaused.selector);
        assertEq(buybacks.buybackReserveEth(), reserveBefore);
        assertEq(buybacks.lastBuybackBlock(), lastExecutionBlock);
        assertEq(RECIPIENT.balance, callerBefore);
        assertEq(potato.balanceOf(TREASURY), treasuryBefore);
    }

    function check_globalPauseRejectsEveryProtectedTransition() public {
        vm.prank(GUARDIAN);
        governance.setPaused(true);

        uint256 supplyBefore = potato.totalSupply();
        uint256 roundBefore = game.currentRoundId();
        uint256 winnerReserveBefore = game.winnerReserveEth();
        uint256 recoveryReserveBefore = recovery.recoveryReserveEth();
        uint256 buybackReserveBefore = buybacks.buybackReserveEth();

        _assertProtocolPaused(address(game), abi.encodeCall(IGame.buyPotato, ()));
        _assertProtocolPaused(address(game), abi.encodeCall(IGame.materializeMaturedEmission, ()));
        _assertProtocolPaused(address(recovery), abi.encodeCall(IRecovery.commitRecovery, (uint256(1))));
        _assertProtocolPaused(address(settlement), abi.encodeCall(ISettlement.settleRound, ()));
        _assertProtocolPaused(address(claims), abi.encodeCall(IClaims.claimWinner, (uint256(1), RECIPIENT)));
        _assertProtocolPaused(address(claims), abi.encodeCall(IClaims.claimRecovery, (uint256(1), RECIPIENT)));
        _assertProtocolPaused(address(claims), abi.encodeCall(IClaims.claimTreasury, ()));
        _assertProtocolPaused(address(claims), abi.encodeCall(IClaims.claimTreasuryPotato, ()));

        vm.prank(address(diamond));
        _assertProtocolPaused(address(potato), abi.encodeCall(IPotatoToken.protocolMint, (RECIPIENT, uint256(1))));

        assertEq(potato.totalSupply(), supplyBefore);
        assertEq(game.currentRoundId(), roundBefore);
        assertEq(game.winnerReserveEth(), winnerReserveBefore);
        assertEq(recovery.recoveryReserveEth(), recoveryReserveBefore);
        assertEq(buybacks.buybackReserveEth(), buybackReserveBefore);
        assertTrue(governance.paused());
    }

    function check_pausedDirectFundingRemainsAvailable(uint96 amount) public {
        vm.assume(amount > 0);
        vm.prank(GUARDIAN);
        governance.setPaused(true);
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 lastExecutionBlock = buybacks.lastBuybackBlock();
        vm.deal(RECIPIENT, amount);

        vm.prank(RECIPIENT);
        buybacks.fundBuybackReserve{value: amount}();

        assertEq(buybacks.buybackReserveEth(), reserveBefore + amount);
        assertEq(buybacks.lastBuybackBlock(), lastExecutionBlock);
        assertTrue(governance.paused());
    }

    function check_pausedRoundFundingRemainsAvailable(uint96 winnerAmount, uint96 recoveryAmount) public {
        uint256 total = uint256(winnerAmount) + uint256(recoveryAmount);
        vm.assume(total > 0);
        vm.prank(GUARDIAN);
        governance.setPaused(true);
        vm.deal(RECIPIENT, total);

        vm.prank(RECIPIENT);
        game.fundRoundReserves{value: total}(1, winnerAmount, recoveryAmount);

        (uint256 winnerReserve, uint256 recoveryReserve) = game.roundReserves(1);
        assertEq(winnerReserve, winnerAmount);
        assertEq(recoveryReserve, recoveryAmount);
        assertEq(game.winnerReserveEth(), winnerAmount);
        assertEq(recovery.recoveryReserveEth(), recoveryAmount);
        assertTrue(governance.paused());
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
            nextRoundWinnerBps: 0,
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

    function _assertProtocolPaused(address target, bytes memory data) private {
        (bool success, bytes memory reason) = target.call(data);
        assertFalse(success);
        assertEq(_selector(reason), Errors.ProtocolPaused.selector);
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
