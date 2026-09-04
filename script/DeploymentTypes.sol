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
    uint16 operatorRewardShareBps;
    int24 initialTick;
    int24 tickSpacing;
    int24 tickLower;
    int24 tickUpper;
    uint256 potatoSeed;
}

struct StaticsOperatorDependencies {
    uint256 chainId;
    uint256 finalizedBlock;
    bytes32 finalizedBlockHash;
    address operatorsNft;
    bytes32 operatorsNftCodeHash;
    address activationRegistry;
    bytes32 activationRegistryCodeHash;
}

struct CanonicalV4Dependencies {
    uint256 chainId;
    uint256 forkBlock;
    bytes32 forkBlockHash;
    address poolManager;
    bytes32 poolManagerCodeHash;
    address positionDescriptor;
    bytes32 positionDescriptorCodeHash;
    address positionManager;
    bytes32 positionManagerCodeHash;
    address quoter;
    bytes32 quoterCodeHash;
    address stateView;
    bytes32 stateViewCodeHash;
    address reservesLens;
    bytes32 reservesLensCodeHash;
    address universalRouter;
    bytes32 universalRouterCodeHash;
    address permit2;
    bytes32 permit2CodeHash;
    address weth;
    bytes32 wethCodeHash;
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
    address operatorRewardsRouter;
    address quoter;
    address stateView;
    address reservesLens;
    address universalRouter;
}
