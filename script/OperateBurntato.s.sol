// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {VerifyBurntato} from "./VerifyBurntato.s.sol";
import {InitializeBurntato} from "./InitializeBurntato.s.sol";

/// @notice Activate a funded fresh deployment. This does not finalize protocol upgrades.
abstract contract OperateBurntato is InitializeBurntato {
    function run() public override returns (bool) {
        _requireChain();
        new VerifyBurntato().runAtPhase(1);
        string memory json = vm.readFile(vm.envString("BURNTATO_DEPLOYMENT_ARTIFACT"));
        require(
            vm.envAddress("BURNTATO_DIAMOND") == vm.parseJsonAddress(json, ".diamond"), "activation artifact mismatch"
        );
        return super.run();
    }

    function initializePurchases() external returns (bool) {
        return run();
    }

    function checkDeployed() external returns (bool) {
        _requireChain();
        return new VerifyBurntato().runAtPhase(3);
    }

    function checkStaged() external returns (bool) {
        _requireChain();
        return new VerifyBurntato().runAtPhase(1);
    }

    function checkReadyForInitialization() external returns (bool) {
        _requireChain();
        new VerifyBurntato().runAtPhase(1);
        string memory json = vm.readFile(vm.envString("BURNTATO_DEPLOYMENT_ARTIFACT"));
        checkReady(vm.parseJsonAddress(json, ".diamond"));
        return true;
    }

    function checkActive() external returns (bool) {
        _requireChain();
        return new VerifyBurntato().runAtPhase(2);
    }

    function _requireChain() private view {
        require(block.chainid == _chainId(), "incorrect Robinhood chain");
    }

    function _chainId() internal pure virtual returns (uint256);
}
