// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

struct GenesisConfig {
    address deployer;
    address proposer;
    address guardian;
    address treasuryRecipient;
    uint256 timelockDelay;
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
    int24 initialTick;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint256 nativeSeed;
    uint256 potatoSeed;
}

struct BurntatoDeployment {
    address diamond;
    address diamondCutFacet;
    address diamondLoupeFacet;
    address governanceFacet;
    address marketFacet;
    address potatoTokenFacet;
    address gameFacet;
    address recoveryFacet;
    address settlementFacet;
    address claimsFacet;
    address foundationInit;
    address timelock;
    address poolManager;
    address permit2;
    address weth9;
    address positionDescriptor;
    address positionManager;
    address hookDeployer;
    address hook;
}
