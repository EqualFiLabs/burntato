// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

enum FacetCutAction {
    Add,
    Replace,
    Remove
}

struct FacetCut {
    address facetAddress;
    FacetCutAction action;
    bytes4[] functionSelectors;
}

struct Facet {
    address facetAddress;
    bytes4[] functionSelectors;
}

struct ProtocolConfig {
    uint256 startingPrice;
    uint16 priceIncreaseBps;
    uint256 roundTimeout;
    uint256 roundEmissionBudget;
    uint16 emissionStepBps;
    uint256 emissionVestingDuration;
    uint16 winnerBps;
    uint16 recoveryBps;
    uint16 treasuryBps;
    uint16 recoveryBurnBps;
    uint16 recoveryTreasuryBps;
    uint16 buybackBps;
    uint16 operatorPurchaseBps;
    uint256 roundTimeoutDecay;
    uint256 minimumRoundTimeout;
}

struct RoundConfig {
    uint256 startingPrice;
    uint16 priceIncreaseBps;
    uint256 roundTimeout;
    uint256 roundEmissionBudget;
    uint16 emissionStepBps;
    uint256 emissionVestingDuration;
    uint16 winnerBps;
    uint16 recoveryBps;
    uint16 treasuryBps;
    uint16 recoveryBurnBps;
    uint16 recoveryTreasuryBps;
    uint16 buybackBps;
    uint16 operatorPurchaseBps;
    uint256 roundTimeoutDecay;
    uint256 minimumRoundTimeout;
}

struct BuybackConfig {
    uint256 maxSpend;
    uint16 callerRewardBps;
    uint256 delayBlocks;
}

struct RewardSchedule {
    uint256 scheduleId;
    uint256 amount;
    uint256 firstRoundId;
    uint256 roundCount;
    uint256 perRound;
    uint256 firstRoundRemainder;
    uint256 canceledFromRound;
    uint256 canceledAmount;
}

struct Round {
    uint256 roundId;
    RoundConfig config;
    address currentHolder;
    uint256 holderSince;
    uint256 deadline;
    uint64 purchaseIndex;
    uint256 nextPrice;
    uint256 holderMaxReward;
    uint256 holderEarned;
    uint256 remainingEmission;
    uint256 emittedPotato;
    uint256 treasuryEmissionBudget;
    uint256 holderTreasuryMaxReward;
    uint256 holderTreasuryEarned;
    uint256 remainingTreasuryEmission;
    uint256 treasuryEmittedPotato;
    uint256 treasuryReleasedPotato;
    uint256 winnerPool;
    uint256 recoveryPool;
    uint256 recoveryCarryIn;
    uint256 totalCommitted;
    bool holderEmissionFinalized;
    bool activated;
    bool settled;
}
