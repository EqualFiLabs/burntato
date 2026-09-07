// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {GenesisConfig} from "../DeploymentTypes.sol";

library BurntatoGenesisCodec {
    function encode(GenesisConfig memory config) internal pure returns (bytes memory) {
        return abi.encode(config);
    }

    function decode(bytes memory encoded) internal pure returns (GenesisConfig memory config) {
        config = abi.decode(encoded, (GenesisConfig));
    }
}
