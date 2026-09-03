// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {BurntatoDeploymentVerifier} from "../../script/BurntatoDeploymentVerifier.sol";
import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {DeployBurntatoLocalFork} from "../../script/DeployBurntatoLocalFork.s.sol";
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
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {Round} from "../../src/shared/Types.sol";

interface IPoolManagerAuthority {
    function owner() external view returns (address);
    function protocolFeeController() external view returns (address);
    function setProtocolFeeController(address controller) external;
}

interface IPositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract DeploymentConfigHarness {
    function checkedUint16(uint256 value) external pure returns (uint16) {
        return BurntatoDeploymentConfig.checkedUint16(value);
    }

    function checkedInt24(int256 value) external pure returns (int24) {
        return BurntatoDeploymentConfig.checkedInt24(value);
    }
}

contract DeterministicDeploymentTest is Test {
    DeployBurntato internal deployScript;
    BurntatoDeploymentVerifier internal verifier;
    GenesisConfig internal config;
    BurntatoDeployment internal deployment;

    address internal buyer = makeAddr("deploymentBuyer");

    function setUp() public {
        deployScript = new DeployBurntato();
        verifier = new BurntatoDeploymentVerifier();
        config = deployScript.localDefaults();
        deployment = deployScript.deploy(config, address(deployScript));
    }

    function test_VerifierConfirmsCompleteGenesisDeployment() public view {
        assertTrue(verifier.verify(config, deployment));
        assertEq(IPoolManagerAuthority(deployment.poolManager).owner(), deployment.timelock);
        assertEq(BurntatoSwapFeeHook(payable(deployment.hook)).owner(), deployment.timelock);
        assertTrue(IPotatoToken(deployment.diamond).isDistributor(config.treasuryRecipient));
    }

    function test_GenericVerifierRejectsOperatorRewardsWithoutCanonicalDependencies() public {
        config.operatorRewardShareBps = 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoDeploymentVerifier.VerificationFailed.selector, bytes32("OPERATOR_CANONICAL_REQUIRED")
            )
        );
        verifier.verify(config, deployment);
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
        vm.createSelectFork(rpc, StaticsOperatorDeploymentConfig.load().finalizedBlock);
    }

    function test_CanonicalDependenciesDeployOnlyOwnedContractsAndVerify() public {
        _selectRobinhoodFork();
        DeployBurntato canonicalDeployScript = new DeployBurntato();
        BurntatoDeploymentVerifier canonicalVerifier = new BurntatoDeploymentVerifier();
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        address poolManagerOwnerBefore = IPoolManagerAuthority(dependencies.poolManager).owner();

        GenesisConfig memory canonicalConfig = canonicalDeployScript.localDefaults();
        BurntatoDeployment memory canonicalDeployment =
            canonicalDeployScript.deployWithDependencies(canonicalConfig, address(canonicalDeployScript), dependencies);
        assertTrue(canonicalVerifier.verifyCanonical(canonicalConfig, canonicalDeployment, dependencies));
        assertEq(IPoolManagerAuthority(dependencies.poolManager).owner(), poolManagerOwnerBefore);
        assertEq(canonicalDeployment.poolManager, dependencies.poolManager);
        assertEq(canonicalDeployment.positionManager, dependencies.positionManager);
        assertEq(canonicalDeployment.universalRouter, dependencies.universalRouter);
        assertEq(BurntatoSwapFeeHook(payable(canonicalDeployment.hook)).owner(), canonicalDeployment.timelock);
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

    function test_CanonicalOperatorDependenciesDeployRouterAndVerify() public {
        _selectStaticsFork();
        DeployBurntato canonicalDeployScript = new DeployBurntato();
        BurntatoDeploymentVerifier canonicalVerifier = new BurntatoDeploymentVerifier();
        CanonicalV4Dependencies memory dependencies = RobinhoodDeploymentConfig.load();
        StaticsOperatorDependencies memory operatorDependencies = StaticsOperatorDeploymentConfig.load();
        GenesisConfig memory canonicalConfig = canonicalDeployScript.localDefaults();
        canonicalConfig.operatorRewardShareBps = 4_000;

        BurntatoDeployment memory canonicalDeployment = canonicalDeployScript.deployWithDependencies(
            canonicalConfig, address(canonicalDeployScript), dependencies, operatorDependencies
        );
        assertTrue(
            canonicalVerifier.verifyCanonical(canonicalConfig, canonicalDeployment, dependencies, operatorDependencies)
        );
        BurntatoOperatorRewardsRouter router =
            BurntatoOperatorRewardsRouter(payable(canonicalDeployment.operatorRewardsRouter));
        assertEq(router.burntato(), canonicalDeployment.diamond);
        assertEq(address(router.operators()), operatorDependencies.operatorsNft);
        assertEq(address(router.activationRegistry()), operatorDependencies.activationRegistry);
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

    function test_DeploymentAcceptsZeroTimelockDelay() public {
        GenesisConfig memory zeroDelayConfig = config;
        zeroDelayConfig.timelockDelay = 0;

        BurntatoDeployment memory zeroDelayDeployment = deployScript.deploy(zeroDelayConfig, address(deployScript));
        assertTrue(verifier.verify(zeroDelayConfig, zeroDelayDeployment));
    }

    function test_DeploymentAcceptsBootstrapAsTimelockProposer() public {
        GenesisConfig memory sharedAuthorityConfig = config;
        sharedAuthorityConfig.proposer = address(deployScript);

        BurntatoDeployment memory sharedAuthorityDeployment =
            deployScript.deploy(sharedAuthorityConfig, address(deployScript));
        TimelockController timelock = TimelockController(payable(sharedAuthorityDeployment.timelock));
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(deployScript)));
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

    function test_VerifierRejectsProtocolConfigurationMismatch() public {
        GenesisConfig memory mismatched = config;
        mismatched.protocol.startingPrice += 1;

        vm.expectRevert(
            abi.encodeWithSelector(BurntatoDeploymentVerifier.VerificationFailed.selector, bytes32("STARTING_PRICE"))
        );
        verifier.verify(mismatched, deployment);
    }

    function test_VerifierRejectsDiminishingTimeoutMismatch() public {
        GenesisConfig memory mismatched = config;
        mismatched.protocol.roundTimeoutDecay += 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoDeploymentVerifier.VerificationFailed.selector, bytes32("ROUND_TIMEOUT_DECAY")
            )
        );
        verifier.verify(mismatched, deployment);

        mismatched = config;
        mismatched.protocol.minimumRoundTimeout += 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                BurntatoDeploymentVerifier.VerificationFailed.selector, bytes32("MINIMUM_ROUND_TIMEOUT")
            )
        );
        verifier.verify(mismatched, deployment);
    }

    function test_GenesisPurchaseSnapshotsFixedEmissionBudget() public {
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

    function test_TimelockIsOnlyPathToAdministrativeMutation() public {
        address replacementGuardian = makeAddr("replacementGuardian");
        bytes memory data = abi.encodeCall(IGovernance.setGuardian, (replacementGuardian));
        bytes32 predecessor;
        bytes32 salt = keccak256("replace guardian");
        TimelockController timelock = TimelockController(payable(deployment.timelock));

        vm.prank(config.deployer);
        vm.expectRevert();
        IGovernance(deployment.diamond).setGuardian(replacementGuardian);

        vm.prank(config.proposer);
        timelock.schedule(deployment.diamond, 0, data, predecessor, salt, config.timelockDelay);
        vm.warp(block.timestamp + config.timelockDelay);
        timelock.execute(deployment.diamond, 0, data, predecessor, salt);

        assertEq(IGovernance(deployment.diamond).guardian(), replacementGuardian);
    }

    function test_TimelockCanAdministerPoolManager() public {
        address controller = makeAddr("protocolFeeController");
        IPoolManagerAuthority poolManager = IPoolManagerAuthority(deployment.poolManager);

        vm.expectRevert();
        poolManager.setProtocolFeeController(controller);

        bytes memory data = abi.encodeCall(IPoolManagerAuthority.setProtocolFeeController, (controller));
        bytes32 salt = keccak256("set protocol fee controller");
        TimelockController timelock = TimelockController(payable(deployment.timelock));
        vm.prank(config.proposer);
        timelock.schedule(deployment.poolManager, 0, data, bytes32(0), salt, config.timelockDelay);
        vm.warp(block.timestamp + config.timelockDelay);
        timelock.execute(deployment.poolManager, 0, data, bytes32(0), salt);

        assertEq(poolManager.protocolFeeController(), controller);
    }

    function test_LocalDependenciesLaunchLockedSingleSidedMarket() public {
        GenesisConfig memory launchConfig = config;
        launchConfig.potatoSeed = 1 ether;
        BurntatoDeployment memory launchDeployment = deployScript.deploy(launchConfig, address(deployScript));
        IGame game = IGame(launchDeployment.diamond);
        IRecovery recovery = IRecovery(launchDeployment.diamond);
        ISettlement settlement = ISettlement(launchDeployment.diamond);

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.buyPotato{value: launchConfig.protocol.startingPrice}();
        vm.warp(block.timestamp + 120);
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
}
