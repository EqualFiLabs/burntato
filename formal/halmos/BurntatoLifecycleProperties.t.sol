// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {BurntatoDiamond} from "../../src/BurntatoDiamond.sol";
import {ClaimsFacet} from "../../src/facets/ClaimsFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {GameFacet} from "../../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../../src/facets/GovernanceFacet.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {RecoveryFacet} from "../../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../../src/facets/SettlementFacet.sol";
import {TreasuryRewardsFacet} from "../../src/facets/TreasuryRewardsFacet.sol";
import {FoundationInit} from "../../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {ITreasuryRewards} from "../../src/interfaces/ITreasuryRewards.sol";
import {Errors} from "../../src/shared/Errors.sol";
import {FacetCut, FacetCutAction, ProtocolConfig, RewardSchedule, Round} from "../../src/shared/Types.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";
import {LibProtocolStorage} from "../../src/libraries/LibProtocolStorage.sol";

contract FormalNativeReceiver {
    receive() external payable {}
}

contract FormalLifecycleStateFacet {
    function formalExpireCurrentRound() external {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        gs.rounds[gs.currentRoundId].deadline = block.timestamp;
    }
}

contract BurntatoLifecycleProperties is Test {
    uint256 private constant PRICE = 10_000;
    uint256 private constant COMMITMENT = 100;
    uint256 private constant GENESIS_SEED = 1 ether;
    address private constant TREASURY = address(0xBEEF);
    address private constant BUYER_ONE = address(0xA11CE);
    address private constant BUYER_TWO = address(0xB0B);
    address private constant COMMITTER = address(0xCAFE);
    address private constant ALLOCATOR = address(0xD00D);

    BurntatoDiamond private diamond;
    IClaims private claims;
    IGame private game;
    IGovernance private governance;
    IPotatoToken private potato;
    IRecovery private recovery;
    ISettlement private settlement;
    ITreasuryRewards private rewards;
    FormalNativeReceiver private receiver;
    FormalLifecycleStateFacet private lifecycleState;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));

        FormalLifecycleStateFacet lifecycleStateFacet = new FormalLifecycleStateFacet();
        bytes4[] memory lifecycleStateSelectors = new bytes4[](1);
        lifecycleStateSelectors[0] = FormalLifecycleStateFacet.formalExpireCurrentRound.selector;

        FacetCut[] memory cuts = new FacetCut[](8);
        cuts[0] = FacetCut(address(new GovernanceFacet()), FacetCutAction.Add, BurntatoSelectors.governance());
        cuts[1] = FacetCut(address(new PotatoTokenFacet()), FacetCutAction.Add, BurntatoSelectors.token());
        cuts[2] = FacetCut(address(new GameFacet()), FacetCutAction.Add, BurntatoSelectors.game());
        cuts[3] = FacetCut(address(new RecoveryFacet()), FacetCutAction.Add, BurntatoSelectors.recovery());
        cuts[4] = FacetCut(address(new SettlementFacet()), FacetCutAction.Add, BurntatoSelectors.settlement());
        cuts[5] = FacetCut(address(new ClaimsFacet()), FacetCutAction.Add, BurntatoSelectors.claims());
        cuts[6] =
            FacetCut(address(new TreasuryRewardsFacet()), FacetCutAction.Add, BurntatoSelectors.treasuryRewards());
        cuts[7] = FacetCut(address(lifecycleStateFacet), FacetCutAction.Add, lifecycleStateSelectors);

        FoundationInit foundation = new FoundationInit();
        IDiamondCut(address(diamond)).diamondCut(
            cuts,
            address(foundation),
            abi.encodeCall(FoundationInit.initialize, (_config(PRICE, 100), TREASURY, address(0), GENESIS_SEED, 0))
        );

        claims = IClaims(address(diamond));
        game = IGame(address(diamond));
        governance = IGovernance(address(diamond));
        potato = IPotatoToken(address(diamond));
        recovery = IRecovery(address(diamond));
        settlement = ISettlement(address(diamond));
        rewards = ITreasuryRewards(address(diamond));
        receiver = new FormalNativeReceiver();
        lifecycleState = FormalLifecycleStateFacet(address(diamond));
        governance.initializePurchases();
    }

    function check_winnerClaimPaysExactPoolOnce() public {
        _buy(BUYER_ONE);
        _buy(BUYER_TWO);
        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 2_500);
        uint256 winnerBefore = address(receiver).balance;

        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        vm.prank(BUYER_TWO);
        uint256 claimed = claims.claimWinner(1, address(receiver));

        assertEq(claimed, 2_500);
        assertEq(address(receiver).balance, winnerBefore + claimed);
        assertTrue(claims.winnerClaimed(1));

        vm.prank(BUYER_TWO);
        (bool replayed, bytes memory reason) =
            address(claims).call(abi.encodeCall(IClaims.claimWinner, (uint256(1), address(receiver))));
        assertFalse(replayed);
        assertEq(_selector(reason), Errors.AlreadyClaimed.selector);
    }

    function check_singleRecoveryCommitmentReceivesExactPoolAndBurnsExactly() public {
        _protocolMint(COMMITTER, COMMITMENT);
        _buy(BUYER_ONE);
        _buy(BUYER_TWO);

        vm.prank(COMMITTER);
        recovery.commitRecovery(COMMITMENT);
        assertEq(recovery.recoveryCommitment(2, COMMITTER), COMMITMENT);
        assertEq(recovery.totalRecoveryCommitment(2), COMMITMENT);

        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        assertEq(game.getRound(2).recoveryPool, 4_000);

        _buy(BUYER_ONE);
        _buy(BUYER_TWO);
        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.recoveryPool, 8_000);
        uint256 supplyBeforeSettlement = potato.totalSupply();
        uint256 treasuryAvailableBefore = claims.treasuryPotatoAvailable();

        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();

        assertEq(potato.totalSupply(), supplyBeforeSettlement - 90);
        assertEq(claims.treasuryPotatoAvailable(), treasuryAvailableBefore + 10);
        assertEq(claims.claimableRecovery(2, COMMITTER), 8_000);

        uint256 committerEthBefore = address(receiver).balance;
        vm.prank(COMMITTER);
        uint256 claimed = claims.claimRecovery(2, address(receiver));
        assertEq(claimed, 8_000);
        assertEq(address(receiver).balance, committerEthBefore + claimed);
        assertEq(claims.claimableRecovery(2, COMMITTER), 0);
        assertTrue(claims.recoveryClaimed(2, COMMITTER));
    }

    function check_snapshottedRoundKeepsConfigAndLaterSnapshotUsesNewConfig() public {
        _buy(BUYER_ONE);
        Round memory activeBefore = game.getRound(1);
        assertEq(activeBefore.config.startingPrice, PRICE);
        assertEq(activeBefore.config.roundTimeout, 100);

        governance.setProtocolConfig(_config(PRICE * 2, 200));
        Round memory activeAfter = game.getRound(1);
        assertEq(activeAfter.config.startingPrice, PRICE);
        assertEq(activeAfter.config.roundTimeout, 100);

        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        Round memory next = game.getRound(2);
        assertEq(next.config.startingPrice, PRICE);
        assertEq(next.config.roundTimeout, 100);
        assertEq(next.nextPrice, PRICE);

        _buy(BUYER_ONE);
        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        Round memory later = game.getRound(3);
        assertEq(later.config.startingPrice, PRICE * 2);
        assertEq(later.config.roundTimeout, 200);
        assertEq(later.nextPrice, PRICE * 2);
    }

    function test_WinnerClaimWitness() public {
        check_winnerClaimPaysExactPoolOnce();
    }

    function test_RecoveryClaimWitness() public {
        check_singleRecoveryCommitmentReceivesExactPoolAndBurnsExactly();
    }

    function test_ConfigSnapshotWitness() public {
        check_snapshottedRoundKeepsConfigAndLaterSnapshotUsesNewConfig();
    }

    function test_RewardScheduleWitness() public {
        check_rewardAllocationCancellationConservesInventory();
    }

    function check_rewardAllocationCancellationConservesInventory() public {
        uint256 amount = 101;
        uint256 inventoryBefore = claims.treasuryPotatoAvailable();
        _protocolMint(ALLOCATOR, amount);
        rewards.setRewardAllocator(ALLOCATOR);

        vm.prank(ALLOCATOR);
        uint256 scheduleId = rewards.allocateTreasuryRewards(amount, 1, 10);
        RewardSchedule memory schedule = rewards.rewardSchedule(scheduleId);
        assertEq(schedule.perRound * schedule.roundCount + schedule.firstRoundRemainder, amount);
        assertEq(rewards.treasuryRewardsReserved(), amount);
        assertEq(claims.treasuryPotatoAvailable(), inventoryBefore);
        assertEq(potato.balanceOf(address(diamond)), GENESIS_SEED + amount);

        vm.prank(ALLOCATOR);
        uint256 released = rewards.cancelTreasuryRewards(scheduleId);
        assertEq(released, amount);
        assertEq(rewards.treasuryRewardsReserved(), 0);
        assertEq(claims.treasuryPotatoAvailable(), inventoryBefore + amount);
        assertEq(potato.balanceOf(address(diamond)), GENESIS_SEED + amount);
    }

    function _buy(address buyer) private {
        vm.deal(buyer, PRICE);
        vm.prank(buyer);
        game.buyPotato{value: PRICE}();
    }

    function _protocolMint(address recipient, uint256 amount) private {
        vm.prank(address(diamond));
        potato.protocolMint(recipient, amount);
    }

    function _config(uint256 price, uint256 timeout) private pure returns (ProtocolConfig memory config) {
        config = ProtocolConfig({
            startingPrice: price,
            priceIncreaseBps: 0,
            roundTimeout: timeout,
            roundEmissionBudget: 0,
            emissionStepBps: 0,
            emissionVestingDuration: 1,
            winnerBps: 2_500,
            nextRoundWinnerBps: 200,
            recoveryBps: 4_000,
            treasuryBps: 2_300,
            buybackBps: 1_000,
            operatorPurchaseBps: 0,
            recoveryBurnBps: 9_000,
            recoveryTreasuryBps: 1_000,
            roundTimeoutDecay: 0,
            minimumRoundTimeout: timeout
        });
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
