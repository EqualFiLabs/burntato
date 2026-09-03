// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";

contract BurntatoHookDeployer {
    error UnauthorizedDeployer(address caller);

    address public immutable authorizedDeployer;

    constructor() {
        authorizedDeployer = msg.sender;
    }

    function deploy(
        bytes32 salt,
        IPoolManager poolManager,
        address owner,
        address token,
        address feeAddress,
        uint16 feeBps,
        address operatorRewardsRouter,
        uint16 operatorRewardShareBps,
        int24 tickSpacing
    ) external returns (BurntatoSwapFeeHook hook) {
        if (msg.sender != authorizedDeployer) revert UnauthorizedDeployer(msg.sender);
        hook = new BurntatoSwapFeeHook{salt: salt}(
            poolManager, owner, token, feeAddress, feeBps, operatorRewardsRouter, operatorRewardShareBps, tickSpacing
        );
    }
}
