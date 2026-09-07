// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";
import {LibMath} from "../../src/libraries/LibMath.sol";
import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

contract ForceNativeIntoDiamond {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract ProtocolHandler is Test {
    address internal immutable diamond;
    address internal immutable guardian;

    IClaims internal immutable claims;
    IGame internal immutable game;
    IGovernance internal immutable governance;
    IPotatoToken internal immutable potato;
    IRecovery internal immutable recovery;
    ISettlement internal immutable settlement;

    address[4] internal actors;

    uint256 public nativeIn;
    uint256 public nativeOut;
    uint256 public forcedNative;
    uint256 public selfBurned;
    mapping(uint256 => uint256) public recoveryPaid;
    mapping(uint256 => uint256) public recoveryClaimedCommitments;
    bool public transferBypass;
    bool public authorityBypass;
    bool public remainingIncreased;
    bool public recoveryWithdrawalMismatch;
    uint256 internal observedRound;
    uint256 internal observedRemaining;

    constructor(address diamond_, address guardian_) {
        diamond = diamond_;
        guardian = guardian_;
        claims = IClaims(diamond_);
        game = IGame(diamond_);
        governance = IGovernance(diamond_);
        potato = IPotatoToken(diamond_);
        recovery = IRecovery(diamond_);
        settlement = ISettlement(diamond_);
        actors[0] = makeAddr("invariant-alice");
        actors[1] = makeAddr("invariant-bob");
        actors[2] = makeAddr("invariant-carol");
        actors[3] = makeAddr("invariant-dave");
    }

    function buy(uint256 actorSeed) external {
        uint256 roundId = game.currentRoundId();
        uint256 price;
        if (roundId == 0) {
            price = 0.01 ether;
        } else {
            Round memory round = game.getRound(roundId);
            if (round.currentHolder != address(0) && vm.getBlockTimestamp() >= round.deadline) return;
            price = round.nextPrice;
        }
        address actor = actors[actorSeed % actors.length];
        vm.deal(actor, actor.balance + price);
        vm.prank(actor);
        try game.buyPotato{value: price}() {
            nativeIn += price;
        } catch {}
        _observeRemaining();
    }

    function advance(uint256 rawSeconds) external {
        vm.warp(vm.getBlockTimestamp() + bound(rawSeconds, 0, 45 days));
        _observeRemaining();
    }

    function materialize() external {
        try game.materializeMaturedEmission() {} catch {}
        _observeRemaining();
    }

    function commit(uint256 actorSeed, uint256 rawAmount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = potato.balanceOf(actor);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(actor);
        try recovery.commitRecovery(amount) {} catch {}
        _observeRemaining();
    }

    function settle() external {
        try settlement.settleRound() {} catch {}
        _observeRemaining();
    }

    function withdrawStalledRecovery(uint256 actorSeed) external {
        uint256 currentRoundId = game.currentRoundId();
        if (currentRoundId == 0) return;
        uint256 targetRoundId = currentRoundId + 1;
        address actor = actors[actorSeed % actors.length];
        uint256 commitmentBefore = recovery.recoveryCommitment(targetRoundId, actor);
        if (commitmentBefore == 0) return;
        uint256 totalBefore = recovery.totalRecoveryCommitment(targetRoundId);
        uint256 balanceBefore = potato.balanceOf(actor);

        vm.prank(actor);
        try recovery.withdrawStalledRecovery(targetRoundId) returns (uint256 amount) {
            if (
                commitmentBefore > totalBefore || amount != commitmentBefore
                    || recovery.recoveryCommitment(targetRoundId, actor) != 0
                    || recovery.totalRecoveryCommitment(targetRoundId) != totalBefore - commitmentBefore
                    || potato.balanceOf(actor) != balanceBefore + commitmentBefore
            ) recoveryWithdrawalMismatch = true;
        } catch {}
        _observeRemaining();
    }

    function burn(uint256 actorSeed, uint256 rawAmount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = potato.balanceOf(actor);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(actor);
        try potato.burn(amount) {
            selfBurned += amount;
        } catch {}
        _observeRemaining();
    }

    function claimWinner(uint256 rawRound) external {
        uint256 current = game.currentRoundId();
        if (current <= 1) return;
        uint256 roundId = bound(rawRound, 1, current - 1);
        Round memory round = game.getRound(roundId);
        if (!round.settled || round.currentHolder == address(0)) return;
        vm.prank(round.currentHolder);
        try claims.claimWinner(roundId, round.currentHolder) returns (uint256 amount) {
            nativeOut += amount;
        } catch {}
    }

    function claimRecovery(uint256 actorSeed, uint256 rawRound) external {
        uint256 current = game.currentRoundId();
        if (current <= 1) return;
        uint256 roundId = bound(rawRound, 1, current - 1);
        address actor = actors[actorSeed % actors.length];
        uint256 commitment = recovery.recoveryCommitment(roundId, actor);
        vm.prank(actor);
        try claims.claimRecovery(roundId, actor) returns (uint256 amount) {
            nativeOut += amount;
            recoveryPaid[roundId] += amount;
            recoveryClaimedCommitments[roundId] += commitment;
        } catch {}
    }

    function claimTreasury() external {
        try claims.claimTreasury() returns (uint256 amount) {
            nativeOut += amount;
        } catch {}
    }

    function forceNative(uint96 rawAmount) external {
        uint256 amount = bound(uint256(rawAmount), 0, 10 ether);
        vm.deal(address(this), address(this).balance + amount);
        new ForceNativeIntoDiamond{value: amount}(payable(diamond));
        forcedNative += amount;
    }

    function setPause(uint256 rawFlags) external {
        vm.prank(guardian);
        try governance.setPauseState((rawFlags & 1) != 0, (rawFlags & 2) != 0) {} catch {}
    }

    function attemptRestrictedTransfer(uint256 actorSeed, uint256 rawAmount) external {
        address from = actors[actorSeed % actors.length];
        address to = actors[(actorSeed + 1) % actors.length];
        uint256 balance = potato.balanceOf(from);
        if (balance == 0) return;
        uint256 amount = bound(rawAmount, 1, balance);
        vm.prank(from);
        try potato.transfer(to, amount) returns (bool moved) {
            if (moved) transferBypass = true;
        } catch {}
    }

    function attemptUnauthorizedConfiguration(uint256 actorSeed, uint128 rawPrice, uint16 rawBps) external {
        address actor = actors[actorSeed % actors.length];
        uint256 price = bound(uint256(rawPrice), 1, 1_000 ether);
        uint16 bps = uint16(bound(uint256(rawBps), 1, 10_000));
        ProtocolConfig memory config = governance.protocolConfig();
        config.startingPrice = price;
        config.priceIncreaseBps = bps;
        vm.prank(actor);
        try governance.setProtocolConfig(config) {
            authorityBypass = true;
        } catch {}
    }

    function _observeRemaining() internal {
        uint256 roundId = game.currentRoundId();
        if (roundId == 0) return;
        uint256 remaining = game.getRound(roundId).remainingEmission;
        if (observedRound == roundId && remaining > observedRemaining) remainingIncreased = true;
        observedRound = roundId;
        observedRemaining = remaining;
    }
}

contract ProtocolInvariantTest is DiamondTestSetup {
    ProtocolHandler internal handler;

    function setUp() public {
        _deployCore();
        handler = new ProtocolHandler(address(diamond), guardian);
        targetContract(address(handler));
    }

    function invariant_NativeAssetAccountingIsExactlyConserved() public view {
        assertEq(address(diamond).balance, handler.nativeIn() + handler.forcedNative() - handler.nativeOut());
    }

    function invariant_PotatoSupplyEqualsEmissionMinusActualBurns() public view {
        IGame game = IGame(address(diamond));
        uint256 current = game.currentRoundId();
        uint256 emitted;
        uint256 recoveryBurned;
        for (uint256 roundId = 1; roundId <= current; ++roundId) {
            Round memory round = game.getRound(roundId);
            emitted += round.emittedPotato;
            if (round.settled && round.totalCommitted != 0) {
                uint256 treasuryPotato = round.totalCommitted * 1_000 / 10_000;
                recoveryBurned += round.totalCommitted - treasuryPotato;
            }
        }
        assertEq(
            IPotatoToken(address(diamond)).totalSupply(),
            GENESIS_MARKET_SUPPLY + emitted - recoveryBurned - handler.selfBurned()
        );
    }

    function invariant_CurrentRoundEmissionBudgetIsConserved() public view {
        IGame game = IGame(address(diamond));
        uint256 current = game.currentRoundId();
        if (current == 0) return;
        Round memory round = game.getRound(current);
        assertEq(round.emittedPotato + round.remainingEmission, 100_000 ether);
    }

    function invariant_CurrentRoundDeadlineMatchesDiminishingSchedule() public view {
        IGame game = IGame(address(diamond));
        uint256 current = game.currentRoundId();
        if (current == 0) return;
        Round memory round = game.getRound(current);
        if (round.currentHolder == address(0)) return;

        uint256 duration = round.deadline - round.holderSince;
        uint256 expected = LibMath.diminishingTimeout(
            round.config.roundTimeout,
            round.config.roundTimeoutDecay,
            round.config.minimumRoundTimeout,
            round.purchaseIndex - 1
        );
        assertEq(duration, expected);
        assertGe(duration, round.config.minimumRoundTimeout);
        assertLe(duration, round.config.roundTimeout);
    }

    function invariant_BuybackReserveRemainsBackedAndPurchaseBounded() public view {
        uint256 reserve = IBuyback(address(diamond)).buybackReserveEth();
        assertLe(reserve, address(diamond).balance);
        assertLe(reserve, handler.nativeIn());
    }

    function invariant_RecoveryNeverOverpaysAnyRound() public view {
        IGame game = IGame(address(diamond));
        uint256 current = game.currentRoundId();
        for (uint256 roundId = 1; roundId < current; ++roundId) {
            Round memory round = game.getRound(roundId);
            uint256 paid = handler.recoveryPaid(roundId);
            uint256 claimedCommitments = handler.recoveryClaimedCommitments(roundId);
            assertLe(paid, round.recoveryPool);
            assertLe(claimedCommitments, round.totalCommitted);
            if (round.settled && round.totalCommitted != 0 && claimedCommitments == round.totalCommitted) {
                assertEq(paid, round.recoveryPool);
            }
        }
    }

    function invariant_RestrictionsAndAuthorityNeverBypass() public view {
        assertFalse(handler.transferBypass());
        assertFalse(handler.authorityBypass());
        assertFalse(handler.remainingIncreased());
        assertFalse(handler.recoveryWithdrawalMismatch());
    }
}
