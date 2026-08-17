// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";

contract BurntatoHookDeployer {
    function deploy(
        bytes32 salt,
        IPoolManager poolManager,
        address owner,
        address token,
        address feeAddress,
        uint16 feeBps,
        int24 tickSpacing
    ) external returns (BurntatoSwapFeeHook hook) {
        hook = new BurntatoSwapFeeHook{salt: salt}(poolManager, owner, token, feeAddress, feeBps, tickSpacing);
    }
}
