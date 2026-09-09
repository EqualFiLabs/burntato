// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice Runtime hashes for reviewed Burntato source.
/// @dev Immutable-bearing hashes use the compiler artifact with every immutable reference zeroed.
///      Regenerate and validate these whenever the compiler settings or owned source changes.
library BurntatoSourceCodeHashes {
    bytes32 internal constant DIAMOND = 0x08078332fcfc2680de45d406fe082dcbe5c11e2f23fa0a6798726756ff1b2be6;
    bytes32 internal constant DIAMOND_CUT_FACET = 0xa84928664cd2e4743aff7733c3ab8f4661e9a6ab7545577ca11342272aa91ae5;
    bytes32 internal constant DIAMOND_LOUPE_FACET = 0x31f9d7259b05395dcadd67ec708606124e8667d3d9b275264c2f13875ef2ae93;
    bytes32 internal constant GOVERNANCE_FACET = 0xc9b97eff15f51d31d1636a333f2bc50121a5a50659aff26a7236c50125d60df9;
    bytes32 internal constant MARKET_FACET = 0x977918a2ed1ebd28b8408f79c2f99f684759ec2b8e2c7e0f030433b876f92cfe;
    bytes32 internal constant BUYBACK_FACET = 0xf3601b1c356b523c9d132d6b4d885ed6fecde484ae54235d8519014df6b84623;
    bytes32 internal constant POTATO_TOKEN_FACET = 0x6e46b3ba498d70b35a838846319b3766564ef29eb4e5b1d1552bcbaede1b6540;
    bytes32 internal constant GAME_FACET = 0x338f9d9c7d99cd33a263d1cb5d075f344343b855ba15511cea747d9f10048902;
    bytes32 internal constant RECOVERY_FACET = 0x3ed1f63875295c6ab323a2317f727a24d5328ae18305d71aa337e14fca8fca69;
    bytes32 internal constant SETTLEMENT_FACET = 0x9be63ecf6f09d93e48a089f2f38c048b0e1d397e46de64be4bfe799f1c378f6f;
    bytes32 internal constant CLAIMS_FACET = 0x2df29b11b27d7cf6bc773888b60e0e03c7f7bd251f5f5fd80d83278b79ee07eb;
    bytes32 internal constant TREASURY_REWARDS_FACET =
        0xd6f8bdeaf4d0944da1309fc06a331d9d84670fbcc2a35c04426cd76fe80c9e19;
    bytes32 internal constant FOUNDATION_INIT = 0x4f7fd9b54a83656b84f78f076361b67110454c6bc7b61ed37d818ce383493596;
    bytes32 internal constant HOOK_DEPLOYER_NORMALIZED =
        0xe74476fe70d26e9b1fa5f84df93db5a375193ab8f873da753b753dc3aa458070;
    bytes32 internal constant HOOK_NORMALIZED = 0x38337ea93b155e39f5bc044d5ae557da0aee7e0f4769ae2a90cbd9268d8566e8;
    bytes32 internal constant OPERATOR_ROUTER_NORMALIZED =
        0x03379d5b337d450006dd4817af7d1b18a712a58ed992d298c9b25dd482e06ca2;
}
