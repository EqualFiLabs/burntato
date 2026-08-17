// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";

abstract contract PositionManagerTestSetup is DeployPermit2 {
    IPositionManager internal positionManager;

    function _deployPositionManager(IPoolManager poolManager) internal {
        deployPermit2();
        positionManager = new PositionManager(
            poolManager,
            IAllowanceTransfer(PERMIT2_ADDRESS),
            100_000,
            IPositionDescriptor(address(0)),
            IWETH9(payable(address(0xeee)))
        );
    }
}
