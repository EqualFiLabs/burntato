// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Constants} from "../shared/Constants.sol";
import {Errors} from "../shared/Errors.sol";
import {ProtocolConfig, RoundConfig} from "../shared/Types.sol";

library LibConfig {
    function validate(ProtocolConfig memory config) internal pure {
        if (
            config.startingPrice == 0 || config.roundTimeout == 0 || config.roundTimeout > type(uint64).max
                || config.emissionVestingDuration == 0 || config.priceIncreaseBps > Constants.BPS
                || config.emissionStepBps > Constants.BPS || config.winnerBps > Constants.BPS
                || config.recoveryBps > Constants.BPS || config.treasuryBps > Constants.BPS
                || config.buybackBps > Constants.BPS || config.recoveryBurnBps > Constants.BPS
                || config.recoveryTreasuryBps > Constants.BPS
                || uint256(config.winnerBps) + config.recoveryBps + config.treasuryBps + config.buybackBps
                    != Constants.BPS || uint256(config.recoveryBurnBps) + config.recoveryTreasuryBps != Constants.BPS
        ) revert Errors.InvalidProtocolConfig();
    }

    function snapshot(ProtocolConfig storage config, RoundConfig storage target) internal {
        target.startingPrice = config.startingPrice;
        target.priceIncreaseBps = config.priceIncreaseBps;
        target.roundTimeout = config.roundTimeout;
        target.roundEmissionBudget = config.roundEmissionBudget;
        target.emissionStepBps = config.emissionStepBps;
        target.emissionVestingDuration = config.emissionVestingDuration;
        target.winnerBps = config.winnerBps;
        target.recoveryBps = config.recoveryBps;
        target.treasuryBps = config.treasuryBps;
        target.buybackBps = config.buybackBps;
        target.recoveryBurnBps = config.recoveryBurnBps;
        target.recoveryTreasuryBps = config.recoveryTreasuryBps;
    }
}
