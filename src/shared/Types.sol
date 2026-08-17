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
}

struct RoundConfig {
    uint256 startingPrice;
    uint16 priceIncreaseBps;
}

struct Round {
    uint256 roundId;
    RoundConfig config;
    address currentHolder;
    uint64 holderSince;
    uint64 deadline;
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
    bool settled;
}
