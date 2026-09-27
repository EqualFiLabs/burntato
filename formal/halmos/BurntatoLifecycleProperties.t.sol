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
import {LibGame} from "../../src/libraries/LibGame.sol";
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

    function formalProtocolMint(address recipient, uint256 amount) external {
        IPotatoToken(address(this)).protocolMint(recipient, amount);
    }

    function formalConfigureWinnerClaim(address holder, uint256 winnerPool) external {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[1];
        round.roundId = 1;
        round.currentHolder = holder;
        round.winnerPool = winnerPool;
        round.settled = true;
    }

    function formalConfigureRecoveryClaim(address account, uint256 commitment, uint256 recoveryPool) external {
        Round storage round = LibProtocolStorage.game().rounds[1];
        round.roundId = 1;
        round.recoveryPool = recoveryPool;
        round.totalCommitted = commitment;
        round.settled = true;
        LibProtocolStorage.RecoveryStorage storage rs = LibProtocolStorage.recovery();
        rs.commitments[1][account] = commitment;
        rs.totalCommitments[1] = commitment;
    }

    function formalSnapshotRound(uint256 roundId) external {
        LibGame.snapshotFutureRound(roundId);
    }

    function formalRoundStartingPrice(uint256 roundId) external view returns (uint256) {
        return LibProtocolStorage.game().rounds[roundId].config.startingPrice;
    }

    function formalRoundTimeout(uint256 roundId) external view returns (uint256) {
        return LibProtocolStorage.game().rounds[roundId].config.roundTimeout;
    }
}

contract FormalLifecycleActor {
    function buy(IGame game, uint256 amount) external {
        game.buyPotato{value: amount}();
    }

    function commit(IRecovery recovery, uint256 amount) external {
        recovery.commitRecovery(amount);
    }

    function claimWinner(IClaims claims, uint256 roundId, address recipient) external returns (uint256) {
        return claims.claimWinner(roundId, recipient);
    }

    function claimRecovery(IClaims claims, uint256 roundId, address recipient) external returns (uint256) {
        return claims.claimRecovery(roundId, recipient);
    }
}

contract BurntatoLifecycleProperties is Test {
    uint256 private constant PRICE = 10_000;
    uint256 private constant COMMITMENT = 100;
    uint256 private constant GENESIS_SEED = 1 ether;
    address private constant TREASURY = address(0xBEEF);
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
    FormalLifecycleActor private buyerOne;
    FormalLifecycleActor private buyerTwo;
    FormalLifecycleActor private committer;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        diamond = new BurntatoDiamond(address(this), address(cutFacet));

        FormalLifecycleStateFacet lifecycleStateFacet = new FormalLifecycleStateFacet();
        bytes4[] memory lifecycleStateSelectors = new bytes4[](7);
        lifecycleStateSelectors[0] = FormalLifecycleStateFacet.formalExpireCurrentRound.selector;
        lifecycleStateSelectors[1] = FormalLifecycleStateFacet.formalProtocolMint.selector;
        lifecycleStateSelectors[2] = FormalLifecycleStateFacet.formalConfigureWinnerClaim.selector;
        lifecycleStateSelectors[3] = FormalLifecycleStateFacet.formalConfigureRecoveryClaim.selector;
        lifecycleStateSelectors[4] = FormalLifecycleStateFacet.formalSnapshotRound.selector;
        lifecycleStateSelectors[5] = FormalLifecycleStateFacet.formalRoundStartingPrice.selector;
        lifecycleStateSelectors[6] = FormalLifecycleStateFacet.formalRoundTimeout.selector;

        FacetCut[] memory cuts = new FacetCut[](8);
        cuts[0] = FacetCut(address(new GovernanceFacet()), FacetCutAction.Add, BurntatoSelectors.governance());
        cuts[1] = FacetCut(address(new PotatoTokenFacet()), FacetCutAction.Add, BurntatoSelectors.token());
        cuts[2] = FacetCut(address(new GameFacet()), FacetCutAction.Add, BurntatoSelectors.game());
        cuts[3] = FacetCut(address(new RecoveryFacet()), FacetCutAction.Add, BurntatoSelectors.recovery());
        cuts[4] = FacetCut(address(new SettlementFacet()), FacetCutAction.Add, BurntatoSelectors.settlement());
        cuts[5] = FacetCut(address(new ClaimsFacet()), FacetCutAction.Add, BurntatoSelectors.claims());
        cuts[6] = FacetCut(address(new TreasuryRewardsFacet()), FacetCutAction.Add, BurntatoSelectors.treasuryRewards());
        cuts[7] = FacetCut(address(lifecycleStateFacet), FacetCutAction.Add, lifecycleStateSelectors);

        FoundationInit foundation = new FoundationInit();
        IDiamondCut(address(diamond))
            .diamondCut(
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
        buyerOne = new FormalLifecycleActor();
        buyerTwo = new FormalLifecycleActor();
        committer = new FormalLifecycleActor();
        vm.deal(address(buyerOne), 1 ether);
        vm.deal(address(buyerTwo), 1 ether);
        vm.deal(address(diamond), 1 ether);
        governance.initializePurchases();
    }

    function check_winnerClaimPaysConfiguredPoolOnce() public {
        lifecycleState.formalConfigureWinnerClaim(address(buyerTwo), 2_500);
        uint256 winnerBefore = address(receiver).balance;
        uint256 claimed = buyerTwo.claimWinner(claims, 1, address(receiver));

        assertEq(claimed, 2_500);
        assertEq(address(receiver).balance, winnerBefore + claimed);
        assertTrue(claims.winnerClaimed(1));

        (bool replayed, bytes memory reason) = address(buyerTwo)
            .call(abi.encodeCall(FormalLifecycleActor.claimWinner, (claims, uint256(1), address(receiver))));
        assertFalse(replayed);
        assertEq(_selector(reason), Errors.AlreadyClaimed.selector);
    }

    function check_singleRecoveryClaimReceivesConfiguredPoolOnce() public {
        lifecycleState.formalConfigureRecoveryClaim(address(committer), COMMITMENT, 8_000);
        assertEq(claims.claimableRecovery(1, address(committer)), 8_000);

        uint256 committerEthBefore = address(receiver).balance;
        uint256 claimed = committer.claimRecovery(claims, 1, address(receiver));
        assertEq(claimed, 8_000);
        assertEq(address(receiver).balance, committerEthBefore + claimed);
        assertEq(claims.claimableRecovery(1, address(committer)), 0);
        assertTrue(claims.recoveryClaimed(1, address(committer)));
    }

    function check_roundSnapshotIsStableAcrossConfigChange() public {
        lifecycleState.formalSnapshotRound(1);
        assertEq(lifecycleState.formalRoundStartingPrice(1), PRICE);
        assertEq(lifecycleState.formalRoundTimeout(1), 100);
        governance.setProtocolConfig(_config(PRICE * 2, 200));
        assertEq(lifecycleState.formalRoundStartingPrice(1), PRICE);
        assertEq(lifecycleState.formalRoundTimeout(1), 100);
        lifecycleState.formalSnapshotRound(2);
        assertEq(lifecycleState.formalRoundStartingPrice(2), PRICE * 2);
        assertEq(lifecycleState.formalRoundTimeout(2), 200);
    }

    function test_WinnerClaimWitness() public {
        _foundryWinnerClaimWitness();
    }

    function test_RecoveryClaimWitness() public {
        _foundryRecoveryClaimWitness();
    }

    function test_ConfigSnapshotWitness() public {
        _foundryConfigSnapshotWitness();
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

    function _foundryWinnerClaimWitness() private {
        _buy(buyerOne);
        _buy(buyerTwo);
        assertEq(game.getRound(1).winnerPool, 2_500);
        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        assertEq(buyerTwo.claimWinner(claims, 1, address(receiver)), 2_500);
    }

    function _foundryRecoveryClaimWitness() private {
        _protocolMint(address(committer), COMMITMENT);
        _buy(buyerOne);
        _buy(buyerTwo);
        committer.commit(recovery, COMMITMENT);
        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        _buy(buyerOne);
        _buy(buyerTwo);
        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        assertEq(committer.claimRecovery(claims, 2, address(receiver)), 8_000);
    }

    function _foundryConfigSnapshotWitness() private {
        _buy(buyerOne);
        governance.setProtocolConfig(_config(PRICE * 2, 200));
        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        assertEq(game.getRound(2).config.startingPrice, PRICE);
        _buy(buyerOne);
        lifecycleState.formalExpireCurrentRound();
        settlement.settleRound();
        assertEq(game.getRound(3).config.startingPrice, PRICE * 2);
    }

    function _buy(FormalLifecycleActor buyer) private {
        buyer.buy(game, PRICE);
    }

    function _protocolMint(address recipient, uint256 amount) private {
        lifecycleState.formalProtocolMint(recipient, amount);
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
