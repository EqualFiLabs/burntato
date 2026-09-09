// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice Runtime hashes for reviewed Burntato source.
/// @dev Immutable-bearing hashes use the compiler artifact with every immutable reference zeroed.
///      Regenerate and validate these whenever the compiler settings or owned source changes.
library BurntatoSourceCodeHashes {
    bytes32 internal constant DIAMOND = 0x08078332fcfc2680de45d406fe082dcbe5c11e2f23fa0a6798726756ff1b2be6;
    bytes32 internal constant DIAMOND_CUT_FACET = 0xa84928664cd2e4743aff7733c3ab8f4661e9a6ab7545577ca11342272aa91ae5;
    bytes32 internal constant DIAMOND_LOUPE_FACET = 0x31f9d7259b05395dcadd67ec708606124e8667d3d9b275264c2f13875ef2ae93;
    bytes32 internal constant GOVERNANCE_FACET = 0xd5c77479945f788099e9b179be398438197b52230cbf85dba56aad3047060722;
    bytes32 internal constant MARKET_FACET = 0x977918a2ed1ebd28b8408f79c2f99f684759ec2b8e2c7e0f030433b876f92cfe;
    bytes32 internal constant BUYBACK_FACET = 0xf3601b1c356b523c9d132d6b4d885ed6fecde484ae54235d8519014df6b84623;
    bytes32 internal constant POTATO_TOKEN_FACET = 0x8dcc89b9e1c88d49ac79d84ea871d4a2e53272cb74c91aa84024a93108a61be1;
    bytes32 internal constant GAME_FACET = 0x5d6d9d633ab798a36e6f0fa43cb65ed1c3126721947a8a5ed34132c09433d208;
    bytes32 internal constant RECOVERY_FACET = 0x5a285f357d78146ff1123d9a791900aca373183a12f1849e537558840c2636f4;
    bytes32 internal constant SETTLEMENT_FACET = 0xa8e181ddb3fd547e7fa978bba2f548ed2e29d5aa0da6d41be4acb171cbbe407a;
    bytes32 internal constant CLAIMS_FACET = 0xa3c373a9fc421bbdf103115b29d95356556e4116bf070e331f36737a498cddb8;
    bytes32 internal constant TREASURY_REWARDS_FACET =
        0xd6f8bdeaf4d0944da1309fc06a331d9d84670fbcc2a35c04426cd76fe80c9e19;
    bytes32 internal constant FOUNDATION_INIT = 0x4f7fd9b54a83656b84f78f076361b67110454c6bc7b61ed37d818ce383493596;
    bytes32 internal constant HOOK_DEPLOYER_NORMALIZED =
        0xe74476fe70d26e9b1fa5f84df93db5a375193ab8f873da753b753dc3aa458070;
    bytes32 internal constant HOOK_NORMALIZED = 0x38337ea93b155e39f5bc044d5ae557da0aee7e0f4769ae2a90cbd9268d8566e8;
    bytes32 internal constant OPERATOR_ROUTER_NORMALIZED =
        0x03379d5b337d450006dd4817af7d1b18a712a58ed992d298c9b25dd482e06ca2;
}
