// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibConfig} from "../libraries/LibConfig.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Errors} from "../shared/Errors.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
import {ProtocolConfig} from "../shared/Types.sol";
import {IOperatorRewards} from "../interfaces/IOperatorRewards.sol";
import {IGame} from "../interfaces/IGame.sol";

contract FoundationInit {
    event FoundationConfigured();

    function initialize(
        ProtocolConfig calldata config,
        address treasury,
        address operatorRewardsRouter,
        address statics,
        uint256 initialWinnerReserve
    ) external {
        LibProtocolStorage.InitializationStorage storage initialization = LibProtocolStorage.initialization();
        if (initialization.foundationInitialized) revert Errors.AlreadyInitialized();
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        LibRecipients.enforceExternal(treasury);
        if (treasury == operatorRewardsRouter) revert Errors.InvalidAddress();
        LibDiamond.enforceHasCode(statics);
        if (statics == treasury || statics == address(this) || IERC20Metadata(statics).decimals() != 18) {
            revert Errors.InvalidBacking();
        }
        if (initialWinnerReserve > address(this).balance) revert Errors.InsufficientBalance();
        LibConfig.validate(config);
        if (operatorRewardsRouter == address(0)) {
            if (config.operatorPurchaseBps != 0) revert Errors.InvalidProtocolConfig();
        } else {
            LibDiamond.enforceHasCode(operatorRewardsRouter);
            if (IOperatorRewards(operatorRewardsRouter).burntato() != address(this)) {
                revert Errors.InvalidProtocolConfig();
            }
        }
        initialization.foundationInitialized = true;
        gs.config = config;
        gs.winnerReserveEth = initialWinnerReserve;
        gs.winnerReserveByRound[1] = initialWinnerReserve;
        LibProtocolStorage.operatorRevenue().router = operatorRewardsRouter;

        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        ts.recipient = treasury;
        LibProtocolStorage.wrapper().underlying = statics;
        LibProtocolStorage.wrapper().publicWrapCap = 0;
        if (initialWinnerReserve != 0) {
            emit IGame.WinnerReserveFunded(msg.sender, 1, initialWinnerReserve, initialWinnerReserve);
        }
        emit FoundationConfigured();
    }
}
