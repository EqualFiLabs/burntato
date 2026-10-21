// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {GenesisConfig} from "../DeploymentTypes.sol";
import {LibMath} from "../../src/libraries/LibMath.sol";
import {BuybackConfig, ProtocolConfig} from "../../src/shared/Types.sol";

library BurntatoDeploymentConfig {
    error NarrowingOverflow();
    address internal constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant ANVIL_ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant ANVIL_GUARDIAN = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address internal constant ANVIL_TREASURY = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    uint256 internal constant INITIAL_WINNER_TARGET_BPS = 10_500;

    function localDefaults() internal pure returns (GenesisConfig memory config) {
        config = GenesisConfig({
            statics: address(0),
            deployer: ANVIL_DEPLOYER,
            finalAdmin: ANVIL_ADMIN,
            guardian: ANVIL_GUARDIAN,
            treasuryRecipient: ANVIL_TREASURY,
            rewardAllocator: ANVIL_TREASURY,
            protocol: ProtocolConfig({
                startingPrice: 0.003 ether,
                priceIncreaseBps: 1_000,
                roundTimeout: 1 hours,
                roundEmissionBudget: 20_000 ether,
                emissionStepBps: 500,
                emissionVestingDuration: 4 minutes,
                winnerBps: 2_500,
                nextRoundWinnerBps: 500,
                recoveryBps: 3_000,
                treasuryBps: 3_000,
                buybackBps: 1_000,
                operatorPurchaseBps: 0,
                roundTimeoutDecay: 5 minutes,
                minimumRoundTimeout: 5 minutes
            }),
            initialWinnerReserve: 0,
            buyback: BuybackConfig({maxSpend: 1 ether, callerRewardBps: 50, delayBlocks: 1}),
            publicWrapCap: 0
        });
        config.initialWinnerReserve = defaultInitialWinnerReserve(config.protocol);
    }

    function launchDefaults() internal pure returns (GenesisConfig memory config) {
        config = localDefaults();
        config.protocol.winnerBps = 2_500;
        config.protocol.nextRoundWinnerBps = 500;
        config.protocol.recoveryBps = 3_000;
        config.protocol.treasuryBps = 1_500;
        config.protocol.buybackBps = 1_000;
        config.protocol.operatorPurchaseBps = 1_500;
    }

    function defaultInitialWinnerReserve(ProtocolConfig memory protocol) internal pure returns (uint256) {
        return LibMath.mulBpsUp(protocol.startingPrice, INITIAL_WINNER_TARGET_BPS);
    }

    function checkedUint16(uint256 value) internal pure returns (uint16 narrowed) {
        if (value > type(uint16).max) revert NarrowingOverflow();
        narrowed = uint16(value);
    }
}
