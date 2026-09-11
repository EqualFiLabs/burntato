// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 arbBlockNumber) external view returns (bytes32);
}

library RobinhoodBlockProvenance {
    IArbSys private constant ARB_SYS = IArbSys(address(100));

    function blockNumber() internal view returns (uint256) {
        return ARB_SYS.arbBlockNumber();
    }

    function blockHash(uint256 arbBlockNumber) internal view returns (bytes32) {
        return ARB_SYS.arbBlockHash(arbBlockNumber);
    }
}
