// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {MockOperatorCollection, MockActivationRegistry} from "../unit/OperatorRewardsRouter.t.sol";
import {BurntatoOperatorRewardsRouter} from "../../src/rewards/BurntatoOperatorRewardsRouter.sol";
import {VerifyBurntato} from "../../script/VerifyBurntato.s.sol";
import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {OperateBurntatoRobinhoodMainnet} from "../../script/OperateBurntatoRobinhoodMainnet.s.sol";
import {OperateBurntatoRobinhoodTestnet} from "../../script/OperateBurntatoRobinhoodTestnet.s.sol";
import {InitializeBurntato} from "../../script/InitializeBurntato.s.sol";
import {BurntatoDeploymentConfig} from "../../script/libraries/BurntatoDeploymentConfig.sol";
import {BurntatoSelectors} from "../../script/libraries/BurntatoSelectors.sol";
import {StaticsMarketDeploymentConfig} from "../../script/libraries/StaticsMarketDeploymentConfig.sol";
import {
    GenesisConfig,
    BurntatoDeployment,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "../../script/DeploymentTypes.sol";
import {MockStatics} from "../mocks/MockStatics.sol";
import {LocalWETH9} from "../../script/helpers/LocalWETH9.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {Errors} from "../../src/shared/Errors.sol";

contract DeploymentArtifactHarness is DeployBurntato {
    function writeArtifact(BurntatoDeployment memory d, GenesisConfig memory c, StaticsMarketDependencies memory m)
        external
    {
        StaticsOperatorDependencies memory o;
        _writeDeployment(d, c, m, o, "artifacts/robinhood-local/artifact-test");
    }
}

contract BackedDeploymentTest is Test {
    DeployBurntato internal deployer;
    GenesisConfig internal config;
    StaticsMarketDependencies internal market;
    BurntatoDeployment internal deployment;
    MockStatics internal statics;
    address internal admin = makeAddr("admin");

    function setUp() public {
        deployer = new DeployBurntato();
        statics = new MockStatics();
        address weth = address(new LocalWETH9());
        address manager = address(new PoolManager(address(this)));
        (address c0, address c1) = address(statics) < weth ? (address(statics), weth) : (weth, address(statics));
        market.chainId = block.chainid;
        market.statics = address(statics);
        market.staticsCodeHash = address(statics).codehash;
        market.weth = weth;
        market.wethCodeHash = weth.codehash;
        market.poolManager = manager;
        market.poolManagerCodeHash = manager.codehash;
        market.key = PoolKey(Currency.wrap(c0), Currency.wrap(c1), 15000, 100, IHooks(address(0)));
        market.poolId = PoolId.unwrap(PoolIdLibrary.toId(market.key));
        IPoolManager(manager).initialize(market.key, uint160(1 << 96));
        config = BurntatoDeploymentConfig.localDefaults();
        config.deployer = address(deployer);
        config.finalAdmin = admin;
        config.statics = address(statics);
        vm.deal(address(deployer), config.initialWinnerReserve);
        StaticsOperatorDependencies memory operators;
        deployment = deployer.deployWithDependencies(config, address(deployer), market, operators);
    }

    function test_FreshDeploymentHasZeroSupplyBackingAndInactivePurchases() public view {
        IPotatoToken token = IPotatoToken(deployment.diamond);
        assertEq(token.totalSupply(), 0);
        assertEq(token.backingBalance(), 0);
        assertEq(token.rewardReserve(), 0);
        assertEq(token.underlying(), address(statics));
        assertEq(token.publicWrapCap(), 0);
        assertEq(token.availablePublicWrapCapacity(), 0);
        assertEq(IGovernance(deployment.diamond).authority(), admin);
        assertFalse(IGovernance(deployment.diamond).purchasesInitialized());
        assertEq(IGame(deployment.diamond).winnerReserveEth(), 0.00315 ether);
        assertEq(IDiamondLoupe(deployment.diamond).facetAddresses().length, 10);
    }

    function test_SelectorsMatchFreshIntegrationAndExcludeOldMarket() public view {
        IDiamondLoupe loupe = IDiamondLoupe(deployment.diamond);
        bytes4[] memory token = BurntatoSelectors.token();
        for (uint256 i; i < token.length; ++i) {
            assertEq(loupe.facetAddress(token[i]), deployment.potatoTokenFacet);
        }
        bytes4[] memory buyback = BurntatoSelectors.buyback();
        for (uint256 i; i < buyback.length; ++i) {
            assertEq(loupe.facetAddress(buyback[i]), deployment.buybackFacet);
        }
        assertEq(loupe.facetAddress(bytes4(keccak256("burn(uint256)"))), address(0));
        assertEq(loupe.facetAddress(bytes4(keccak256("launchMarket()"))), address(0));
        assertEq(loupe.facetAddress(bytes4(keccak256("canonicalHook()"))), address(0));
        assertEq(loupe.facetAddress(bytes4(keccak256("protocolMint(address,uint256)"))), address(0));
    }

    function test_ActualReserveFundingAndAuthorityActivationStartGameplay() public {
        InitializeBurntato activation = new InitializeBurntato();
        vm.expectRevert(abi.encodeWithSelector(InitializeBurntato.RewardReserveNotFunded.selector, 20_000 ether, 0));
        activation.checkReady(deployment.diamond);
        vm.prank(admin);
        IGovernance(deployment.diamond).initializePurchases();
        uint256 beforeBalance = address(this).balance;
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientRewardReserve.selector, 0, 20_000 ether));
        IGame(deployment.diamond).buyPotato{value: 0.003 ether}();
        assertEq(address(this).balance, beforeBalance);
        statics.mint(address(this), 20_000 ether);
        statics.approve(deployment.diamond, 20_000 ether);
        IPotatoToken(deployment.diamond).fundRewardReserve(20_000 ether);
        IGame(deployment.diamond).buyPotato{value: 0.003 ether}();
        assertEq(IGame(deployment.diamond).getRound(1).currentHolder, address(this));
    }

    function test_ZeroLaunchCapAllowsEarnedRedemptionAndOnlyAuthorityCanOpenWrapping() public {
        IPotatoToken token = IPotatoToken(deployment.diamond);
        IGame game = IGame(deployment.diamond);
        statics.mint(address(this), 20_000 ether);
        statics.approve(deployment.diamond, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Errors.PublicWrapCapacityExceeded.selector, 0, 1));
        token.wrap(1);
        assertEq(statics.balanceOf(address(this)), 20_000 ether);
        token.fundRewardReserve(20_000 ether);
        vm.prank(admin);
        IGovernance(deployment.diamond).initializePurchases();
        game.buyPotato{value: 0.003 ether}();
        vm.warp(block.timestamp + 4 minutes);
        game.materializeMaturedEmission();
        assertEq(token.balanceOf(address(this)), 1_000 ether);
        token.unwrap(1_000 ether);
        assertEq(statics.balanceOf(address(this)), 1_000 ether);
        assertEq(token.rewardReserve(), 19_000 ether);
        assertEq(token.publicWrapOutstanding(), 0);
        assertEq(token.publicWrapCap(), 0);
        assertEq(token.availablePublicWrapCapacity(), 0);
        vm.expectRevert(abi.encodeWithSelector(Errors.PublicWrapCapacityExceeded.selector, 0, 1));
        token.wrap(1);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthority.selector, address(this)));
        token.setPublicWrapCap(1_000 ether);
        vm.prank(admin);
        token.setPublicWrapCap(1_000 ether);
        token.wrap(1_000 ether);
        assertEq(token.publicWrapOutstanding(), 1_000 ether);
        assertEq(token.balanceOf(address(this)), 1_000 ether);
        assertEq(token.backingBalance(), token.totalSupply());
    }

    function test_DependencyDriftFailsBeforeOwnedDeployment() public {
        market.staticsCodeHash = keccak256("wrong runtime");
        StaticsOperatorDependencies memory operators;
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsMarketDeploymentConfig.InvalidMarketCode.selector,
                market.statics,
                market.staticsCodeHash,
                market.statics.codehash
            )
        );
        deployer.deployWithDependencies(config, address(deployer), market, operators);
    }

    function test_VerifierChecksCompiledSourceAndFreshDeploymentState() public {
        StaticsOperatorDependencies memory operators;
        new VerifyBurntato().verify(deployment, config, market, operators, 0);
    }

    function test_ActivationExportsCalldataOnlyAfterFunding() public {
        statics.mint(address(this), 20_000 ether);
        statics.approve(deployment.diamond, 20_000 ether);
        IPotatoToken(deployment.diamond).fundRewardReserve(20_000 ether);
        (address target, bytes memory data) = new InitializeBurntato().initializationCall(deployment.diamond);
        assertEq(target, deployment.diamond);
        assertEq(data, abi.encodeCall(IGovernance.initializePurchases, ()));
    }

    function test_VerifierChecksFundedAndActivatedPhases() public {
        StaticsOperatorDependencies memory operators;
        VerifyBurntato verifier = new VerifyBurntato();
        statics.mint(address(this), 20_000 ether);
        statics.approve(deployment.diamond, 20_000 ether);
        IPotatoToken(deployment.diamond).fundRewardReserve(20_000 ether);
        verifier.verify(deployment, config, market, operators, 1);
        vm.prank(admin);
        IGovernance(deployment.diamond).initializePurchases();
        verifier.verify(deployment, config, market, operators, 2);
        vm.etch(deployment.gameFacet, hex"00");
        vm.expectRevert("facet source runtime");
        verifier.verify(deployment, config, market, operators, 2);
    }

    function test_ReadableArtifactMatchesEncodedEconomicsAndRejectsTampering() public {
        vm.setEnv("BURNTATO_SOURCE_COMMIT", "1111111111111111111111111111111111111111");
        new DeploymentArtifactHarness().writeArtifact(deployment, config, market);
        string memory path = "artifacts/robinhood-local/artifact-test/deployment.json";
        string memory json = vm.readFile(path);
        GenesisConfig memory encoded = abi.decode(vm.parseJsonBytes(json, ".genesisConfig"), (GenesisConfig));
        assertEq(keccak256(abi.encode(encoded)), keccak256(abi.encode(config)));
        VerifyBurntato verifier = new VerifyBurntato();
        verifier.verifyReadableConfig(json, deployment, encoded);
        vm.writeJson("2501", path, ".winnerBps");
        vm.expectRevert("artifact winnerBps");
        verifier.verifyReadableConfig(vm.readFile(path), deployment, encoded);
    }

    function test_ActivatedFreshDeploymentStillRequiresFirstRoundFundingForRelease() public {
        StaticsOperatorDependencies memory operators;
        VerifyBurntato verifier = new VerifyBurntato();
        vm.prank(admin);
        IGovernance(deployment.diamond).initializePurchases();
        vm.expectRevert("unfunded first round");
        verifier.verify(deployment, config, market, operators, 2);
        // Inspection remains usable before funding, independently of activation status.
        verifier.verify(deployment, config, market, operators, 3);
    }

    function test_NetworkActivationChecksChainBeforeReadingKey() public {
        OperateBurntatoRobinhoodMainnet mainnet = new OperateBurntatoRobinhoodMainnet();
        OperateBurntatoRobinhoodTestnet testnet = new OperateBurntatoRobinhoodTestnet();
        vm.chainId(1);
        vm.expectRevert("incorrect Robinhood chain");
        mainnet.run();
        vm.expectRevert("incorrect Robinhood chain");
        testnet.run();
    }

    function test_VerifierRejectsCounterfeitOperatorRuntimeWithCorrectBindings() public {
        MockOperatorCollection operators = new MockOperatorCollection();
        MockActivationRegistry registry = new MockActivationRegistry();
        operators.setActivationRegistry(address(registry));
        registry.setGenesisCollection(address(operators));
        BurntatoOperatorRewardsRouter router =
            new BurntatoOperatorRewardsRouter(deployment.diamond, address(operators), address(registry));
        VerifyBurntato verifier = new VerifyBurntato();
        verifier.verifyOperatorRouter(address(router), deployment.diamond, address(operators), address(registry));
        bytes memory code = address(router).code;
        // Append unreachable code: getter results stay identical but deployed source differs.
        vm.etch(address(router), bytes.concat(code, hex"00"));
        assertEq(router.burntato(), deployment.diamond);
        assertEq(address(router.operators()), address(operators));
        assertEq(address(router.activationRegistry()), address(registry));
        vm.expectRevert("operator router source runtime");
        verifier.verifyOperatorRouter(address(router), deployment.diamond, address(operators), address(registry));
    }
}
