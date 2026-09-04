// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

import {IClaims} from "../interfaces/IClaims.sol";
import {IGenesisActivationRegistryView, IOperatorRewards, IStaticsOperators} from "../interfaces/IOperatorRewards.sol";

/// @notice Pull-based native rewards for owners of registered Statics Operator NFTs.
/// @dev Ownership and activation are read lazily from the finalized external Statics contracts.
contract BurntatoOperatorRewardsRouter is IOperatorRewards, ReentrancyGuard {
    uint256 public constant RAY = 1e27;

    address public immutable burntato;
    IStaticsOperators public immutable operators;
    IGenesisActivationRegistryView public immutable activationRegistry;

    uint256 public totalRegisteredWeight;
    uint256 public rewardIndex;
    uint256 public globalRewardRemainder;
    uint256 public pendingRevenue;
    uint256 public treasuryClaimable;
    uint256 public treasuryRemainder;
    uint256 public accountedBalance;
    uint256 public totalReceived;
    uint256 public totalOperatorClaimed;
    uint256 public totalTreasuryClaimed;

    mapping(uint256 operatorId => Registration registration) private _registrations;

    error InvalidDependency(address dependency);
    error InvalidDependencyBinding();
    error StaticsLaunchNotFinalized();
    error InvalidOperatorOwner(uint256 operatorId, address caller, address owner);
    error InvalidOperatorWeight(uint256 operatorId);
    error OperatorAlreadyRegistered(uint256 operatorId);
    error OperatorNotRegistered(uint256 operatorId);
    error InvalidReceiver(address receiver);
    error NativeTransferFailed(address receiver, uint256 amount);

    constructor(address burntato_, address operators_, address activationRegistry_) {
        if (burntato_.code.length == 0) revert InvalidDependency(burntato_);
        if (operators_.code.length == 0) revert InvalidDependency(operators_);
        if (activationRegistry_.code.length == 0) revert InvalidDependency(activationRegistry_);

        IStaticsOperators operatorsContract = IStaticsOperators(operators_);
        IGenesisActivationRegistryView registryContract = IGenesisActivationRegistryView(activationRegistry_);
        if (
            operatorsContract.activationRegistry() != activationRegistry_
                || registryContract.genesisCollection() != operators_
        ) revert InvalidDependencyBinding();
        if (!operatorsContract.launchFinalized()) revert StaticsLaunchNotFinalized();

        burntato = burntato_;
        operators = operatorsContract;
        activationRegistry = registryContract;
    }

    receive() external payable {
        pendingRevenue += msg.value;
        accountedBalance += msg.value;
        totalReceived += msg.value;
        emit RevenueQueued(msg.sender, msg.value);
    }

    function register(uint256 operatorId) external {
        _accrue();
        address currentOwner = operators.ownerOf(operatorId);
        if (currentOwner != msg.sender) revert InvalidOperatorOwner(operatorId, msg.sender, currentOwner);

        Registration storage registration = _registrations[operatorId];
        if (registration.owner != address(0)) {
            uint16 currentWeight = activationRegistry.multiplierBps(operatorId);
            if (registration.owner == currentOwner && currentWeight >= registration.weight) {
                revert OperatorAlreadyRegistered(operatorId);
            }
            _invalidate(operatorId, registration, currentOwner, currentWeight);
        }

        uint16 weight = activationRegistry.multiplierBps(operatorId);
        if (weight == 0) revert InvalidOperatorWeight(operatorId);
        _flushGlobalRemainder();
        totalRegisteredWeight += weight;
        _registrations[operatorId] = Registration({
            owner: currentOwner, weight: weight, rewardIndex: rewardIndex, claimable: 0, rewardRemainder: 0
        });
        emit OperatorRegistered(operatorId, currentOwner, weight);
    }

    function sync(uint256 operatorId) external returns (SyncResult result) {
        _accrue();
        Registration storage registration = _registrations[operatorId];
        if (registration.owner == address(0)) revert OperatorNotRegistered(operatorId);
        (result,,) = _sync(operatorId, registration);
    }

    function claim(uint256 operatorId, address receiver) external nonReentrant returns (uint256 amount) {
        if (receiver == address(0) || receiver == address(this)) revert InvalidReceiver(receiver);
        _accrue();
        Registration storage registration = _registrations[operatorId];
        if (registration.owner == address(0)) revert OperatorNotRegistered(operatorId);

        address currentOwner = operators.ownerOf(operatorId);
        if (currentOwner != msg.sender) revert InvalidOperatorOwner(operatorId, msg.sender, currentOwner);
        (SyncResult result,,) = _syncKnownOwner(operatorId, registration, currentOwner);
        if (result == SyncResult.Invalidated) return 0;

        amount = registration.claimable;
        registration.claimable = 0;
        if (amount != 0) {
            accountedBalance -= amount;
            totalOperatorClaimed += amount;
            (bool success,) = receiver.call{value: amount}("");
            if (!success) revert NativeTransferFailed(receiver, amount);
        }
        emit OperatorRewardClaimed(operatorId, currentOwner, receiver, amount);
    }

    function accrue() external returns (uint256 amount) {
        return _accrue();
    }

    function claimTreasury() external nonReentrant returns (uint256 amount) {
        _accrue();
        address receiver = IClaims(burntato).treasuryRecipient();
        if (receiver == address(0) || receiver == address(this)) revert InvalidReceiver(receiver);
        amount = treasuryClaimable;
        treasuryClaimable = 0;
        if (amount != 0) {
            accountedBalance -= amount;
            totalTreasuryClaimed += amount;
            (bool success,) = receiver.call{value: amount}("");
            if (!success) revert NativeTransferFailed(receiver, amount);
        }
        emit TreasuryRewardClaimed(receiver, amount);
    }

    function registrationOf(uint256 operatorId) external view returns (Registration memory registration) {
        return _registrations[operatorId];
    }

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
        )
    {
        Registration memory registration = _registrations[operatorId];
        if (registration.owner == address(0)) return (address(0), 0, false, 0, 0, 0);

        currentOwner = operators.ownerOf(operatorId);
        currentWeight = activationRegistry.multiplierBps(operatorId);
        transferDetected = currentOwner != registration.owner || currentWeight < registration.weight;

        uint256 previewIndex = _previewRewardIndex();
        (claimable, rewardRemainder) = _previewSettlement(registration, previewIndex);
        if (transferDetected) {
            forfeitable = claimable;
            claimable = 0;
        }
    }

    function _sync(uint256 operatorId, Registration storage registration)
        private
        returns (SyncResult result, address currentOwner, uint16 currentWeight)
    {
        currentOwner = operators.ownerOf(operatorId);
        return _syncKnownOwner(operatorId, registration, currentOwner);
    }

    function _syncKnownOwner(uint256 operatorId, Registration storage registration, address currentOwner)
        private
        returns (SyncResult result, address, uint16 currentWeight)
    {
        currentWeight = activationRegistry.multiplierBps(operatorId);
        if (currentOwner != registration.owner || currentWeight < registration.weight) {
            _invalidate(operatorId, registration, currentOwner, currentWeight);
            return (SyncResult.Invalidated, currentOwner, currentWeight);
        }

        _settle(registration);
        if (currentWeight == registration.weight) return (SyncResult.Unchanged, currentOwner, currentWeight);
        if (currentWeight == 0) revert InvalidOperatorWeight(operatorId);

        uint16 previousWeight = registration.weight;
        _flushGlobalRemainder();
        totalRegisteredWeight = totalRegisteredWeight - previousWeight + currentWeight;
        registration.weight = currentWeight;
        registration.rewardIndex = rewardIndex;
        emit OperatorWeightUpdated(operatorId, previousWeight, currentWeight);
        return (SyncResult.WeightIncreased, currentOwner, currentWeight);
    }

    function _invalidate(
        uint256 operatorId,
        Registration storage registration,
        address currentOwner,
        uint16 currentWeight
    ) private {
        _settle(registration);
        address storedOwner = registration.owner;
        uint16 storedWeight = registration.weight;
        uint256 forfeited = registration.claimable;
        uint256 forfeitedRemainder = registration.rewardRemainder;

        _flushGlobalRemainder();
        totalRegisteredWeight -= storedWeight;
        delete _registrations[operatorId];

        if (totalRegisteredWeight == 0) {
            _creditTreasuryWhole(forfeited);
            _creditTreasuryRemainder(forfeitedRemainder);
        } else {
            _distributeWhole(forfeited);
            _distributeRemainder(forfeitedRemainder);
        }

        emit OperatorInvalidated(
            operatorId, storedOwner, currentOwner, storedWeight, currentWeight, forfeited, forfeitedRemainder
        );
    }

    function _accrue() private returns (uint256 amount) {
        uint256 actualBalance = address(this).balance;
        if (actualBalance > accountedBalance) {
            uint256 forcedRevenue = actualBalance - accountedBalance;
            accountedBalance = actualBalance;
            pendingRevenue += forcedRevenue;
            totalReceived += forcedRevenue;
            emit ForcedRevenueRecognized(forcedRevenue);
        }

        amount = pendingRevenue;
        if (amount == 0) return 0;
        pendingRevenue = 0;
        uint256 weight = totalRegisteredWeight;
        if (weight == 0) _creditTreasuryWhole(amount);
        else _distributeWhole(amount);
        emit RevenueAccrued(amount, weight, rewardIndex);
    }

    function _settle(Registration storage registration) private {
        uint256 indexDelta = rewardIndex - registration.rewardIndex;
        if (indexDelta == 0) return;

        uint256 whole = FixedPointMathLib.fullMulDiv(registration.weight, indexDelta, RAY);
        uint256 remainder = mulmod(registration.weight, indexDelta, RAY);
        uint256 previousRemainder = registration.rewardRemainder;
        if (remainder >= RAY - previousRemainder) {
            ++whole;
            remainder -= RAY - previousRemainder;
        } else {
            remainder += previousRemainder;
        }
        registration.claimable += whole;
        registration.rewardRemainder = remainder;
        registration.rewardIndex = rewardIndex;
    }

    function _distributeWhole(uint256 amount) private {
        if (amount == 0) return;
        uint256 weight = totalRegisteredWeight;
        uint256 indexDelta = FixedPointMathLib.fullMulDiv(amount, RAY, weight);
        uint256 remainder = mulmod(amount, RAY, weight);
        uint256 previousRemainder = globalRewardRemainder;
        if (remainder >= weight - previousRemainder) {
            ++indexDelta;
            remainder -= weight - previousRemainder;
        } else {
            remainder += previousRemainder;
        }
        rewardIndex += indexDelta;
        globalRewardRemainder = remainder;
    }

    function _distributeRemainder(uint256 scaledAmount) private {
        if (scaledAmount == 0) return;
        uint256 weight = totalRegisteredWeight;
        uint256 indexDelta = scaledAmount / weight;
        uint256 remainder = scaledAmount % weight;
        uint256 previousRemainder = globalRewardRemainder;
        if (remainder >= weight - previousRemainder) {
            ++indexDelta;
            remainder -= weight - previousRemainder;
        } else {
            remainder += previousRemainder;
        }
        rewardIndex += indexDelta;
        globalRewardRemainder = remainder;
    }

    function _flushGlobalRemainder() private {
        uint256 remainder = globalRewardRemainder;
        if (remainder == 0) return;
        globalRewardRemainder = 0;
        _creditTreasuryRemainder(remainder);
    }

    function _creditTreasuryWhole(uint256 amount) private {
        treasuryClaimable += amount;
    }

    function _creditTreasuryRemainder(uint256 scaledAmount) private {
        if (scaledAmount == 0) return;
        treasuryClaimable += scaledAmount / RAY;
        uint256 remainder = scaledAmount % RAY;
        uint256 previousRemainder = treasuryRemainder;
        if (remainder >= RAY - previousRemainder) {
            ++treasuryClaimable;
            remainder -= RAY - previousRemainder;
        } else {
            remainder += previousRemainder;
        }
        treasuryRemainder = remainder;
    }

    function _previewRewardIndex() private view returns (uint256 previewIndex) {
        previewIndex = rewardIndex;
        uint256 weight = totalRegisteredWeight;
        if (weight == 0) return previewIndex;
        uint256 amount = pendingRevenue;
        uint256 actualBalance = address(this).balance;
        if (actualBalance > accountedBalance) amount += actualBalance - accountedBalance;
        if (amount == 0) return previewIndex;

        uint256 indexDelta = FixedPointMathLib.fullMulDiv(amount, RAY, weight);
        uint256 remainder = mulmod(amount, RAY, weight);
        if (remainder >= weight - globalRewardRemainder) ++indexDelta;
        return previewIndex + indexDelta;
    }

    function _previewSettlement(Registration memory registration, uint256 previewIndex)
        private
        pure
        returns (uint256 claimable, uint256 remainder)
    {
        uint256 indexDelta = previewIndex - registration.rewardIndex;
        uint256 whole = FixedPointMathLib.fullMulDiv(registration.weight, indexDelta, RAY);
        remainder = mulmod(registration.weight, indexDelta, RAY);
        if (remainder >= RAY - registration.rewardRemainder) {
            ++whole;
            remainder -= RAY - registration.rewardRemainder;
        } else {
            remainder += registration.rewardRemainder;
        }
        claimable = registration.claimable + whole;
    }
}
