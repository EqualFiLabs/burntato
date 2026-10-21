// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Vm} from "forge-std/Vm.sol";
import {LibString} from "solady/src/utils/LibString.sol";

library AnvilForkValidation {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function requireMainnet() internal {
        require(block.chainid == 4663, "mainnet fork required");
        require(vm.rpc("anvil_getAutomine", "[]").length != 0, "Anvil fork required");
    }

    function height() internal returns (uint256 n) {
        bytes memory encoded = vm.rpc("eth_blockNumber", "[]");
        for (uint256 i; i < encoded.length; ++i) {
            n = (n << 8) | uint8(encoded[i]);
        }
    }

    function blockHash(uint256 n) internal returns (bytes32) {
        string memory json =
            vm.rpcJson("eth_getBlockByNumber", string.concat("[\"", LibString.toMinimalHexString(n), "\",false]"));
        return vm.parseJsonBytes32(json, ".hash");
    }
}
