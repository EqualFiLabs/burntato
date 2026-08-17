// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ProtocolConfig, Round} from "../shared/Types.sol";

library LibProtocolStorage {
    bytes32 internal constant GAME_SLOT = keccak256("burntato.storage.game.v1");
    bytes32 internal constant TOKEN_SLOT = keccak256("burntato.storage.token.v1");
    bytes32 internal constant RECOVERY_SLOT = keccak256("burntato.storage.recovery.v1");
    bytes32 internal constant TREASURY_SLOT = keccak256("burntato.storage.treasury.v1");
    bytes32 internal constant GOVERNANCE_SLOT = keccak256("burntato.storage.governance.v1");
    bytes32 internal constant MARKET_SLOT = keccak256("burntato.storage.market.v1");
    bytes32 internal constant REENTRANCY_SLOT = keccak256("burntato.storage.reentrancy.v1");

    bytes32 internal constant POOL_MANAGER_ALLOWANCE_SLOT = keccak256("burntato.transient.pool-manager-allowance.v1");
    bytes32 internal constant PROTOCOL_MOVEMENT_SLOT = keccak256("burntato.transient.protocol-movement.v1");
    bytes32 internal constant MARKET_LAUNCH_SLOT = keccak256("burntato.transient.market-launch.v1");

    struct GameStorage {
        bool initialized;
        ProtocolConfig config;
        uint256 currentRoundId;
        mapping(uint256 => Round) rounds;
        mapping(uint256 => bool) winnerClaimed;
    }

    struct TokenStorage {
        uint256 totalSupply;
        mapping(address => uint256) balanceOf;
        mapping(address => mapping(address => uint256)) allowance;
        address canonicalHook;
        address poolManager;
    }

    struct RecoveryStorage {
        mapping(uint256 => mapping(address => uint256)) commitments;
        mapping(uint256 => uint256) totalCommitments;
        mapping(uint256 => mapping(address => bool)) claimed;
        mapping(uint256 => uint256) recoveryPaid;
    }

    struct TreasuryStorage {
        address recipient;
        uint256 purchaseEth;
        uint256 hookEth;
        uint256 potatoInventory;
        uint256 reservedEth;
        uint256 reservedPotato;
    }

    struct GovernanceStorage {
        address guardian;
        bool purchasesPaused;
        bool commitmentsPaused;
        bool finalized;
        mapping(bytes32 => bool) frozenParameters;
    }

    struct MarketStorage {
        address hook;
        address poolManager;
        bytes32 poolId;
        uint256 nativeSeed;
        uint256 potatoSeed;
        bool launched;
    }

    struct ReentrancyStorage {
        uint256 status;
    }

    function game() internal pure returns (GameStorage storage s) {
        bytes32 slot = GAME_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function token() internal pure returns (TokenStorage storage s) {
        bytes32 slot = TOKEN_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function recovery() internal pure returns (RecoveryStorage storage s) {
        bytes32 slot = RECOVERY_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function treasury() internal pure returns (TreasuryStorage storage s) {
        bytes32 slot = TREASURY_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function governance() internal pure returns (GovernanceStorage storage s) {
        bytes32 slot = GOVERNANCE_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function market() internal pure returns (MarketStorage storage s) {
        bytes32 slot = MARKET_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }

    function reentrancy() internal pure returns (ReentrancyStorage storage s) {
        bytes32 slot = REENTRANCY_SLOT;
        assembly ("memory-safe") {
            s.slot := slot
        }
    }
}
