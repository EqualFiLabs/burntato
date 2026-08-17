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
    uint256 winnerPool;
    uint256 recoveryPool;
    uint256 recoveryCarryIn;
    uint256 totalCommitted;
    bool holderEmissionFinalized;
    bool activated;
    bool settled;
}
