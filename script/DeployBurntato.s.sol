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
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {FacetCut, FacetCutAction} from "../src/shared/Types.sol";
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

        address[] memory proposers = new address[](1);
        proposers[0] = config.proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        deployment.timelock = address(new TimelockController(config.timelockDelay, proposers, executors, address(0)));

        deployment.poolManager = address(new PoolManager(address(0)));
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

        deployment.diamondCutFacet = address(new DiamondCutFacet());
        deployment.diamond = address(new BurntatoDiamond(bootstrapAuthority, deployment.diamondCutFacet));
        deployment.diamondLoupeFacet = address(new DiamondLoupeFacet());
        deployment.governanceFacet = address(new GovernanceFacet());
        deployment.marketFacet = address(new MarketFacet());
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
                    FoundationInit.initialize, (config.startingPrice, config.priceIncreaseBps, config.treasuryRecipient)
                )
            );

        deployment.hookDeployer = address(new BurntatoHookDeployer());
        bytes memory constructorArgs = abi.encode(IPoolManager(deployment.poolManager), deployment.diamond);
        (address expectedHook, bytes32 salt) = HookMiner.find(
            deployment.hookDeployer, _hookFlags(), type(BurntatoSwapFeeHook).creationCode, constructorArgs
        );
        deployment.hook = address(
            BurntatoHookDeployer(deployment.hookDeployer)
                .deploy(salt, IPoolManager(deployment.poolManager), deployment.diamond)
        );
        if (deployment.hook != expectedHook) revert UnexpectedHookAddress(expectedHook, deployment.hook);

        IGovernance(deployment.diamond).setGuardian(config.guardian);
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
                    nativeSeed: config.nativeSeed,
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
        config.startingPrice = vm.envOr("BURNTATO_STARTING_PRICE", config.startingPrice);
        config.priceIncreaseBps = uint16(vm.envOr("BURNTATO_PRICE_INCREASE_BPS", uint256(config.priceIncreaseBps)));
        config.initialTick = int24(vm.envOr("BURNTATO_INITIAL_TICK", int256(config.initialTick)));
        config.tickSpacing = int24(vm.envOr("BURNTATO_TICK_SPACING", int256(config.tickSpacing)));
        config.tickLower = int24(vm.envOr("BURNTATO_TICK_LOWER", int256(config.tickLower)));
        config.tickUpper = int24(vm.envOr("BURNTATO_TICK_UPPER", int256(config.tickUpper)));
        config.nativeSeed = vm.envOr("BURNTATO_NATIVE_SEED", config.nativeSeed);
        config.potatoSeed = vm.envOr("BURNTATO_POTATO_SEED", config.potatoSeed);
    }

    function _initialCut(BurntatoDeployment memory deployment) private pure returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](8);
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
            facetAddress: deployment.gameFacet, action: FacetCutAction.Add, functionSelectors: BurntatoSelectors.game()
        });
        cuts[5] = FacetCut({
            facetAddress: deployment.recoveryFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.recovery()
        });
        cuts[6] = FacetCut({
            facetAddress: deployment.settlementFacet,
            action: FacetCutAction.Add,
            functionSelectors: BurntatoSelectors.settlement()
        });
        cuts[7] = FacetCut({
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
        if (
            bootstrapAuthority == address(0) || config.deployer == address(0) || config.proposer == address(0)
                || config.guardian == address(0) || config.treasuryRecipient == address(0)
                || config.proposer == bootstrapAuthority || config.timelockDelay < Constants.MIN_TIMELOCK_DELAY
                || config.startingPrice == 0 || config.priceIncreaseBps == 0 || config.priceIncreaseBps > 10_000
                || config.tickSpacing <= 0 || config.tickLower >= config.initialTick
                || config.initialTick >= config.tickUpper || config.tickLower % config.tickSpacing != 0
                || config.tickUpper % config.tickSpacing != 0 || config.nativeSeed == 0 || config.potatoSeed == 0
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
        console2.log("PotatoTokenFacet", deployment.potatoTokenFacet);
        console2.log("GameFacet", deployment.gameFacet);
        console2.log("RecoveryFacet", deployment.recoveryFacet);
        console2.log("SettlementFacet", deployment.settlementFacet);
        console2.log("ClaimsFacet", deployment.claimsFacet);
        console2.log("FoundationInit", deployment.foundationInit);
    }
}
