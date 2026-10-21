// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {AnvilForkValidation} from "./libraries/AnvilForkValidation.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {LibConfig} from "../src/libraries/LibConfig.sol";
import {DeployBurntato} from "./DeployBurntato.s.sol";
import {
    GenesisConfig,
    BurntatoDeployment,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {StaticsMarketDeploymentConfig} from "./libraries/StaticsMarketDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

contract DeployBurntatoLocalFork is DeployBurntato {
    bool private localReplica;

    function run() public override returns (BurntatoDeployment memory deployment) {
        AnvilForkValidation.requireMainnet();
        deployment = super.run();
        uint256 interval = vm.envOr("BURNTATO_LOCAL_INTERVAL_SECONDS", uint256(1));
        vm.rpc("anvil_setIntervalMining", string.concat("[", vm.toString(interval), "]"));
        // Anvil disables automining even for interval zero; keep transaction mining live.
        if (interval == 0) vm.rpc("anvil_setAutomine", "[true]");
    }

    function runLocalFork() external returns (BurntatoDeployment memory) {
        preflightLocalFork();
        return run();
    }

    function runLocalForkReplica() external returns (BurntatoDeployment memory deployment) {
        AnvilForkValidation.requireMainnet();
        localReplica = true;
        deployment = run();
        localReplica = false;
    }

    function preflightLocalFork() public returns (StaticsMarketDependencies memory m) {
        StaticsOperatorDependencies memory o = StaticsOperatorDeploymentConfig.load();
        require(AnvilForkValidation.height() == o.finalizedBlock, "incorrect initial fork block");
        return preflightDeployedLocalFork();
    }

    function preflightDeployedLocalFork() public returns (StaticsMarketDependencies memory m) {
        m = StaticsMarketDeploymentConfig.load();
        _validateMarket(m);
        _validateOperators(_operatorDependencies());
    }

    function _operatorDependencies() internal view override returns (StaticsOperatorDependencies memory o) {
        if (!localReplica) return super._operatorDependencies();
        o.chainId = block.chainid;
        o.finalizedBlock = block.number;
        o.operatorsNft = vm.envAddress("STATICS_GENESIS_NFT_ADDRESS");
        o.activationRegistry = vm.envAddress("STATICS_GENESIS_ACTIVATION_REGISTRY_ADDRESS");
        o.operatorsNftCodeHash = o.operatorsNft.codehash;
        o.activationRegistryCodeHash = o.activationRegistry.codehash;
    }

    function _validateMarket(StaticsMarketDependencies memory m) internal override {
        AnvilForkValidation.requireMainnet();
        StaticsMarketDeploymentConfig.validateAnvilFork(
            m, AnvilForkValidation.height(), AnvilForkValidation.blockHash(m.forkBlock)
        );
    }

    function _validateOperators(StaticsOperatorDependencies memory o) internal override {
        AnvilForkValidation.requireMainnet();
        if (localReplica) {
            StaticsOperatorDeploymentConfig.validateLocalReplica(o);
        } else {
            StaticsOperatorDeploymentConfig.validateAnvilFork(
                o, AnvilForkValidation.height(), AnvilForkValidation.blockHash(o.finalizedBlock)
            );
        }
    }

    function _environmentConfig() internal view override returns (GenesisConfig memory config) {
        require(block.chainid == 4663, "mainnet fork required");
        config = BurntatoDeploymentConfig.launchDefaults();
        uint256 key = vm.envOr("PRIVATE_KEY", uint256(0));
        if (key != 0) config.deployer = vm.addr(key);
        config.deployer = vm.envOr("BURNTATO_DEPLOYER", config.deployer);
        config.finalAdmin = vm.envOr("BURNTATO_FINAL_ADMIN", config.finalAdmin);
        config.guardian = vm.envOr("BURNTATO_GUARDIAN", config.guardian);
        config.treasuryRecipient = vm.envOr("BURNTATO_TREASURY", config.treasuryRecipient);
        config.rewardAllocator = vm.envOr("BURNTATO_REWARD_ALLOCATOR", config.rewardAllocator);
        config.protocol.startingPrice = vm.envOr("BURNTATO_STARTING_PRICE", config.protocol.startingPrice);
        config.protocol.priceIncreaseBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_PRICE_INCREASE_BPS", uint256(config.protocol.priceIncreaseBps))
        );
        config.protocol.roundTimeout = vm.envOr("BURNTATO_ROUND_TIMEOUT", config.protocol.roundTimeout);
        config.protocol.roundTimeoutDecay = vm.envOr("BURNTATO_ROUND_TIMEOUT_DECAY", config.protocol.roundTimeoutDecay);
        config.protocol.minimumRoundTimeout =
            vm.envOr("BURNTATO_MINIMUM_ROUND_TIMEOUT", config.protocol.minimumRoundTimeout);
        config.protocol.roundEmissionBudget =
            vm.envOr("BURNTATO_ROUND_EMISSION_BUDGET", config.protocol.roundEmissionBudget);
        config.protocol.emissionStepBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_EMISSION_STEP_BPS", uint256(config.protocol.emissionStepBps))
        );
        config.protocol.emissionVestingDuration =
            vm.envOr("BURNTATO_EMISSION_VESTING_DURATION", config.protocol.emissionVestingDuration);
        config.protocol.winnerBps =
            BurntatoDeploymentConfig.checkedUint16(vm.envOr("BURNTATO_WINNER_BPS", uint256(config.protocol.winnerBps)));
        config.protocol.nextRoundWinnerBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_NEXT_ROUND_WINNER_BPS", uint256(config.protocol.nextRoundWinnerBps))
        );
        config.protocol.recoveryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_BPS", uint256(config.protocol.recoveryBps))
        );
        config.protocol.treasuryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_TREASURY_BPS", uint256(config.protocol.treasuryBps))
        );
        config.protocol.buybackBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_BUYBACK_BPS", uint256(config.protocol.buybackBps))
        );
        config.protocol.operatorPurchaseBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_OPERATOR_PURCHASE_BPS", uint256(config.protocol.operatorPurchaseBps))
        );
        config.initialWinnerReserve = vm.envOr(
            "BURNTATO_INITIAL_WINNER_RESERVE", BurntatoDeploymentConfig.defaultInitialWinnerReserve(config.protocol)
        );
        config.buyback.maxSpend = vm.envOr("BURNTATO_BUYBACK_MAX_SPEND", config.buyback.maxSpend);
        config.buyback.callerRewardBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_BUYBACK_CALLER_REWARD_BPS", uint256(config.buyback.callerRewardBps))
        );
        config.buyback.delayBlocks = vm.envOr("BURNTATO_BUYBACK_DELAY_BLOCKS", config.buyback.delayBlocks);
        LibConfig.validate(config.protocol);
        if (config.buyback.callerRewardBps > 100) revert InvalidGenesisConfiguration();
        return config;
    }

    function _outputDirectory() internal pure override returns (string memory) {
        return "artifacts/robinhood-local";
    }

    function _deploymentMode() internal view override returns (string memory) {
        return localReplica ? "local-replica" : "local-fork";
    }
}
