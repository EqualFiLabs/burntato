// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {BuybackConfig, ProtocolConfig} from "../src/shared/Types.sol";

struct GenesisConfig {
    address deployer;
    address finalAdmin;
    address guardian;
    address treasuryRecipient;
    address rewardAllocator;
    address statics;
    ProtocolConfig protocol;
    uint256 initialWinnerReserve;
    BuybackConfig buyback;
    uint256 publicWrapCap;
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

struct BurntatoDeployment {
    address diamond;
    address diamondCutFacet;
    address diamondLoupeFacet;
    address governanceFacet;
    address buybackFacet;
    address potatoTokenFacet;
    address gameFacet;
    address recoveryFacet;
    address settlementFacet;
    address claimsFacet;
    address treasuryRewardsFacet;
    address foundationInit;
    address admin;
    address statics;
    address poolManager;
    address weth9;
    address operatorRewardsRouter;
}

struct StaticsMarketDependencies {
    uint256 chainId;
    uint256 forkBlock;
    bytes32 forkBlockHash;
    address statics;
    bytes32 staticsCodeHash;
    address weth;
    bytes32 wethCodeHash;
    address poolManager;
    bytes32 poolManagerCodeHash;
    bytes32 hookCodeHash;
    bytes32 poolId;
    PoolKey key;
}
