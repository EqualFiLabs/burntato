// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {DeployBurntatoLocalFork} from "../../script/DeployBurntatoLocalFork.s.sol";
import {DeployBurntatoRobinhoodTestnet} from "../../script/DeployBurntatoRobinhoodTestnet.s.sol";
import {FinalizeBurntatoRobinhoodTestnet} from "../../script/FinalizeBurntatoRobinhoodTestnet.s.sol";
import {BurntatoHookDeployer} from "../../script/helpers/BurntatoHookDeployer.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {RobinhoodDeploymentConfig} from "../../script/libraries/RobinhoodDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "../../script/libraries/StaticsOperatorDeploymentConfig.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "../../script/DeploymentTypes.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";
import {Errors} from "../../src/shared/Errors.sol";

interface IPoolManagerAuthority {
    function owner() external view returns (address);
    function protocolFeeController() external view returns (address);
    function setProtocolFeeController(address controller) external;
}

interface IPositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract LocalReplicaOperators {
    address public immutable activationRegistry;
    bool public launchFinalized = true;

    constructor(address activationRegistry_) {
        activationRegistry = activationRegistry_;
    }
}

contract LocalReplicaRegistry {
    address public genesisCollection;

    function bind(address genesisCollection_) external {
        genesisCollection = genesisCollection_;
    }
}

contract DeploymentConfigHarness {
    function checkedUint16(uint256 value) external pure returns (uint16) {
        return BurntatoDeploymentConfig.checkedUint16(value);
    }

    function checkedInt24(int256 value) external pure returns (int24) {
        return BurntatoDeploymentConfig.checkedInt24(value);
    }

    function hookOperatorRewardsRouter(uint256 operatorRewardShareBps, address router) external pure returns (address) {
        if (operatorRewardShareBps > type(uint16).max) revert();
        return BurntatoDeploymentConfig.hookOperatorRewardsRouter(uint16(operatorRewardShareBps), router);
    }

    function defaultInitialWinnerReserve(ProtocolConfig memory protocol) external pure returns (uint256) {
        return BurntatoDeploymentConfig.defaultInitialWinnerReserve(protocol);
    }
}

contract DeterministicDeploymentTest is Test {
    DeployBurntato internal deployScript;
    GenesisConfig internal config;
    BurntatoDeployment internal deployment;

    address internal buyer = makeAddr("deploymentBuyer");

    function setUp() public {
        deployScript = new DeployBurntato();
        config = deployScript.localDefaults();
        vm.deal(address(deployScript), config.initialWinnerReserve);
        deployment = deployScript.deploy(config, address(deployScript));
    }

    function test_DeploymentConfiguresCompleteGenesisState() public view {
        assertEq(IPoolManagerAuthority(deployment.poolManager).owner(), config.finalAdmin);
        assertEq(BurntatoSwapFeeHook(payable(deployment.hook)).owner(), config.finalAdmin);
        assertEq(deployment.admin, config.finalAdmin);
        assertTrue(IGovernance(deployment.diamond).foundationConfigured());
        assertFalse(IGovernance(deployment.diamond).purchasesInitialized());
        assertTrue(IPotatoToken(deployment.diamond).isDistributor(config.treasuryRecipient));
        assertEq(IGame(deployment.diamond).winnerReserveEth(), config.initialWinnerReserve);
        (uint256 genesisWinnerReserve, uint256 genesisRecoveryReserve) = IGame(deployment.diamond).roundReserves(1);
        assertEq(genesisWinnerReserve, config.initialWinnerReserve);
        assertEq(genesisRecoveryReserve, 0);
        (uint256 winnerReserve, uint256 recoveryReserve, uint256 winnerSponsored, uint256 recoverySponsored) =
            IGame(deployment.diamond).roundFunding(1);
        assertEq(winnerReserve, config.initialWinnerReserve);
        assertEq(recoveryReserve, 0);
        assertEq(winnerSponsored, 0);
        assertEq(recoverySponsored, 0);
        assertEq(deployment.diamond.balance, config.initialWinnerReserve);
    }

    function test_DefaultEmissionVestsAtFourMinutesAndMintsOnce() public {
        _initializePurchases(deployment, config.finalAdmin);
        IGame game = IGame(deployment.diamond);
        IPotatoToken token = IPotatoToken(deployment.diamond);
        uint256 supplyBefore = token.totalSupply();
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.buyPotato{value: config.protocol.startingPrice}();
        Round memory round = game.getRound(1);
        assertEq(round.winnerPool, 0.0105 ether);
        assertEq(game.winnerReserveEth(), 0.01 ether);
        assertEq(round.config.emissionVestingDuration, 4 minutes);
        assertEq(round.holderMaxReward, 10_000 ether);

        vm.warp(round.holderSince + 2 minutes);
        (uint256 halfEarned,) = game.currentEarnedEmission();
        assertEq(halfEarned, 5_000 ether);
        vm.expectRevert(Errors.VestingIncomplete.selector);
        game.materializeMaturedEmission();
        assertEq(token.totalSupply(), supplyBefore);

        vm.warp(round.holderSince + 4 minutes - 1);
        vm.expectRevert(Errors.VestingIncomplete.selector);
        game.materializeMaturedEmission();

        vm.warp(round.holderSince + 4 minutes);
        (uint256 earned,) = game.materializeMaturedEmission();
        assertEq(earned, 10_000 ether);
        assertEq(token.balanceOf(buyer), earned);
        assertEq(token.totalSupply() - supplyBefore, earned);

        vm.warp(round.deadline);
        ISettlement(deployment.diamond).settleRound();
        assertEq(token.totalSupply() - supplyBefore, earned);
        assertEq(game.getRound(1).remainingEmission, 90_000 ether);
    }

    function test_DefaultReplacementAfterTwoMinutesPreservesUnearnedBudget() public {
        _initializePurchases(deployment, config.finalAdmin);
        IGame game = IGame(deployment.diamond);
        IPotatoToken token = IPotatoToken(deployment.diamond);
        address successor = makeAddr("vesting-successor");
        vm.deal(buyer, 1 ether);
        vm.deal(successor, 1 ether);
        vm.prank(buyer);
        game.buyPotato{value: config.protocol.startingPrice}();
        Round memory round = game.getRound(1);
        vm.warp(round.holderSince + 2 minutes);
        vm.prank(successor);
        game.buyPotato{value: round.nextPrice}();

        round = game.getRound(1);
        assertEq(token.balanceOf(buyer), 5_000 ether);
        assertEq(round.remainingEmission, 95_000 ether);
        assertEq(round.holderMaxReward, 9_500 ether);
        vm.warp(round.holderSince + 4 minutes);
        game.materializeMaturedEmission();
        assertEq(token.balanceOf(successor), 9_500 ether);
        assertEq(game.getRound(1).remainingEmission, 85_500 ether);
    }

    function test_DefaultVestingCompletesBeforeMinimumRoundDeadline() public {
        _initializePurchases(deployment, config.finalAdmin);
        IGame game = IGame(deployment.diamond);
        vm.deal(buyer, 1 ether);
        uint256 price = config.protocol.startingPrice;
        for (uint256 i; i < 12; ++i) {
            vm.prank(buyer);
            game.buyPotato{value: price}();
            price = game.getRound(1).nextPrice;
        }
        Round memory round = game.getRound(1);
        assertEq(round.deadline - round.holderSince, 5 minutes);
        vm.warp(round.holderSince + 4 minutes);
        (uint256 earned,) = game.materializeMaturedEmission();
        assertEq(earned, 10_000 ether);
        assertEq(round.deadline - block.timestamp, 1 minutes);
    }

    function test_DeploymentOmitsLegacyPartialPauseSelectors() public view {
        IDiamondLoupe loupe = IDiamondLoupe(deployment.diamond);
        assertEq(loupe.facetAddress(bytes4(keccak256("purchasesPaused()"))), address(0));
        assertEq(loupe.facetAddress(bytes4(keccak256("commitmentsPaused()"))), address(0));
        assertEq(loupe.facetAddress(bytes4(keccak256("setPauseState(bool,bool)"))), address(0));
    }

    function test_BuyPotatoBlockedUntilFinalAdminInitializesOnce() public {
        vm.deal(buyer, config.protocol.startingPrice);
        vm.prank(buyer);
        vm.expectRevert(Errors.PurchasesNotInitialized.selector);
        IGame(deployment.diamond).buyPotato{value: config.protocol.startingPrice}();

        vm.prank(address(deployScript));
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, address(deployScript)));
        IGovernance(deployment.diamond).initializePurchases();

        vm.prank(config.guardian);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, config.guardian));
        IGovernance(deployment.diamond).initializePurchases();

        _initializePurchases(deployment, config.finalAdmin);
        assertTrue(IGovernance(deployment.diamond).purchasesInitialized());

        vm.prank(config.finalAdmin);
        vm.expectRevert(Errors.AlreadyInitialized.selector);
        IGovernance(deployment.diamond).initializePurchases();

        vm.prank(buyer);
        IGame(deployment.diamond).buyPotato{value: config.protocol.startingPrice}();
        assertEq(IGame(deployment.diamond).currentRoundId(), 1);
    }

    function test_CurrentAdminCanInitializePurchasesAfterAuthorityTransfer() public {
        IGovernance governance = IGovernance(deployment.diamond);
        address successor = makeAddr("successor-admin");

        vm.prank(config.finalAdmin);
        governance.setAuthority(successor);

        vm.prank(config.finalAdmin);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, config.finalAdmin));
        governance.initializePurchases();

        vm.prank(successor);
        governance.initializePurchases();
        assertTrue(governance.purchasesInitialized());
    }

    function test_PurchaseActivationDoesNotGateOtherProtocolSurfaces() public {
        IGovernance governance = IGovernance(deployment.diamond);
        assertFalse(governance.purchasesInitialized());
        assertFalse(governance.paused());

        address replacementGuardian = makeAddr("pre-activation-guardian");
        vm.prank(config.finalAdmin);
        governance.setGuardian(replacementGuardian);
        assertEq(governance.guardian(), replacementGuardian);

        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidRound.selector, 0));
        IRecovery(deployment.diamond).commitRecovery(1);

        IMarket market = IMarket(deployment.diamond);
        assertTrue(market.marketReady());
        (bytes32 poolId, uint128 liquidity) = market.launchMarket();
        assertNotEq(poolId, bytes32(0));
        assertGt(liquidity, 0);
        assertFalse(governance.purchasesInitialized());
    }

    function test_TestnetFinalCheckRejectsPausedProtocol() public {
        IGovernance governance = IGovernance(deployment.diamond);
        vm.startPrank(config.finalAdmin);
        governance.initializePurchases();
        governance.setPaused(true);
        vm.stopPrank();

        FinalizeBurntatoRobinhoodTestnet finalizer = new FinalizeBurntatoRobinhoodTestnet();
        vm.expectRevert(FinalizeBurntatoRobinhoodTestnet.ProtocolPaused.selector);
        finalizer.checkFinalizedDeployment(deployment.diamond, deployment.hook);
    }

    function _selectRobinhoodFork() internal {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) vm.skip(true, "ROBINHOOD_MAINNET is not configured");
        uint256 forkId = vm.createSelectFork(rpc, 45_234_856);
        vm.rollFork(forkId, 45_234_855);
    }

    function _selectStaticsFork() internal {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) vm.skip(true, "ROBINHOOD_MAINNET is not configured");
        vm.createSelectFork(rpc);
        vm.rollFork(StaticsOperatorDeploymentConfig.load().finalizedBlock);
    }

    function _selectRobinhoodTestnetFork() internal {
        string memory rpc = vm.envOr("ROBINHOOD_TESTNET", string(""));
        if (bytes(rpc).length == 0) vm.skip(true, "ROBINHOOD_TESTNET is not configured");
        vm.createSelectFork(rpc);
    }

    function test_RobinhoodTestnetProfilePinsApprovedEconomicsAndRoles() public {
        address deployer = makeAddr("testnet-deployer");
        GenesisConfig memory testnet = (new DeployBurntatoRobinhoodTestnet()).testnetConfig(deployer);

        assertEq(testnet.deployer, deployer);
        assertEq(testnet.finalAdmin, deployer);
        assertEq(testnet.guardian, deployer);
        assertEq(testnet.treasuryRecipient, deployer);
        assertEq(testnet.rewardAllocator, deployer);
        assertEq(testnet.protocol.emissionVestingDuration, 4 minutes);
        assertEq(testnet.protocol.winnerBps, 2_500);
        assertEq(testnet.protocol.nextRoundWinnerBps, 200);
        assertEq(testnet.protocol.recoveryBps, 3_000);
        assertEq(testnet.protocol.treasuryBps, 1_800);
        assertEq(testnet.protocol.buybackBps, 1_000);
        assertEq(testnet.protocol.operatorPurchaseBps, 1_500);
        assertEq(testnet.hookFeeBps, 100);
        assertEq(testnet.operatorRewardShareBps, 4_000);
        assertEq(testnet.initialWinnerReserve, 0.0105 ether);
        assertEq(testnet.initialTick, 170_280);
        assertEq(testnet.tickUpper, 170_280);
        assertEq(testnet.potatoSeed, 100_000_000 ether);
    }

    function test_RobinhoodTestnetManifestsMatchLiveDependencies() public {
        _selectRobinhoodTestnetFork();
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();

        RobinhoodDeploymentConfig.validate(dependencies);
        StaticsOperatorDeploymentConfig.validate(operatorDependencies);
        assertEq(dependencies.chainId, 46_630);
        assertEq(operatorDependencies.operatorsNft, 0x8BB2E39abAE7346293Ff084fd4D104b064BEbC71);
        assertEq(operatorDependencies.activationRegistry, 0xcE4D413915B4C6dE7DfD486d233596Da35c5cFbD);
    }

    function test_RobinhoodTestnetProfileDeploysAndLaunchesNativeMarket() public {
        _selectRobinhoodTestnetFork();
        DeployBurntatoRobinhoodTestnet testnetScript = new DeployBurntatoRobinhoodTestnet();
        GenesisConfig memory testnetConfig = testnetScript.testnetConfig(address(testnetScript));
        vm.deal(address(testnetScript), testnetConfig.initialWinnerReserve);
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();

        BurntatoDeployment memory testnetDeployment = testnetScript.deployWithDependencies(
            testnetConfig, address(testnetScript), dependencies, operatorDependencies
        );
        (bytes32 poolId, uint128 liquidity) = IMarket(testnetDeployment.diamond).launchMarket();
        (bytes32 actualPoolId,, bool launching, bool launched) = IMarket(testnetDeployment.diamond).marketState();

        assertEq(actualPoolId, poolId);
        assertGt(liquidity, 0);
        assertFalse(launching);
        assertTrue(launched);
    }

    function test_CanonicalDependenciesDeployOnlyOwnedContracts() public {
        _selectRobinhoodFork();
        DeployBurntato canonicalDeployScript = new DeployBurntato();
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        address poolManagerOwnerBefore = IPoolManagerAuthority(dependencies.poolManager).owner();

        GenesisConfig memory canonicalConfig = canonicalDeployScript.localDefaults();
        vm.deal(address(canonicalDeployScript), canonicalConfig.initialWinnerReserve);
        BurntatoDeployment memory canonicalDeployment =
            canonicalDeployScript.deployWithDependencies(canonicalConfig, address(canonicalDeployScript), dependencies);
        assertEq(IPoolManagerAuthority(dependencies.poolManager).owner(), poolManagerOwnerBefore);
        assertEq(canonicalDeployment.poolManager, dependencies.poolManager);
        assertEq(canonicalDeployment.positionManager, dependencies.positionManager);
        assertEq(canonicalDeployment.universalRouter, dependencies.universalRouter);
        assertEq(BurntatoSwapFeeHook(payable(canonicalDeployment.hook)).owner(), canonicalConfig.finalAdmin);
    }

    function test_CanonicalDependencyHashDriftFailsBeforeBurntatoDeployment() public {
        _selectRobinhoodFork();
        DeployBurntato canonicalDeployScript = new DeployBurntato();
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        dependencies.poolManagerCodeHash = bytes32(uint256(dependencies.poolManagerCodeHash) ^ 1);
        GenesisConfig memory canonicalConfig = canonicalDeployScript.localDefaults();
        uint256 deployScriptNonceBefore = vm.getNonce(address(canonicalDeployScript));

        vm.expectRevert(RobinhoodDeploymentConfig.InvalidCanonicalManifest.selector);
        canonicalDeployScript.deployWithDependencies(canonicalConfig, address(canonicalDeployScript), dependencies);

        assertEq(vm.getNonce(address(canonicalDeployScript)), deployScriptNonceBefore);
    }

    function test_CanonicalOperatorDependenciesDeployRouter() public {
        _selectStaticsFork();
        DeployBurntato canonicalDeployScript = new DeployBurntato();
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
        GenesisConfig memory canonicalConfig = canonicalDeployScript.localDefaults();
        canonicalConfig.operatorRewardShareBps = 4_000;
        vm.deal(address(canonicalDeployScript), canonicalConfig.initialWinnerReserve);

        BurntatoDeployment memory canonicalDeployment = canonicalDeployScript.deployWithDependencies(
            canonicalConfig, address(canonicalDeployScript), dependencies, operatorDependencies
        );
        BurntatoOperatorRewardsRouter router =
            BurntatoOperatorRewardsRouter(payable(canonicalDeployment.operatorRewardsRouter));
        assertEq(router.burntato(), canonicalDeployment.diamond);
        assertEq(address(router.operators()), operatorDependencies.operatorsNft);
        assertEq(address(router.activationRegistry()), operatorDependencies.activationRegistry);

        BurntatoSwapFeeHook hook = BurntatoSwapFeeHook(payable(canonicalDeployment.hook));
        vm.startPrank(canonicalConfig.finalAdmin);
        hook.setOperatorRewards(address(0), 0);
        vm.expectRevert(Errors.InvalidAddress.selector);
        hook.setFeeAddress(canonicalDeployment.operatorRewardsRouter);
        vm.stopPrank();
    }

    function test_LocalReplicaDependenciesValidateWithoutManifestHashes() public {
        vm.chainId(4663);
        LocalReplicaRegistry registry = new LocalReplicaRegistry();
        LocalReplicaOperators operators = new LocalReplicaOperators(address(registry));
        registry.bind(address(operators));

        StaticsOperatorDependencies memory replica = StaticsOperatorDependencies({
            chainId: block.chainid,
            finalizedBlock: block.number,
            finalizedBlockHash: bytes32(0),
            operatorsNft: address(operators),
            operatorsNftCodeHash: bytes32(0),
            activationRegistry: address(registry),
            activationRegistryCodeHash: bytes32(0)
        });
        StaticsOperatorDeploymentConfig.validateLocalReplica(replica);
    }

    function test_LocalDeploymentRejectsOperatorShareWithoutCanonicalDependencies() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.operatorRewardShareBps = 1;
        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_LocalForkEntrypointRejectsWrongChainBeforeRpcOrPrivateKey() public {
        DeployBurntatoLocalFork harness = new DeployBurntatoLocalFork();
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeployBurntatoLocalFork.InvalidLocalForkChain.selector, 1));
        harness.preflightLocalFork();
    }

    function test_DeploymentAcceptsMaximumHookFeeAndCallerReward() public {
        GenesisConfig memory maximumConfig = config;
        maximumConfig.hookFeeBps = 200;
        maximumConfig.buyback.callerRewardBps = 100;
        vm.deal(address(deployScript), maximumConfig.initialWinnerReserve);

        BurntatoDeployment memory maximumDeployment = deployScript.deploy(maximumConfig, address(deployScript));

        assertEq(BurntatoSwapFeeHook(payable(maximumDeployment.hook)).feeBps(), 200);
    }

    function test_DeploymentRejectsHookFeeAndCallerRewardAboveMaximum() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.hookFeeBps = 201;
        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));

        unsafeConfig = config;
        unsafeConfig.buyback.callerRewardBps = 101;
        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentAcceptsIndependentFinalAdmin() public {
        GenesisConfig memory independentAdminConfig = config;
        independentAdminConfig.finalAdmin = makeAddr("independent-final-admin");
        vm.deal(address(deployScript), independentAdminConfig.initialWinnerReserve);

        BurntatoDeployment memory independentAdminDeployment =
            deployScript.deploy(independentAdminConfig, address(deployScript));
        assertEq(IGovernance(independentAdminDeployment.diamond).authority(), independentAdminConfig.finalAdmin);
        assertEq(
            BurntatoSwapFeeHook(payable(independentAdminDeployment.hook)).owner(), independentAdminConfig.finalAdmin
        );
        assertEq(
            IPoolManagerAuthority(independentAdminDeployment.poolManager).owner(), independentAdminConfig.finalAdmin
        );
    }

    function test_DeploymentRejectsZeroFinalAdmin() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.finalAdmin = address(0);

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsTickSpacingOutsidePoolManagerDomain() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.tickSpacing = 32_768;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsTerminalUpperTickThatPoolManagerCannotInitialize() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.tickSpacing = 1;
        unsafeConfig.tickLower = TickMath.MIN_TICK;
        unsafeConfig.initialTick = TickMath.MAX_TICK;
        unsafeConfig.tickUpper = TickMath.MAX_TICK;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsTimeoutOutsideDeadlineDomain() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.protocol.roundTimeout = uint256(type(uint64).max) + 1;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsSeedAbovePositionManagerAmountDomain() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.potatoSeed = uint256(type(uint128).max) + 1;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsSeedWhoseLaunchLiquidityRoundsToZero() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.tickSpacing = 1;
        unsafeConfig.tickLower = TickMath.MIN_TICK;
        unsafeConfig.initialTick = TickMath.MAX_TICK - 1;
        unsafeConfig.tickUpper = TickMath.MAX_TICK - 1;
        unsafeConfig.potatoSeed = 1;

        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_DeploymentRejectsInvalidDiminishingTimeoutDomain() public {
        GenesisConfig memory unsafeConfig = config;
        unsafeConfig.protocol.minimumRoundTimeout = 0;
        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));

        unsafeConfig = config;
        unsafeConfig.protocol.minimumRoundTimeout = unsafeConfig.protocol.roundTimeout + 1;
        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));

        unsafeConfig = config;
        unsafeConfig.protocol.roundTimeoutDecay = unsafeConfig.protocol.roundTimeout + 1;
        vm.expectRevert(DeployBurntato.InvalidGenesisConfiguration.selector);
        deployScript.deploy(unsafeConfig, address(deployScript));
    }

    function test_HookDeployerRejectsUnauthorizedCaller() public {
        BurntatoHookDeployer hookDeployer = BurntatoHookDeployer(deployment.hookDeployer);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(BurntatoHookDeployer.UnauthorizedDeployer.selector, buyer));
        hookDeployer.deploy(
            bytes32(0), IPoolManager(address(0)), address(0), address(0), address(0), 0, address(0), 0, 0
        );
    }

    function test_EnvironmentNarrowingHelpersRejectTruncation() public {
        DeploymentConfigHarness harness = new DeploymentConfigHarness();

        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        harness.checkedUint16(uint256(type(uint16).max) + 1);
        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        harness.checkedInt24(int256(type(int24).max) + 1);
        vm.expectRevert(BurntatoDeploymentConfig.NarrowingOverflow.selector);
        harness.checkedInt24(int256(type(int24).min) - 1);
    }

    function test_DefaultWinnerReserveOpensAtFivePercentAboveFirstGrab() public {
        DeploymentConfigHarness harness = new DeploymentConfigHarness();
        ProtocolConfig memory protocol = config.protocol;
        assertEq(harness.defaultInitialWinnerReserve(protocol), 0.0105 ether);

        protocol.startingPrice = 0.003 ether;
        protocol.winnerBps = 3_500;
        assertEq(harness.defaultInitialWinnerReserve(protocol), 0.00315 ether);
    }

    function test_HookRouterConfigurationSupportsEveryRevenueCombination() public {
        DeploymentConfigHarness harness = new DeploymentConfigHarness();
        address router = makeAddr("operator-router");

        assertEq(harness.hookOperatorRewardsRouter(0, address(0)), address(0));
        assertEq(harness.hookOperatorRewardsRouter(0, router), address(0));
        assertEq(harness.hookOperatorRewardsRouter(4_000, router), router);
    }

    function test_GenesisPurchaseSnapshotsFixedEmissionBudget() public {
        _initializePurchases(deployment, config.finalAdmin);
        vm.deal(buyer, config.protocol.startingPrice);
        vm.prank(buyer);
        IGame(deployment.diamond).buyPotato{value: config.protocol.startingPrice}();

        Round memory round = IGame(deployment.diamond).getRound(1);
        assertEq(round.roundId, 1);
        assertEq(round.currentHolder, buyer);
        assertEq(round.config.roundTimeoutDecay, 5 minutes);
        assertEq(round.config.minimumRoundTimeout, 5 minutes);
        assertEq(round.deadline - round.holderSince, 1 hours);
        assertEq(round.remainingEmission, config.protocol.roundEmissionBudget);
        assertEq(round.holderMaxReward, config.protocol.roundEmissionBudget * config.protocol.emissionStepBps / 10_000);
        assertEq(
            round.nextPrice,
            config.protocol.startingPrice + config.protocol.startingPrice * config.protocol.priceIncreaseBps / 10_000
        );
    }

    function test_FinalAdminIsOnlyPathToAdministrativeMutation() public {
        address replacementGuardian = makeAddr("replacementGuardian");

        vm.prank(config.deployer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, config.deployer));
        IGovernance(deployment.diamond).setGuardian(replacementGuardian);

        vm.prank(config.finalAdmin);
        IGovernance(deployment.diamond).setGuardian(replacementGuardian);

        assertEq(IGovernance(deployment.diamond).guardian(), replacementGuardian);
    }

    function test_FinalAdminCanAdministerPoolManager() public {
        address controller = makeAddr("protocolFeeController");
        IPoolManagerAuthority poolManager = IPoolManagerAuthority(deployment.poolManager);

        vm.expectRevert();
        poolManager.setProtocolFeeController(controller);

        vm.prank(config.finalAdmin);
        poolManager.setProtocolFeeController(controller);

        assertEq(poolManager.protocolFeeController(), controller);
    }

    function test_LocalDependenciesLaunchLockedSingleSidedMarket() public {
        GenesisConfig memory launchConfig = config;
        launchConfig.potatoSeed = 1 ether;
        vm.deal(address(deployScript), launchConfig.initialWinnerReserve);
        BurntatoDeployment memory launchDeployment = deployScript.deploy(launchConfig, address(deployScript));
        IGame game = IGame(launchDeployment.diamond);
        IRecovery recovery = IRecovery(launchDeployment.diamond);
        ISettlement settlement = ISettlement(launchDeployment.diamond);
        _initializePurchases(launchDeployment, launchConfig.finalAdmin);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.buyPotato{value: launchConfig.protocol.startingPrice}();
        vm.warp(block.timestamp + launchConfig.protocol.emissionVestingDuration);
        game.materializeMaturedEmission();
        vm.prank(buyer);
        recovery.commitRecovery(10_000 ether);
        vm.warp(game.getRound(1).deadline);
        settlement.settleRound();

        vm.prank(buyer);
        game.buyPotato{value: launchConfig.protocol.startingPrice}();
        vm.warp(game.getRound(2).deadline);
        settlement.settleRound();

        IMarket market = IMarket(launchDeployment.diamond);
        assertEq(IPotatoToken(launchDeployment.diamond).balanceOf(launchDeployment.diamond), 1_001 ether);
        assertTrue(market.marketReady());
        (bytes32 poolId, uint128 liquidity) = market.launchMarket();
        assertNotEq(poolId, bytes32(0));
        assertGt(liquidity, 0);
        assertEq(IPositionOwner(launchDeployment.positionManager).ownerOf(1), market.lockedLpRecipient());
    }

    function _initializePurchases(BurntatoDeployment memory target, address finalAdmin) private {
        vm.prank(finalAdmin);
        IGovernance(target.diamond).initializePurchases();
    }
}
