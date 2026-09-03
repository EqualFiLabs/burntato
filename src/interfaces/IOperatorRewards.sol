// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IStaticsOperators {
    function ownerOf(uint256 operatorId) external view returns (address);
    function activationRegistry() external view returns (address);
    function launchFinalized() external view returns (bool);
}

interface IGenesisActivationRegistryView {
    function genesisCollection() external view returns (address);
    function multiplierBps(uint256 operatorId) external view returns (uint16);
}

interface IOperatorRewards {
    enum SyncResult {
        Unchanged,
        WeightIncreased,
        Invalidated
    }

    struct Registration {
        address owner;
        uint16 weight;
        uint256 rewardIndex;
        uint256 claimable;
        uint256 rewardRemainder;
    }

    event RevenueQueued(address indexed sender, uint256 amount);
    event ForcedRevenueRecognized(uint256 amount);
    event RevenueAccrued(uint256 amount, uint256 totalWeight, uint256 rewardIndex);
    event OperatorRegistered(uint256 indexed operatorId, address indexed owner, uint16 weight);
    event OperatorWeightUpdated(uint256 indexed operatorId, uint16 previousWeight, uint16 newWeight);
    event OperatorInvalidated(
        uint256 indexed operatorId,
        address indexed storedOwner,
        address indexed currentOwner,
        uint16 storedWeight,
        uint16 currentWeight,
        uint256 forfeited,
        uint256 forfeitedRemainder
    );
    event OperatorRewardClaimed(
        uint256 indexed operatorId, address indexed owner, address indexed receiver, uint256 amount
    );
    event TreasuryRewardClaimed(address indexed receiver, uint256 amount);

    function burntato() external view returns (address);
    function register(uint256 operatorId) external;
    function sync(uint256 operatorId) external returns (SyncResult result);
    function claim(uint256 operatorId, address receiver) external returns (uint256 amount);
    function accrue() external returns (uint256 amount);
    function claimTreasury() external returns (uint256 amount);
    function registrationOf(uint256 operatorId) external view returns (Registration memory registration);
    function previewRewards(uint256 operatorId)
        external
        view
        returns (
            address currentOwner,
            uint16 currentWeight,
            bool transferDetected,
            uint256 claimable,
            uint256 forfeitable,
            uint256 rewardRemainder
        );
}
