// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BuybackConfig, ProtocolConfig} from "../src/shared/Types.sol";

struct GenesisConfig {
    address deployer;
    address proposer;
    address guardian;
    address treasuryRecipient;
    address rewardAllocator;
    uint256 timelockDelay;
    ProtocolConfig protocol;
    BuybackConfig buyback;
    uint16 hookFeeBps;
    int24 initialTick;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint256 potatoSeed;
}

struct BurntatoDeployment {
    address diamond;
    address diamondCutFacet;
    address diamondLoupeFacet;
    address governanceFacet;
    address marketFacet;
    address buybackFacet;
    address potatoTokenFacet;
    address gameFacet;
    address recoveryFacet;
    address settlementFacet;
    address claimsFacet;
    address treasuryRewardsFacet;
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
