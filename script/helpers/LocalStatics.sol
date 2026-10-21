// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {ERC20} from "solady/src/tokens/ERC20.sol";

/// @notice Disposable backing asset for standalone Anvil development only.
contract LocalStatics is ERC20 {
    constructor() {
        require(block.chainid == 31337, "standalone Anvil chain required");
    }

    function name() public pure override returns (string memory) {
        return "Local STATICS";
    }

    function symbol() public pure override returns (string memory) {
        return "STATICS";
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
