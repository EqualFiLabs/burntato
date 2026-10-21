// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {OperateBurntato} from "./OperateBurntato.s.sol";

/// @notice Activate and inspect a funded deployment without finalizing upgrades.
contract OperateBurntatoRobinhoodMainnet is OperateBurntato {
    function _chainId() internal pure override returns (uint256) {
        return 4663;
    }
}
