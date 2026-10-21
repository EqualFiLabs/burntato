// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {StaticsMarketDependencies} from "../DeploymentTypes.sol";
import {RobinhoodBlockProvenance} from "./RobinhoodBlockProvenance.sol";

library StaticsMarketDeploymentConfig {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    error InvalidMarketManifest();
    error InvalidMarketChain(uint256 expected, uint256 actual);
    error InvalidMarketBlock(uint256 expectedMinimum, uint256 actual);
    error InvalidMarketBlockHash(bytes32 expected, bytes32 actual);
    error InvalidMarketCode(address dependency, bytes32 expected, bytes32 actual);
    error InvalidPoolKey();
    error MarketNotInitialized();

    function load() internal view returns (StaticsMarketDependencies memory d) {
        string memory path;
        if (block.chainid == 4663) path = "deployments/statics-market-robinhood-4663.json";
        else if (block.chainid == 46630) path = "deployments/statics-market-robinhood-testnet-46630.json";
        else revert InvalidMarketChain(4663, block.chainid);
        string memory manifest = vm.readFile(path);
        d.chainId = vm.parseJsonUint(manifest, ".chainId");
        d.forkBlock = vm.parseJsonUint(manifest, ".forkBlock");
        d.forkBlockHash = vm.parseJsonBytes32(manifest, ".forkBlockHash");
        d.statics = vm.parseJsonAddress(manifest, ".contracts.statics.address");
        d.staticsCodeHash = vm.parseJsonBytes32(manifest, ".contracts.statics.runtimeCodeHash");
        d.weth = vm.parseJsonAddress(manifest, ".contracts.weth.address");
        d.wethCodeHash = vm.parseJsonBytes32(manifest, ".contracts.weth.runtimeCodeHash");
        d.poolManager = vm.parseJsonAddress(manifest, ".contracts.poolManager.address");
        d.poolManagerCodeHash = vm.parseJsonBytes32(manifest, ".contracts.poolManager.runtimeCodeHash");
        d.hookCodeHash = vm.parseJsonBytes32(manifest, ".contracts.hook.runtimeCodeHash");
        d.poolId = vm.parseJsonBytes32(manifest, ".poolId");
        d.key = PoolKey({
            currency0: Currency.wrap(vm.parseJsonAddress(manifest, ".poolKey.currency0")),
            currency1: Currency.wrap(vm.parseJsonAddress(manifest, ".poolKey.currency1")),
            fee: uint24(vm.parseJsonUint(manifest, ".poolKey.fee")),
            tickSpacing: int24(vm.parseJsonInt(manifest, ".poolKey.tickSpacing")),
            hooks: IHooks(vm.parseJsonAddress(manifest, ".poolKey.hooks"))
        });
    }

    function requireManifest(StaticsMarketDependencies memory d) internal view {
        if (keccak256(abi.encode(d)) != keccak256(abi.encode(load()))) revert InvalidMarketManifest();
    }

    function validate(StaticsMarketDependencies memory d) internal view {
        requireManifest(d);
        uint256 currentBlock = RobinhoodBlockProvenance.blockNumber();
        if (currentBlock < d.forkBlock) revert InvalidMarketBlock(d.forkBlock, currentBlock);
        if (currentBlock > d.forkBlock && currentBlock - d.forkBlock <= 256) {
            bytes32 actualHash = RobinhoodBlockProvenance.blockHash(d.forkBlock);
            if (actualHash != d.forkBlockHash) revert InvalidMarketBlockHash(d.forkBlockHash, actualHash);
        }
        validateRuntime(d);
    }

    /// @dev Only for a separately verified Anvil/fork historical block hash.
    function validateAnvilFork(StaticsMarketDependencies memory d, uint256 currentBlock, bytes32 actualHash)
        internal
        view
    {
        requireManifest(d);
        if (currentBlock < d.forkBlock) revert InvalidMarketBlock(d.forkBlock, currentBlock);
        if (actualHash != d.forkBlockHash) revert InvalidMarketBlockHash(d.forkBlockHash, actualHash);
        validateRuntime(d);
    }

    function validateRuntime(StaticsMarketDependencies memory d) internal view {
        if (block.chainid != d.chainId) revert InvalidMarketChain(d.chainId, block.chainid);
        _code(d.statics, d.staticsCodeHash);
        _code(d.weth, d.wethCodeHash);
        _code(d.poolManager, d.poolManagerCodeHash);
        if (address(d.key.hooks) != address(0)) _code(address(d.key.hooks), d.hookCodeHash);
        address c0 = Currency.unwrap(d.key.currency0);
        address c1 = Currency.unwrap(d.key.currency1);
        if (
            c0 >= c1 || d.statics == d.weth || d.weth == address(0) || d.key.tickSpacing <= 0
                || !((c0 == d.weth && c1 == d.statics) || (c0 == d.statics && c1 == d.weth))
                || PoolId.unwrap(PoolIdLibrary.toId(d.key)) != d.poolId || IERC20Metadata(d.statics).decimals() != 18
                || IERC20Metadata(d.weth).decimals() != 18
        ) revert InvalidPoolKey();
        (uint160 sqrtPriceX96,,,) = StateLibrary.getSlot0(IPoolManager(d.poolManager), PoolId.wrap(d.poolId));
        if (sqrtPriceX96 == 0) revert MarketNotInitialized();
    }

    function _code(address target, bytes32 expected) private view {
        if (target.code.length == 0 || expected == bytes32(0) || target.codehash != expected) {
            revert InvalidMarketCode(target, expected, target.codehash);
        }
    }
}
