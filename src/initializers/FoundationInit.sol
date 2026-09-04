// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "solady/src/tokens/ERC20.sol";

import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibConfig} from "../libraries/LibConfig.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {Errors} from "../shared/Errors.sol";
import {LibRecipients} from "../libraries/LibRecipients.sol";
import {ProtocolConfig} from "../shared/Types.sol";
import {IOperatorRewards} from "../interfaces/IOperatorRewards.sol";

contract FoundationInit is ERC20 {
    event GenesisMarketSupplyMinted(uint256 amount);

    function name() public pure override returns (string memory) {
        return "Burntato Potato";
    }

    function symbol() public pure override returns (string memory) {
        return "POTATO";
    }

    function initialize(
        ProtocolConfig calldata config,
        address treasury,
        address operatorRewardsRouter,
        uint256 marketPotatoSeed
    ) external {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        if (gs.initialized) revert Errors.AlreadyInitialized();
        LibRecipients.enforceExternal(treasury);
        if (marketPotatoSeed == 0) revert Errors.ZeroAmount();
        LibConfig.validate(config);
        if (operatorRewardsRouter == address(0)) {
            if (config.operatorPurchaseBps != 0) revert Errors.InvalidProtocolConfig();
        } else {
            LibDiamond.enforceHasCode(operatorRewardsRouter);
            if (IOperatorRewards(operatorRewardsRouter).burntato() != address(this)) {
                revert Errors.InvalidProtocolConfig();
            }
        }
        gs.initialized = true;
        gs.config = config;
        LibProtocolStorage.operatorRevenue().router = operatorRewardsRouter;

        LibProtocolStorage.TreasuryStorage storage ts = LibProtocolStorage.treasury();
        ts.recipient = treasury;
        ts.potatoInventory = marketPotatoSeed;
        ts.reservedPotato = marketPotatoSeed;
        LibProtocolStorage.market().potatoSeed = marketPotatoSeed;
        _mint(address(this), marketPotatoSeed);
        emit GenesisMarketSupplyMinted(marketPotatoSeed);
    }
}
