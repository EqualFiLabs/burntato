// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {IAllowanceTransfer} from "@uniswap/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {Plan, Planner} from "@uniswap/v4-periphery/test/shared/Planner.sol";
import {Permit2SignatureHelpers} from "@uniswap/v4-periphery/test/shared/Permit2SignatureHelpers.sol";

import {BurntatoDeploymentVerifier} from "../../script/BurntatoDeploymentVerifier.sol";
import {DeployBurntato} from "../../script/DeployBurntato.s.sol";
import {BurntatoDeployment, CanonicalV4Dependencies, GenesisConfig} from "../../script/DeploymentTypes.sol";
import {RobinhoodDeploymentConfig} from "../../script/libraries/RobinhoodDeploymentConfig.sol";
import {BurntatoSwapFeeHook} from "../../src/hooks/BurntatoSwapFeeHook.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IGame} from "../../src/interfaces/IGame.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IMarket} from "../../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {IRecovery} from "../../src/interfaces/IRecovery.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {ITreasuryRewards} from "../../src/interfaces/ITreasuryRewards.sol";
import {RewardSchedule, Round} from "../../src/shared/Types.sol";

interface IUniversalRouter {
    function poolManager() external view returns (address);
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IPositionManagerBindings {
    function poolManager() external view returns (address);
    function permit2() external view returns (address);
    function tokenDescriptor() external view returns (address);
    function WETH9() external view returns (address);
    function nextTokenId() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

struct RouterExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    uint256 minHopPriceX36;
    bytes hookData;
}

contract RobinhoodBurntatoForkTest is Test, Permit2SignatureHelpers {
    using Planner for Plan;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 private constant FORK_BLOCK = 45_234_855;
    bytes32 private constant FORK_BLOCK_HASH = 0xd65b81057261cc49ef60573d9f500ec9563257d673e10f1ff8d3d7c6ce33670d;
    bytes1 private constant PERMIT2_PERMIT_ALLOW_REVERT = 0x8a;
    bytes1 private constant V4_SWAP = 0x10;

    uint256 private constant ALICE_KEY = 0xA11CE;
    uint256 private constant BOB_KEY = 0xB0B;
    uint256 private constant CAROL_KEY = 0xCA401;
    uint256 private constant DAVE_KEY = 0xDA7E;
    uint256 private constant ERIN_KEY = 0xE71;

    CanonicalV4Dependencies private dependencies;
    GenesisConfig private config;
    BurntatoDeployment private deployment;
    DeployBurntato private deployer;
    BurntatoDeploymentVerifier private verifier;

    address private alice;
    address private bob;
    address private carol;
    address private dave;
    address private erin;
    address private keeper;

    IBuyback private buybacks;
    IClaims private claims;
    IGame private game;
    IGovernance private governance;
    IMarket private market;
    IPotatoToken private potato;
    IRecovery private recovery;
    ISettlement private settlement;
    ITreasuryRewards private rewards;
    BurntatoSwapFeeHook private hook;
    IPoolManager private poolManager;
    IAllowanceTransfer private permit2;
    IV4Quoter private quoter;
    IUniversalRouter private router;
    PoolKey private key;

    function setUp() public {
        uint256 overrideBlock = vm.envOr("ROBINHOOD_FORK_BLOCK", uint256(0));
        if (overrideBlock != 0) assertEq(overrideBlock, FORK_BLOCK, "ROBINHOOD_FORK_BLOCK drift");

        if (block.chainid == RobinhoodDeploymentConfig.ROBINHOOD_MAINNET_CHAIN_ID && block.number == FORK_BLOCK) {
            string memory pinnedBlock = vm.rpcJson("eth_getBlockByNumber", "[\"0x2b23aa7\",false]");
            assertEq(vm.parseJsonBytes32(pinnedBlock, ".hash"), FORK_BLOCK_HASH, "pinned block hash drift");
        } else {
            string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
            if (bytes(rpc).length == 0) {
                if (vm.envOr("REQUIRE_ROBINHOOD_FORK", false)) fail("Robinhood fork required");
                vm.skip(true, "ROBINHOOD_MAINNET is not configured");
            }
            uint256 forkId = vm.createSelectFork(rpc, FORK_BLOCK + 1);
            assertEq(blockhash(FORK_BLOCK), FORK_BLOCK_HASH, "pinned block hash drift");
            vm.rollFork(forkId, FORK_BLOCK);
        }
        assertEq(block.chainid, 4663);
        assertEq(block.number, FORK_BLOCK);

        dependencies = RobinhoodDeploymentConfig.load();
        RobinhoodDeploymentConfig.validate(dependencies);
        deployer = new DeployBurntato();
        verifier = new BurntatoDeploymentVerifier();
        config = deployer.localDefaults();

        alice = vm.addr(ALICE_KEY);
        bob = vm.addr(BOB_KEY);
        carol = vm.addr(CAROL_KEY);
        dave = vm.addr(DAVE_KEY);
        erin = vm.addr(ERIN_KEY);
        keeper = makeAddr("keeper");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        config.deployer = address(deployer);
        config.proposer = makeAddr("forkProposer");
        config.guardian = makeAddr("initialForkGuardian");
        config.treasuryRecipient = makeAddr("forkTreasury");
        config.rewardAllocator = config.treasuryRecipient;
        vm.deal(dave, 100 ether);
        vm.deal(erin, 100 ether);
        vm.deal(keeper, 100 ether);
    }

    function test_ManifestCodeAndBindingsMatch() public view {
        RobinhoodDeploymentConfig.validate(dependencies);
        assertEq(dependencies.chainId, 4663);
        assertEq(dependencies.forkBlock, FORK_BLOCK);
        assertEq(dependencies.forkBlockHash, FORK_BLOCK_HASH);
        IPositionManagerBindings positionManager = IPositionManagerBindings(dependencies.positionManager);
        assertEq(positionManager.poolManager(), dependencies.poolManager);
        assertEq(positionManager.permit2(), dependencies.permit2);
        assertEq(positionManager.tokenDescriptor(), dependencies.positionDescriptor);
        assertEq(positionManager.WETH9(), dependencies.weth);
        assertEq(IUniversalRouter(dependencies.universalRouter).poolManager(), dependencies.poolManager);
    }

    function test_CompleteBurntatoLifecycleOnRobinhood() public {
        _deployCanonicalBurntato();
        _assertGenesisAndGovernance();
        _completeGameRecoveryAndRewards();
        _launchAndTradeCanonicalMarket();
    }

    function _deployCanonicalBurntato() private {
        deployment = deployer.deployWithDependencies(config, address(deployer), dependencies);
        assertTrue(verifier.verifyCanonical(config, deployment, dependencies));
        buybacks = IBuyback(deployment.diamond);
        claims = IClaims(deployment.diamond);
        game = IGame(deployment.diamond);
        governance = IGovernance(deployment.diamond);
        market = IMarket(deployment.diamond);
        potato = IPotatoToken(deployment.diamond);
        recovery = IRecovery(deployment.diamond);
        settlement = ISettlement(deployment.diamond);
        rewards = ITreasuryRewards(deployment.diamond);
        hook = BurntatoSwapFeeHook(payable(deployment.hook));
        poolManager = IPoolManager(dependencies.poolManager);
        permit2 = IAllowanceTransfer(dependencies.permit2);
        quoter = IV4Quoter(dependencies.quoter);
        router = IUniversalRouter(dependencies.universalRouter);
        key = market.canonicalPoolKey();
    }

    function _assertGenesisAndGovernance() private {
        assertEq(IDiamondLoupe(deployment.diamond).facetAddresses().length, 11);
        assertEq(governance.guardian(), config.guardian);
        assertEq(governance.authority(), deployment.timelock);
        assertEq(claims.treasuryRecipient(), config.treasuryRecipient);
        assertEq(rewards.rewardAllocator(), config.rewardAllocator);
        assertEq(hook.owner(), deployment.timelock);
        assertEq(address(hook.poolManager()), dependencies.poolManager);
        assertEq(hook.token(), deployment.diamond);
        assertFalse(hook.externalBuysEnabled());
        uint160 requiredFlags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        assertEq(uint160(deployment.hook) & Hooks.ALL_HOOK_MASK, requiredFlags);

        address nextGuardian = makeAddr("forkGuardian");
        _timelockCall(deployment.diamond, abi.encodeCall(IGovernance.setGuardian, (nextGuardian)), "set guardian");
        assertEq(governance.guardian(), nextGuardian);
    }

    function _completeGameRecoveryAndRewards() private {
        _buyGame(alice, 0.01 ether);
        Round memory roundOne = game.getRound(1);
        assertEq(roundOne.deadline - roundOne.holderSince, 60 minutes);
        vm.warp(vm.getBlockTimestamp() + 120);
        _buyGame(bob, 0.011 ether);
        roundOne = game.getRound(1);
        assertEq(roundOne.deadline - roundOne.holderSince, 55 minutes);
        vm.warp(vm.getBlockTimestamp() + 60);
        _buyGame(carol, 0.0121 ether);
        roundOne = game.getRound(1);
        assertEq(roundOne.deadline - roundOne.holderSince, 50 minutes);
        vm.warp(vm.getBlockTimestamp() + 120);
        game.materializeMaturedEmission();
        assertEq(roundOne.nextPrice, 0.01331 ether);

        uint256 aliceCommitment = 3_333 ether + 1;
        uint256 bobCommitment = 2_222 ether + 2;
        vm.prank(alice);
        recovery.commitRecovery(aliceCommitment);
        vm.prank(bob);
        recovery.commitRecovery(bobCommitment);
        _settleCurrentRound();
        assertEq(game.currentRoundId(), 2);
        assertEq(game.getRound(2).recoveryCarryIn, 0.01324 ether);

        _buyGame(dave, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 60);
        _buyGame(erin, 0.011 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        _settleCurrentRound();
        Round memory roundTwo = game.getRound(2);
        assertEq(roundTwo.totalCommitted, aliceCommitment + bobCommitment);
        uint256 treasuryPotato = roundTwo.totalCommitted * 1_000 / 10_000;
        uint256 burnedPotato = roundTwo.totalCommitted - treasuryPotato;
        assertGt(burnedPotato, 0);

        vm.prank(erin);
        assertEq(claims.claimWinner(2, erin), roundTwo.winnerPool);
        uint256 claimSnapshot = vm.snapshotState();
        _assertRecoveryOrder(roundTwo, alice, aliceCommitment, bob);
        assertTrue(vm.revertToStateAndDelete(claimSnapshot));
        _assertRecoveryOrder(roundTwo, bob, bobCommitment, alice);

        uint256 treasuryBefore = potato.balanceOf(config.treasuryRecipient);
        assertEq(claims.claimTreasuryPotato(), treasuryPotato);
        assertEq(potato.balanceOf(config.treasuryRecipient) - treasuryBefore, treasuryPotato);

        vm.prank(config.rewardAllocator);
        uint256 scheduleA = rewards.allocateTreasuryRewards(400 ether + 1, 4, 2);
        vm.prank(config.rewardAllocator);
        uint256 scheduleB = rewards.allocateTreasuryRewards(33 ether + 7, 6, 3);
        vm.prank(config.rewardAllocator);
        assertEq(rewards.cancelTreasuryRewards(scheduleB), 33 ether + 7);
        RewardSchedule memory schedule = rewards.rewardSchedule(scheduleA);
        assertEq(schedule.firstRoundRemainder, 1);

        _buyGame(carol, 0.01 ether);
        _settleCurrentRound();
        assertEq(game.currentRoundId(), 4);
        Round memory roundFour = game.getRound(4);
        assertEq(roundFour.treasuryEmissionBudget, 200 ether + 1);
        uint256 supplyBefore = potato.totalSupply();
        _buyGame(alice, 0.01 ether);
        vm.warp(vm.getBlockTimestamp() + 60);
        _buyGame(bob, 0.011 ether);
        vm.warp(vm.getBlockTimestamp() + 120);
        _settleCurrentRound();
        roundFour = game.getRound(4);
        assertEq(roundFour.treasuryEmittedPotato, 29 ether);
        assertEq(roundFour.treasuryReleasedPotato, 171 ether + 1);
        assertEq(potato.totalSupply() - supplyBefore, 14_500 ether);
    }

    function _launchAndTradeCanonicalMarket() private {
        uint256 poolManagerEthBefore = dependencies.poolManager.balance;
        uint256 routerEthBefore = dependencies.universalRouter.balance;
        uint256 positionManagerEthBefore = dependencies.positionManager.balance;
        uint256 diamondEthBefore = deployment.diamond.balance;
        uint256 treasuryClaimBefore = claims.treasuryEthAvailable();
        uint256 tokenId = IPositionManagerBindings(dependencies.positionManager).nextTokenId();

        vm.prank(keeper);
        (bytes32 poolId, uint128 liquidity) = market.launchMarket();
        assertEq(poolId, PoolId.unwrap(key.toId()));
        assertEq(IPositionManagerBindings(dependencies.positionManager).getPositionLiquidity(tokenId), liquidity);
        assertEq(IPositionManagerBindings(dependencies.positionManager).ownerOf(tokenId), market.lockedLpRecipient());
        assertEq(deployment.diamond.balance, diamondEthBefore);
        assertEq(claims.treasuryEthAvailable(), treasuryClaimBefore);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        assertEq(sqrtPriceX96, market.marketConfig().sqrtPriceX96);
        (bytes32 storedPoolId,, bool launching, bool launched) = market.marketState();
        assertEq(storedPoolId, poolId);
        assertFalse(launching);
        assertTrue(launched);
        assertEq(potato.transientPoolManagerAllowance(), 0);

        uint256 closedSnapshot = vm.snapshotState();
        _expectRouterBuyDisabled(alice, 0.0001 ether);
        assertTrue(vm.revertToStateAndDelete(closedSnapshot));

        uint256 treasuryPotatoBefore = potato.balanceOf(config.treasuryRecipient);
        uint256 reserveBefore = buybacks.buybackReserveEth();
        uint256 keeperEthBefore = keeper.balance;
        vm.recordLogs();
        vm.prank(keeper);
        uint256 boughtBack = buybacks.buyback();
        Vm.Log[] memory buybackLogs = vm.getRecordedLogs();
        (uint256 grossSlice, uint256 ethSpent, uint256 loggedBought, uint256 callerReward, uint256 reserveAfter) =
            _buybackAccounting(buybackLogs);
        assertEq(boughtBack, loggedBought);
        assertEq(grossSlice, reserveBefore);
        assertEq(callerReward, ethSpent * config.buyback.callerRewardBps / 10_000);
        assertEq(keeper.balance - keeperEthBefore, callerReward);
        assertEq(potato.balanceOf(config.treasuryRecipient) - treasuryPotatoBefore, boughtBack);
        assertEq(reserveAfter, reserveBefore - ethSpent - callerReward);
        assertEq(buybacks.buybackReserveEth(), reserveAfter);
        assertFalse(hook.externalBuysEnabled());
        assertEq(_hookFeeCount(buybackLogs), 0);
        assertEq(potato.transientPoolManagerAllowance(), 0);

        uint256 sellAmount = 1 ether;
        uint256 carolPotatoBefore = potato.balanceOf(carol);
        uint256 carolEthBefore = carol.balance;
        uint256 treasuryEthBefore = config.treasuryRecipient.balance;
        (uint160 sellPriceBefore,,,) = poolManager.getSlot0(key.toId());
        vm.recordLogs();
        uint256 soldOut = _routerSell(carol, CAROL_KEY, sellAmount);
        Vm.Log[] memory sellLogs = vm.getRecordedLogs();
        assertEq(carolPotatoBefore - potato.balanceOf(carol), sellAmount);
        assertEq(carol.balance - carolEthBefore, soldOut);
        (uint256 sellNativeFee, uint256 sellPotatoFee, address sellSender) = _hookFee(sellLogs);
        assertEq(sellSender, dependencies.universalRouter);
        assertEq(sellPotatoFee, 0);
        assertEq(sellNativeFee, (soldOut + sellNativeFee) * hook.feeBps() / 10_000);
        assertEq(config.treasuryRecipient.balance - treasuryEthBefore, sellNativeFee);
        (uint160 sellPriceAfter,,,) = poolManager.getSlot0(key.toId());
        assertGt(sellPriceAfter, sellPriceBefore);
        _assertTradeSender(sellLogs);
        assertEq(potato.transientPoolManagerAllowance(), 0);

        _timelockCall(
            deployment.hook, abi.encodeCall(BurntatoSwapFeeHook.setExternalBuysEnabled, (true)), "enable external buys"
        );
        assertTrue(hook.externalBuysEnabled());

        treasuryEthBefore = config.treasuryRecipient.balance;
        vm.recordLogs();
        uint256 userBought = _routerBuy(alice, 0.0001 ether);
        Vm.Log[] memory buyLogs = vm.getRecordedLogs();
        assertGt(userBought, 0);
        (uint256 buyNativeFee, uint256 buyPotatoFee, address buySender) = _hookFee(buyLogs);
        assertEq(buySender, dependencies.universalRouter);
        assertEq(buyNativeFee, 0);
        assertEq(buyPotatoFee, (userBought + buyPotatoFee) * hook.feeBps() / 10_000);
        assertGt(config.treasuryRecipient.balance, treasuryEthBefore);
        _assertTradeSender(buyLogs);
        assertEq(potato.transientPoolManagerAllowance(), 0);

        treasuryEthBefore = config.treasuryRecipient.balance;
        uint256 secondSellAmount = userBought / 2;
        vm.recordLogs();
        uint256 secondSellOut = _routerSell(alice, ALICE_KEY, secondSellAmount);
        Vm.Log[] memory secondSellLogs = vm.getRecordedLogs();
        (uint256 secondSellFee,, address secondSellSender) = _hookFee(secondSellLogs);
        assertEq(secondSellSender, dependencies.universalRouter);
        assertEq(secondSellFee, (secondSellOut + secondSellFee) * hook.feeBps() / 10_000);
        assertGt(secondSellOut, 0);
        assertEq(config.treasuryRecipient.balance - treasuryEthBefore, secondSellFee);
        _assertTradeSender(secondSellLogs);
        assertEq(potato.transientPoolManagerAllowance(), 0);
        assertGe(dependencies.poolManager.balance, poolManagerEthBefore);
        assertEq(dependencies.universalRouter.balance, routerEthBefore);
        assertEq(dependencies.positionManager.balance, positionManagerEthBefore);
        assertEq(potato.balanceOf(deployment.hook), 0);
        assertEq(potato.balanceOf(dependencies.universalRouter), 0);
        assertEq(potato.balanceOf(dependencies.positionManager), 0);
    }

    function _assertRecoveryOrder(Round memory round, address first, uint256 firstCommitment, address last) private {
        uint256 ordinary = round.recoveryPool * firstCommitment / round.totalCommitted;
        assertEq(claims.claimableRecovery(2, first), ordinary);
        vm.prank(first);
        uint256 firstPaid = claims.claimRecovery(2, first);
        assertEq(firstPaid, ordinary);
        assertEq(claims.claimableRecovery(2, last), round.recoveryPool - firstPaid);
        vm.prank(last);
        uint256 lastPaid = claims.claimRecovery(2, last);
        assertEq(firstPaid + lastPaid, round.recoveryPool);
        assertEq(claims.claimableRecovery(2, first), 0);
        assertEq(claims.claimableRecovery(2, last), 0);
    }

    function _buyGame(address buyer, uint256 price) private {
        vm.prank(buyer);
        game.buyPotato{value: price}();
    }

    function _settleCurrentRound() private {
        Round memory round = game.getRound(game.currentRoundId());
        vm.warp(round.deadline);
        vm.prank(keeper);
        settlement.settleRound();
    }

    function _timelockCall(address target, bytes memory data, string memory saltLabel) private {
        TimelockController timelock = TimelockController(payable(deployment.timelock));
        bytes32 salt = keccak256(bytes(saltLabel));
        vm.prank(config.proposer);
        timelock.schedule(target, 0, data, bytes32(0), salt, config.timelockDelay);
        vm.warp(vm.getBlockTimestamp() + config.timelockDelay);
        timelock.execute(target, 0, data, bytes32(0), salt);
    }

    function _quote(bool zeroForOne, uint128 amountIn) private returns (uint128 minimumOut) {
        (uint256 quoted,) = quoter.quoteExactInputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: key, zeroForOne: zeroForOne, exactAmount: amountIn, hookData: ""
            })
        );
        assertGt(quoted, 0);
        minimumOut = uint128(quoted * 99 / 100);
        assertGt(minimumOut, 0);
    }

    function _routerBuy(address buyer, uint128 amountIn) private returns (uint256 amountOut) {
        uint128 minimumOut = _quote(true, amountIn);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = _swapPlan(true, amountIn, minimumOut);
        uint256 beforeBalance = potato.balanceOf(buyer);
        vm.prank(buyer);
        router.execute{value: amountIn}(abi.encodePacked(V4_SWAP), inputs, block.timestamp + 1 minutes);
        amountOut = potato.balanceOf(buyer) - beforeBalance;
        assertGe(amountOut, minimumOut);
    }

    function test_Permit2PermitFrontRunDoesNotBlockRouterSell() public {
        _deployCanonicalBurntato();
        _completeGameRecoveryAndRewards();
        market.launchMarket();
        vm.prank(keeper);
        buybacks.buyback();

        uint256 amountIn = 1 ether;
        vm.prank(carol);
        potato.approve(dependencies.permit2, type(uint256).max);
        (,, uint48 nonce) = permit2.allowance(carol, deployment.diamond, dependencies.universalRouter);
        IAllowanceTransfer.PermitSingle memory permitSingle = _permitSingle(amountIn, nonce);
        bytes memory signature = getPermitSignature(permitSingle, CAROL_KEY, permit2.DOMAIN_SEPARATOR());
        permit2.permit(carol, permitSingle, signature);

        uint128 minimumOut = _quote(false, uint128(amountIn));
        assertGt(_executeRouterSell(carol, permitSingle, signature, uint128(amountIn), minimumOut), 0);
    }

    function _permitSingle(uint256 amountIn, uint48 nonce)
        private
        view
        returns (IAllowanceTransfer.PermitSingle memory permitSingle)
    {
        permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: deployment.diamond,
                amount: uint160(amountIn),
                expiration: uint48(block.timestamp + 20 minutes),
                nonce: nonce
            }),
            spender: dependencies.universalRouter,
            sigDeadline: block.timestamp + 20 minutes
        });
    }

    function _expectRouterBuyDisabled(address buyer, uint128 amountIn) private {
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = _swapPlan(true, amountIn, 1);
        vm.prank(buyer);
        vm.expectRevert();
        router.execute{value: amountIn}(abi.encodePacked(V4_SWAP), inputs, block.timestamp + 1 days);
    }

    function _routerSell(address seller, uint256 sellerKey, uint256 amountIn) private returns (uint256 amountOut) {
        uint128 exactAmount = uint128(amountIn);
        uint128 minimumOut = _quote(false, exactAmount);
        vm.prank(seller);
        potato.approve(dependencies.permit2, type(uint256).max);
        (,, uint48 nonce) = permit2.allowance(seller, deployment.diamond, dependencies.universalRouter);
        IAllowanceTransfer.PermitSingle memory permitSingle = _permitSingle(amountIn, nonce);
        bytes memory signature = getPermitSignature(permitSingle, sellerKey, permit2.DOMAIN_SEPARATOR());
        amountOut = _executeRouterSell(seller, permitSingle, signature, exactAmount, minimumOut);
    }

    function _executeRouterSell(
        address seller,
        IAllowanceTransfer.PermitSingle memory permitSingle,
        bytes memory signature,
        uint128 exactAmount,
        uint128 minimumOut
    ) private returns (uint256 amountOut) {
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(permitSingle, signature);
        inputs[1] = _swapPlan(false, exactAmount, minimumOut);
        uint256 beforeBalance = seller.balance;
        vm.prank(seller);
        router.execute(abi.encodePacked(PERMIT2_PERMIT_ALLOW_REVERT, V4_SWAP), inputs, block.timestamp + 1 days);
        amountOut = seller.balance - beforeBalance;
        assertGe(amountOut, minimumOut);
        (uint160 remaining,, uint48 nextNonce) =
            permit2.allowance(seller, deployment.diamond, dependencies.universalRouter);
        assertEq(remaining, 0);
        assertGe(nextNonce, permitSingle.details.nonce + 1);
    }

    function _swapPlan(bool zeroForOne, uint128 amountIn, uint128 minimumOut) private view returns (bytes memory) {
        Plan memory plan = Planner.init();
        plan.add(
            Actions.SWAP_EXACT_IN_SINGLE,
            abi.encode(
                RouterExactInputSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    amountIn: amountIn,
                    amountOutMinimum: minimumOut,
                    minHopPriceX36: 0,
                    hookData: ""
                })
            )
        );
        Currency input = zeroForOne ? key.currency0 : key.currency1;
        Currency output = zeroForOne ? key.currency1 : key.currency0;
        plan.add(Actions.SETTLE_ALL, abi.encode(input, amountIn));
        plan.add(Actions.TAKE_ALL, abi.encode(output, minimumOut));
        return plan.encode();
    }

    function _hookFee(Vm.Log[] memory logs) private returns (uint256 nativeFee, uint256 potatoFee, address sender) {
        bytes32 topic = keccak256("HookFee(bytes32,address,uint128,uint128)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 3) continue;
            address indexedSender = address(uint160(uint256(logs[i].topics[2])));
            if (
                logs[i].emitter == deployment.hook && logs[i].topics[0] == topic
                    && indexedSender == dependencies.universalRouter
            ) {
                sender = indexedSender;
                (nativeFee, potatoFee) = abi.decode(logs[i].data, (uint128, uint128));
                return (nativeFee, potatoFee, sender);
            }
        }
        fail("HookFee not emitted");
    }

    function _buybackAccounting(Vm.Log[] memory logs)
        private
        returns (uint256 gross, uint256 spent, uint256 bought, uint256 reward, uint256 reserve)
    {
        bytes32 topic = keccak256("BuybackExecuted(address,address,uint256,uint256,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == deployment.diamond && logs[i].topics[0] == topic) {
                return abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256));
            }
        }
        fail("BuybackExecuted not emitted");
    }

    function _assertTradeSender(Vm.Log[] memory logs) private {
        bytes32 topic = keccak256("Trade(bytes32,address,int128,int128)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != deployment.hook || logs[i].topics.length != 3 || logs[i].topics[0] != topic) {
                continue;
            }
            address sender = address(uint160(uint256(logs[i].topics[2])));
            if (sender == dependencies.universalRouter) return;
        }
        fail("Trade not emitted");
    }

    function _hookFeeCount(Vm.Log[] memory logs) private view returns (uint256 count) {
        bytes32 topic = keccak256("HookFee(bytes32,address,uint128,uint128)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == deployment.hook && logs[i].topics[0] == topic) ++count;
        }
    }
}
