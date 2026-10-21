// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {AnvilForkValidation} from "./libraries/AnvilForkValidation.sol";
import {DeployBurntato} from "./DeployBurntato.s.sol";
import {
    BurntatoDeployment,
    GenesisConfig,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {StaticsMarketDeploymentConfig} from "./libraries/StaticsMarketDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract DeployBurntatoRobinhoodMainnet is DeployBurntato {
    uint256 public constant CHAIN_ID = 4663;

    function _environmentConfig() internal view override returns (GenesisConfig memory c) {
        require(block.chainid == CHAIN_ID, "incorrect Robinhood chain");
        return super._environmentConfig();
    }

    function preflight()
        external
        returns (GenesisConfig memory c, StaticsMarketDependencies memory m, StaticsOperatorDependencies memory o)
    {
        c = _environmentConfig();
        m = StaticsMarketDeploymentConfig.load();
        o = StaticsOperatorDeploymentConfig.load();
        _validateMarket(m);
        _validateOperators(o);
        c.statics = m.statics;
        _validateConfig(c, c.deployer);
        require(c.deployer.balance >= c.initialWinnerReserve, "initial Winner reserve not funded");
    }

    function _validateMarket(StaticsMarketDependencies memory m) internal override {
        if (!vm.envOr("BURNTATO_ANVIL_REHEARSAL", false)) return super._validateMarket(m);
        AnvilForkValidation.requireMainnet();
        StaticsMarketDeploymentConfig.validateAnvilFork(
            m, AnvilForkValidation.height(), AnvilForkValidation.blockHash(m.forkBlock)
        );
    }

    function _validateOperators(StaticsOperatorDependencies memory o) internal override {
        if (!vm.envOr("BURNTATO_ANVIL_REHEARSAL", false)) return super._validateOperators(o);
        AnvilForkValidation.requireMainnet();
        StaticsOperatorDeploymentConfig.validateAnvilFork(
            o, AnvilForkValidation.height(), AnvilForkValidation.blockHash(o.finalizedBlock)
        );
    }

    function _deploymentMode() internal view override returns (string memory) {
        return vm.envOr("BURNTATO_ANVIL_REHEARSAL", false) ? "mainnet-rehearsal" : "production";
    }
}
