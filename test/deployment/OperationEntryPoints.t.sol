// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {OperateBurntatoRobinhoodMainnet} from "../../script/OperateBurntatoRobinhoodMainnet.s.sol";
import {OperateBurntatoRobinhoodTestnet} from "../../script/OperateBurntatoRobinhoodTestnet.s.sol";

contract OperationEntryPointsTest is Test {
    /// @dev Both wrappers must gate every inherited entrypoint before reading an
    /// artifact or signing; on their intended chain they must invoke verification.
    function test_AllNetworkOperationsEnforceChainAndArtifactVerification() public {
        address mainnet = address(new OperateBurntatoRobinhoodMainnet());
        address testnet = address(new OperateBurntatoRobinhoodTestnet());
        string memory path = "artifacts/robinhood-local/operation-entrypoint-test.json";
        vm.createDir("artifacts/robinhood-local", true);
        vm.writeFile(path, '{"schemaVersion":3}');
        vm.setEnv("BURNTATO_DEPLOYMENT_ARTIFACT", path);
        bytes4[6] memory selectors = [
            bytes4(keccak256("run()")),
            bytes4(keccak256("initializePurchases()")),
            bytes4(keccak256("checkDeployed()")),
            bytes4(keccak256("checkStaged()")),
            bytes4(keccak256("checkReadyForInitialization()")),
            bytes4(keccak256("checkActive()"))
        ];
        for (uint256 i; i < selectors.length; ++i) {
            vm.chainId(4663);
            _assertRejected(mainnet, selectors[i], "historical artifact unsupported");
            _assertRejected(testnet, selectors[i], "incorrect Robinhood chain");
            vm.chainId(46630);
            _assertRejected(testnet, selectors[i], "historical artifact unsupported");
            _assertRejected(mainnet, selectors[i], "incorrect Robinhood chain");
        }
    }

    function _assertRejected(address operation, bytes4 selector, string memory message) private {
        (bool success, bytes memory reason) = operation.call(abi.encodeWithSelector(selector));
        assertFalse(success);
        assertEq(reason, abi.encodeWithSignature("Error(string)", message));
    }
}
