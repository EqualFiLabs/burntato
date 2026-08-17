// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAllowanceTransfer} from "@uniswap/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {PositionDescriptor} from "@uniswap/v4-periphery/src/PositionDescriptor.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {BurntatoDiamond} from "../src/BurntatoDiamond.sol";
import {ClaimsFacet} from "../src/facets/ClaimsFacet.sol";
import {BuybackFacet} from "../src/facets/BuybackFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {GameFacet} from "../src/facets/GameFacet.sol";
import {GovernanceFacet} from "../src/facets/GovernanceFacet.sol";
import {MarketFacet} from "../src/facets/MarketFacet.sol";
import {PotatoTokenFacet} from "../src/facets/PotatoTokenFacet.sol";
import {RecoveryFacet} from "../src/facets/RecoveryFacet.sol";
import {SettlementFacet} from "../src/facets/SettlementFacet.sol";
import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {FoundationInit} from "../src/initializers/FoundationInit.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";
import {FacetCut, FacetCutAction, ProtocolConfig} from "../src/shared/Types.sol";
import {Constants} from "../src/shared/Constants.sol";
import {BurntatoDeployment, GenesisConfig} from "./DeploymentTypes.sol";
import {BurntatoHookDeployer} from "./helpers/BurntatoHookDeployer.sol";
import {LocalPermit2} from "./helpers/LocalPermit2.sol";
import {LocalWETH9} from "./helpers/LocalWETH9.sol";
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {BurntatoSelectors} from "./libraries/BurntatoSelectors.sol";

contract DeployBurntato is Script {
    error InvalidGenesisConfiguration();
    error UnexpectedHookAddress(address expected, address actual);

    uint256 internal constant POSITION_MANAGER_UNSUBSCRIBE_GAS_LIMIT = 100_000;
    bytes32 internal constant NATIVE_CURRENCY_LABEL = "ETH";

    function run() external returns (BurntatoDeployment memory deployment) {
        GenesisConfig memory config = _environmentConfig();
        vm.startBroadcast(config.deployer);
        deployment = deploy(config, config.deployer);
        vm.stopBroadcast();
        _log(deployment);
    }

    function deploy(GenesisConfig memory config, address bootstrapAuthority)
        public
        returns (BurntatoDeployment memory deployment)
    {
        _validateConfig(config, bootstrapAuthority);
        _deployTimelock(config, deployment);
        _deployUniswap(deployment);
        _deployDiamond(config, bootstrapAuthority, deployment);
        _deployHook(config, deployment);
        _configureProtocol(config, deployment);
    }

    function _deployTimelock(GenesisConfig memory config, BurntatoDeployment memory deployment) private {
        address[] memory proposers = new address[](1);
        proposers[0] = config.proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        deployment.timelock = address(new TimelockController(config.timelockDelay, proposers, executors, address(0)));
    }

    function _deployUniswap(BurntatoDeployment memory deployment) private {
        deployment.poolManager = address(new PoolManager(deployment.timelock));
        deployment.permit2 = address(new LocalPermit2());
        deployment.weth9 = address(new LocalWETH9());
        deployment.positionDescriptor = address(
            new PositionDescriptor(IPoolManager(deployment.poolManager), deployment.weth9, NATIVE_CURRENCY_LABEL)
        );
        deployment.positionManager = address(
            new PositionManager(
                IPoolManager(deployment.poolManager),
                IAllowanceTransfer(deployment.permit2),
                POSITION_MANAGER_UNSUBSCRIBE_GAS_LIMIT,
                IPositionDescriptor(deployment.positionDescriptor),
                IWETH9(deployment.weth9)
            )
        );
    }

    function _deployDiamond(
        GenesisConfig memory config,
        address bootstrapAuthority,
        BurntatoDeployment memory deployment
    ) private {
        deployment.diamondCutFacet = address(new DiamondCutFacet());
        deployment.diamond = address(new BurntatoDiamond(bootstrapAuthority, deployment.diamondCutFacet));
        deployment.diamondLoupeFacet = address(new DiamondLoupeFacet());
        deployment.governanceFacet = address(new GovernanceFacet());
        deployment.marketFacet = address(new MarketFacet());
        deployment.buybackFacet = address(new BuybackFacet());
        deployment.potatoTokenFacet = address(new PotatoTokenFacet());
        deployment.gameFacet = address(new GameFacet());
        deployment.recoveryFacet = address(new RecoveryFacet());
        deployment.settlementFacet = address(new SettlementFacet());
        deployment.claimsFacet = address(new ClaimsFacet());
        deployment.foundationInit = address(new FoundationInit());

        IDiamondCut(deployment.diamond)
            .diamondCut(
                _initialCut(deployment),
                deployment.foundationInit,
                abi.encodeCall(
                    FoundationInit.initialize, (config.protocol, config.treasuryRecipient, config.potatoSeed)
                )
            );
    }

    function _deployHook(GenesisConfig memory config, BurntatoDeployment memory deployment) private {
        deployment.hookDeployer = address(new BurntatoHookDeployer());
        bytes memory constructorArgs = abi.encode(
            IPoolManager(deployment.poolManager),
            deployment.timelock,
            deployment.diamond,
            config.treasuryRecipient,
            config.hookFeeBps,
            config.tickSpacing
        );
        (address expectedHook, bytes32 salt) = HookMiner.find(
            deployment.hookDeployer, _hookFlags(), type(BurntatoSwapFeeHook).creationCode, constructorArgs
        );
        deployment.hook = address(
            BurntatoHookDeployer(deployment.hookDeployer)
                .deploy(
                    salt,
                    IPoolManager(deployment.poolManager),
                    deployment.timelock,
                    deployment.diamond,
                    config.treasuryRecipient,
                    config.hookFeeBps,
                    config.tickSpacing
                )
        );
        if (deployment.hook != expectedHook) revert UnexpectedHookAddress(expectedHook, deployment.hook);
    }

    function _configureProtocol(GenesisConfig memory config, BurntatoDeployment memory deployment) private {
        IGovernance(deployment.diamond).setGuardian(config.guardian);
        IPotatoToken(deployment.diamond).setDistributor(config.treasuryRecipient, true);
        IBuyback(deployment.diamond).setBuybackConfig(config.buyback);
        IMarket(deployment.diamond)
            .configureMarket(
                IMarket.MarketConfig({
                    hook: deployment.hook,
                    poolManager: deployment.poolManager,
                    positionManager: deployment.positionManager,
                    permit2: deployment.permit2,
                    sqrtPriceX96: TickMath.getSqrtPriceAtTick(config.initialTick),
                    tickLower: config.tickLower,
                    tickUpper: config.tickUpper,
                    tickSpacing: config.tickSpacing,
                    potatoSeed: config.potatoSeed
                })
            );
        IGovernance(deployment.diamond).setAuthority(deployment.timelock);
    }

    function localDefaults() external pure returns (GenesisConfig memory config) {
        return BurntatoDeploymentConfig.localDefaults();
    }

    function _environmentConfig() private view returns (GenesisConfig memory config) {
        config = BurntatoDeploymentConfig.localDefaults();
        config.deployer = vm.envOr("BURNTATO_DEPLOYER", config.deployer);
        config.proposer = vm.envOr("BURNTATO_PROPOSER", config.proposer);
        config.guardian = vm.envOr("BURNTATO_GUARDIAN", config.guardian);
        config.treasuryRecipient = vm.envOr("BURNTATO_TREASURY", config.treasuryRecipient);
        config.timelockDelay = vm.envOr("BURNTATO_TIMELOCK_DELAY", config.timelockDelay);
        config.protocol.startingPrice = vm.envOr("BURNTATO_STARTING_PRICE", config.protocol.startingPrice);
        config.protocol.priceIncreaseBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_PRICE_INCREASE_BPS", uint256(config.protocol.priceIncreaseBps))
        );
        config.protocol.roundTimeout = vm.envOr("BURNTATO_ROUND_TIMEOUT", config.protocol.roundTimeout);
        config.protocol.roundEmissionBudget =
            vm.envOr("BURNTATO_ROUND_EMISSION_BUDGET", config.protocol.roundEmissionBudget);
        config.protocol.emissionStepBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_EMISSION_STEP_BPS", uint256(config.protocol.emissionStepBps))
        );
        config.protocol.emissionVestingDuration =
            vm.envOr("BURNTATO_EMISSION_VESTING_DURATION", config.protocol.emissionVestingDuration);
        config.protocol.winnerBps =
            BurntatoDeploymentConfig.checkedUint16(vm.envOr("BURNTATO_WINNER_BPS", uint256(config.protocol.winnerBps)));
        config.protocol.recoveryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_BPS", uint256(config.protocol.recoveryBps))
        );
        config.protocol.treasuryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_TREASURY_BPS", uint256(config.protocol.treasuryBps))
        );
        config.protocol.buybackBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_BUYBACK_BPS", uint256(config.protocol.buybackBps))
        );
        config.protocol.recoveryBurnBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_BURN_BPS", uint256(config.protocol.recoveryBurnBps))
        );
        config.protocol.recoveryTreasuryBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_RECOVERY_TREASURY_BPS", uint256(config.protocol.recoveryTreasuryBps))
        );
        config.buyback.maxSpend = vm.envOr("BURNTATO_BUYBACK_MAX_SPEND", config.buyback.maxSpend);
        config.buyback.callerRewardBps = BurntatoDeploymentConfig.checkedUint16(
            vm.envOr("BURNTATO_BUYBACK_CALLER_REWARD_BPS", uint256(config.buyback.callerRewardBps))
        );
        config.buyback.delayBlocks = vm.envOr("BURNTATO_BUYBACK_DELAY_BLOCKS", config.buyback.delayBlocks);
        config.hookFeeBps =
            BurntatoDeploymentConfig.checkedUint16(vm.envOr("BURNTATO_HOOK_FEE_BPS", uint256(config.hookFeeBps)));
        config.initialTick =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_INITIAL_TICK", int256(config.initialTick)));
        config.tickSpacing =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_TICK_SPACING", int256(config.tickSpacing)));
        config.tickLower =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_TICK_LOWER", int256(config.tickLower)));
        config.tickUpper =
            BurntatoDeploymentConfig.checkedInt24(vm.envOr("BURNTATO_TICK_UPPER", int256(config.tickUpper)));
        config.potatoSeed = vm.envOr("BURNTATO_POTATO_SEED", config.potatoSeed);
    }

    function _initialCut(BurntatoDeployment memory deployment) private pure returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](9);
        cuts[0] = FacetCut({
            facetAddress: deployment.diamondLoupeFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.loupe()
        });
        cuts[1] = FacetCut({
            facetAddress: deployment.governanceFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.governance()
        });
        cuts[2] = FacetCut({
            facetAddress: deployment.marketFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.market()
        });
        cuts[3] = FacetCut({
            facetAddress: deployment.potatoTokenFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.token()
        });
        cuts[4] = FacetCut({
            facetAddress: deployment.buybackFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.buyback()
        });
        cuts[5] = FacetCut({
            facetAddress: deployment.gameFacet, action: FacetCutAction.Add, functionSelectors: BurntatoSelectors.game()
        });
        cuts[6] = FacetCut({
            facetAddress: deployment.recoveryFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.recovery()
        });
        cuts[7] = FacetCut({
            facetAddress: deployment.settlementFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.settlement()
        });
        cuts[8] = FacetCut({
            facetAddress: deployment.claimsFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.claims()
        });
    }

    function _hookFlags() private pure returns (uint160) {
        return uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
    }

    function _validateConfig(GenesisConfig memory config, address bootstrapAuthority) private pure {
        ProtocolConfig memory protocol = config.protocol;
        if (
            bootstrapAuthority == address(0) || config.deployer == address(0) || config.proposer == address(0)
                || config.treasuryRecipient == address(0) || protocol.startingPrice == 0 || protocol.roundTimeout == 0
                || protocol.roundTimeout > type(uint64).max || protocol.emissionVestingDuration == 0
                || protocol.priceIncreaseBps > Constants.BPS || protocol.emissionStepBps > Constants.BPS
                || protocol.winnerBps > Constants.BPS || protocol.recoveryBps > Constants.BPS
                || protocol.treasuryBps > Constants.BPS || protocol.buybackBps > Constants.BPS
                || protocol.recoveryBurnBps > Constants.BPS || protocol.recoveryTreasuryBps > Constants.BPS
                || config.hookFeeBps > Constants.BPS || config.buyback.callerRewardBps > Constants.BPS
                || uint256(protocol.winnerBps) + protocol.recoveryBps + protocol.treasuryBps + protocol.buybackBps
                    != Constants.BPS
                || uint256(protocol.recoveryBurnBps) + protocol.recoveryTreasuryBps != Constants.BPS
                || config.tickSpacing < TickMath.MIN_TICK_SPACING || config.tickSpacing > TickMath.MAX_TICK_SPACING
                || config.tickLower < TickMath.MIN_TICK || config.tickUpper > TickMath.MAX_TICK
                || config.tickLower >= config.initialTick || config.initialTick != config.tickUpper
                || config.tickLower % config.tickSpacing != 0 || config.tickUpper % config.tickSpacing != 0
                || config.potatoSeed == 0
        ) revert InvalidGenesisConfiguration();
    }

    function _log(BurntatoDeployment memory deployment) private pure {
        console2.log("BurntatoDiamond", deployment.diamond);
        console2.log("TimelockController", deployment.timelock);
        console2.log("PoolManager", deployment.poolManager);
        console2.log("LocalPermit2", deployment.permit2);
        console2.log("LocalWETH9", deployment.weth9);
        console2.log("PositionDescriptor", deployment.positionDescriptor);
        console2.log("PositionManager", deployment.positionManager);
        console2.log("BurntatoHookDeployer", deployment.hookDeployer);
        console2.log("BurntatoSwapFeeHook", deployment.hook);
        console2.log("DiamondCutFacet", deployment.diamondCutFacet);
        console2.log("DiamondLoupeFacet", deployment.diamondLoupeFacet);
        console2.log("GovernanceFacet", deployment.governanceFacet);
        console2.log("MarketFacet", deployment.marketFacet);
        console2.log("BuybackFacet", deployment.buybackFacet);
        console2.log("PotatoTokenFacet", deployment.potatoTokenFacet);
        console2.log("GameFacet", deployment.gameFacet);
        console2.log("RecoveryFacet", deployment.recoveryFacet);
        console2.log("SettlementFacet", deployment.settlementFacet);
        console2.log("ClaimsFacet", deployment.claimsFacet);
        console2.log("FoundationInit", deployment.foundationInit);
    }
}
