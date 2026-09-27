// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {DeployBurntatoRobinhoodMainnet} from "../../script/DeployBurntatoRobinhoodMainnet.s.sol";
import {OperateBurntatoRobinhoodMainnet} from "../../script/OperateBurntatoRobinhoodMainnet.s.sol";
import {
    BurntatoDeployment,
    CanonicalV4Dependencies,
    GenesisConfig,
    StaticsOperatorDependencies
} from "../../script/DeploymentTypes.sol";
import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";

contract RobinhoodMainnetDeploymentTest is Test {
    DeployBurntato internal deployScript;
    OperateBurntatoRobinhoodMainnet internal operations;
    GenesisConfig internal config;
    BurntatoDeployment internal deployment;

    address internal guardian = makeAddr("mainnet-guardian");
    address internal treasury = makeAddr("mainnet-treasury");
    address internal rewardAllocator = makeAddr("mainnet-reward-allocator");

    receive() external payable {}

    function setUp() public {
        deployScript = new DeployBurntato();
        operations = new OperateBurntatoRobinhoodMainnet();
        config = deployScript.localDefaults();
        config.deployer = address(deployScript);
        config.finalAdmin = address(this);
        config.guardian = guardian;
        config.treasuryRecipient = treasury;
        config.rewardAllocator = rewardAllocator;
        vm.deal(address(deployScript), config.initialWinnerReserve);
        deployment = deployScript.deploy(config, address(deployScript));
    }

    function test_MainnetProfilePinsLaunchEconomicsAndExplicitRoles() public {
        DeployBurntatoRobinhoodMainnet mainnet = new DeployBurntatoRobinhoodMainnet();
        address deployer = makeAddr("mainnet-deployer");
        address admin = makeAddr("mainnet-admin");
        GenesisConfig memory mainnetConfig = mainnet.mainnetConfig(deployer, admin, guardian, treasury, rewardAllocator);

        assertEq(mainnetConfig.deployer, deployer);
        assertEq(mainnetConfig.finalAdmin, admin);
        assertEq(mainnetConfig.guardian, guardian);
        assertEq(mainnetConfig.treasuryRecipient, treasury);
        assertEq(mainnetConfig.rewardAllocator, rewardAllocator);
        assertEq(mainnetConfig.protocol.startingPrice, 0.01 ether);
        assertEq(mainnetConfig.protocol.priceIncreaseBps, 1_000);
        assertEq(mainnetConfig.protocol.roundTimeout, 1 hours);
        assertEq(mainnetConfig.protocol.roundTimeoutDecay, 5 minutes);
        assertEq(mainnetConfig.protocol.minimumRoundTimeout, 5 minutes);
        assertEq(mainnetConfig.protocol.roundEmissionBudget, 10_000 ether);
        assertEq(mainnetConfig.protocol.emissionVestingDuration, 4 minutes);
        assertEq(mainnetConfig.protocol.winnerBps, 2_500);
        assertEq(mainnetConfig.protocol.nextRoundWinnerBps, 200);
        assertEq(mainnetConfig.protocol.recoveryBps, 4_000);
        assertEq(mainnetConfig.protocol.treasuryBps, 500);
        assertEq(mainnetConfig.protocol.buybackBps, 1_300);
        assertEq(mainnetConfig.protocol.operatorPurchaseBps, 1_500);
        assertEq(mainnetConfig.buyback.maxSpend, 1 ether);
        assertEq(mainnetConfig.buyback.callerRewardBps, 50);
        assertEq(mainnetConfig.buyback.delayBlocks, 1);
        assertEq(mainnetConfig.hookFeeBps, 100);
        assertEq(mainnetConfig.operatorRewardShareBps, 4_000);
        assertEq(mainnetConfig.initialWinnerReserve, 0.0105 ether);
        assertEq(mainnetConfig.initialTick, 170_280);
        assertEq(mainnetConfig.potatoSeed, 100_000_000 ether);
    }

    function test_MainnetProfileRejectsImplicitCriticalRoles() public {
        DeployBurntatoRobinhoodMainnet mainnet = new DeployBurntatoRobinhoodMainnet();
        address deployer = makeAddr("mainnet-deployer");
        address admin = makeAddr("mainnet-admin");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBurntatoRobinhoodMainnet.InvalidMainnetRole.selector, bytes32("FINAL_ADMIN"), address(0)
            )
        );
        mainnet.mainnetConfig(deployer, address(0), guardian, treasury, rewardAllocator);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBurntatoRobinhoodMainnet.InvalidMainnetRole.selector, bytes32("TREASURY"), address(0)
            )
        );
        mainnet.mainnetConfig(deployer, admin, guardian, address(0), rewardAllocator);

        GenesisConfig memory guardianless =
            mainnet.mainnetConfig(deployer, admin, address(0), treasury, rewardAllocator);
        assertEq(guardianless.guardian, address(0));
    }

    function test_MainnetPreflightRejectsWrongChainBeforeEnvironmentReads() public {
        DeployBurntatoRobinhoodMainnet mainnet = new DeployBurntatoRobinhoodMainnet();
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeployBurntatoRobinhoodMainnet.InvalidMainnetChain.selector, 1));
        mainnet.preflight();
    }

    function test_MainnetPreflightValidatesLiveDependenciesAndExplicitRoles() public {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) vm.skip(true, "ROBINHOOD_MAINNET is not configured");
        vm.createSelectFork(rpc);

        DeployBurntatoRobinhoodMainnet mainnet = new DeployBurntatoRobinhoodMainnet();
        address expectedDeployer = makeAddr("preflight-deployer");
        address expectedAdmin = makeAddr("preflight-admin");
        vm.deal(expectedDeployer, 1 ether);
        vm.setEnv("BURNTATO_DEPLOYER", vm.toString(expectedDeployer));
        vm.setEnv("BURNTATO_FINAL_ADMIN", vm.toString(expectedAdmin));
        vm.setEnv("BURNTATO_GUARDIAN", vm.toString(guardian));
        vm.setEnv("BURNTATO_TREASURY", vm.toString(treasury));
        vm.setEnv("BURNTATO_REWARD_ALLOCATOR", vm.toString(rewardAllocator));

        (
            GenesisConfig memory mainnetConfig,
            CanonicalV4Dependencies memory dependencies,
            StaticsOperatorDependencies memory operatorDependencies
        ) = mainnet.preflight();

        assertEq(block.chainid, 4_663);
        assertEq(mainnetConfig.deployer, expectedDeployer);
        assertEq(mainnetConfig.finalAdmin, expectedAdmin);
        assertEq(dependencies.chainId, 4_663);
        assertEq(operatorDependencies.chainId, 4_663);
        assertGt(dependencies.poolManager.code.length, 0);
        assertGt(operatorDependencies.operatorsNft.code.length, 0);
    }

    function test_MainnetOperationsEnforcePhasedLaunchLifecycle() public {
        assertTrue(
            operations.checkDeployedDeployment(deployment.diamond, deployment.hook, config.finalAdmin, config.guardian)
        );

        IMarket(deployment.diamond).launchMarket();
        vm.expectRevert(OperateBurntatoRobinhoodMainnet.BuybackBootstrapIncomplete.selector);
        operations.checkReadyForInitializationDeployment(
            deployment.diamond, deployment.hook, config.finalAdmin, config.guardian, config.treasuryRecipient, 6
        );

        _completeMainnetBootstrap();
        assertTrue(
            operations.checkReadyForInitializationDeployment(
                deployment.diamond, deployment.hook, config.finalAdmin, config.guardian, config.treasuryRecipient, 6
            )
        );

        IGovernance(deployment.diamond).initializePurchases();
        assertTrue(
            operations.checkReadyForExternalBuysDeployment(
                deployment.diamond, deployment.hook, config.finalAdmin, config.guardian, config.treasuryRecipient, 6
            )
        );

        BurntatoSwapFeeHook(payable(deployment.hook)).setExternalBuysEnabled(true);
        assertTrue(
            operations.checkFinalizedDeployment(
                deployment.diamond, deployment.hook, config.finalAdmin, config.guardian, config.treasuryRecipient, 6
            )
        );
    }

    function test_MainnetInitializationCheckRejectsUnspentBootstrapReserve() public {
        IMarket(deployment.diamond).launchMarket();
        IBuyback buybacks = IBuyback(deployment.diamond);
        vm.deal(address(this), 5.025 ether);
        buybacks.fundBuybackReserve{value: 5.025 ether}();
        buybacks.buyback();
        uint256 reserve = buybacks.buybackReserveEth();

        vm.expectRevert(
            abi.encodeWithSelector(
                OperateBurntatoRobinhoodMainnet.BuybackReserveTooLarge.selector, uint256(100), reserve
            )
        );
        operations.checkReadyForInitializationDeployment(
            deployment.diamond, deployment.hook, config.finalAdmin, config.guardian, config.treasuryRecipient, 100
        );
    }

    function test_MainnetFinalCheckRejectsAdminAndGuardianDrift() public {
        IMarket(deployment.diamond).launchMarket();
        _completeMainnetBootstrap();
        IGovernance governance = IGovernance(deployment.diamond);
        governance.initializePurchases();
        BurntatoSwapFeeHook(payable(deployment.hook)).setExternalBuysEnabled(true);

        address wrongAdmin = makeAddr("wrong-admin");
        vm.expectRevert(
            abi.encodeWithSelector(
                OperateBurntatoRobinhoodMainnet.UnexpectedAuthority.selector, wrongAdmin, config.finalAdmin
            )
        );
        operations.checkFinalizedDeployment(
            deployment.diamond, deployment.hook, wrongAdmin, config.guardian, config.treasuryRecipient, 6
        );

        address wrongGuardian = makeAddr("wrong-guardian");
        vm.expectRevert(
            abi.encodeWithSelector(
                OperateBurntatoRobinhoodMainnet.UnexpectedGuardian.selector, wrongGuardian, config.guardian
            )
        );
        operations.checkFinalizedDeployment(
            deployment.diamond, deployment.hook, config.finalAdmin, wrongGuardian, config.treasuryRecipient, 6
        );

        address wrongTreasury = makeAddr("wrong-treasury");
        vm.expectRevert(
            abi.encodeWithSelector(
                OperateBurntatoRobinhoodMainnet.UnexpectedBootstrapPotato.selector,
                uint256(10_200_000 ether),
                uint256(10_400_000 ether),
                uint256(0)
            )
        );
        operations.checkFinalizedDeployment(
            deployment.diamond, deployment.hook, config.finalAdmin, config.guardian, wrongTreasury, 6
        );
    }

    function _completeMainnetBootstrap() private {
        IBuyback buybacks = IBuyback(deployment.diamond);
        uint256 grossTarget = 5.025 ether;
        vm.deal(address(this), grossTarget);
        buybacks.fundBuybackReserve{value: grossTarget}();
        for (uint256 index; index < 6; ++index) {
            buybacks.buyback();
            if (index < 5) vm.roll(block.number + 1);
        }
        assertLe(buybacks.buybackReserveEth(), 6);
        uint256 treasuryPotato = IPotatoToken(deployment.diamond).balanceOf(config.treasuryRecipient);
        assertGe(treasuryPotato, 10_200_000 ether);
        assertLe(treasuryPotato, 10_400_000 ether);
    }
}
