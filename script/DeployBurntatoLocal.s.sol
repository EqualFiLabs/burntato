// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {DeployBurntato} from "./DeployBurntato.s.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {
    BurntatoDeployment,
    GenesisConfig,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {LocalStatics} from "./helpers/LocalStatics.sol";
import {LocalWETH9} from "./helpers/LocalWETH9.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

/// @notice Standalone development fixtures; never used by a public-network entrypoint.
contract DeployBurntatoLocal is DeployBurntato {
    function run() public override returns (BurntatoDeployment memory d) {
        require(block.chainid == 31337 && vm.rpc("anvil_getAutomine", "[]").length != 0, "standalone Anvil required");
        GenesisConfig memory c = BurntatoDeploymentConfig.localDefaults();
        uint256 key = vm.envUint("PRIVATE_KEY");
        require(key != 0, "local deployer key required");
        c.deployer = vm.addr(key);
        c.finalAdmin = vm.envOr("BURNTATO_FINAL_ADMIN", c.finalAdmin);
        c.guardian = vm.envOr("BURNTATO_GUARDIAN", c.guardian);
        c.treasuryRecipient = vm.envOr("BURNTATO_TREASURY", c.treasuryRecipient);
        c.rewardAllocator = vm.envOr("BURNTATO_REWARD_ALLOCATOR", c.rewardAllocator);
        vm.startBroadcast(key);
        StaticsMarketDependencies memory m = _localMarket(c.deployer);
        c.statics = m.statics;
        StaticsOperatorDependencies memory o;
        d = deployWithDependencies(c, c.deployer, m, o);
        vm.stopBroadcast();
        _writeDeployment(d, c, m, o, "artifacts/robinhood-local");
        _log(d);
    }

    function _localMarket(address owner) internal returns (StaticsMarketDependencies memory m) {
        require(block.chainid == 31337, "standalone Anvil chain required");
        LocalStatics statics = new LocalStatics();
        LocalWETH9 weth = new LocalWETH9();
        IPoolManager manager = IPoolManager(address(new PoolManager(owner)));
        m.chainId = block.chainid;
        m.statics = address(statics);
        m.staticsCodeHash = address(statics).codehash;
        m.weth = address(weth);
        m.wethCodeHash = address(weth).codehash;
        m.poolManager = address(manager);
        m.poolManagerCodeHash = address(manager).codehash;
        (address c0, address c1) =
            address(statics) < address(weth) ? (address(statics), address(weth)) : (address(weth), address(statics));
        m.key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 15000, 100, IHooks(address(0)));
        m.poolId = PoolId.unwrap(PoolIdLibrary.toId(m.key));
        manager.initialize(m.key, uint160(1 << 96));
        PoolModifyLiquidityTest liquidity = new PoolModifyLiquidityTest(manager);
        statics.mint(owner, 1_000_000 ether);
        weth.deposit{value: 100 ether}();
        statics.approve(address(liquidity), 100 ether);
        weth.approve(address(liquidity), 100 ether);
        liquidity.modifyLiquidity(m.key, ModifyLiquidityParams(-887200, 887200, int256(100 ether), bytes32(0)), "");
    }

    function _deploymentMode() internal pure override returns (string memory) {
        return "local";
    }
}
