// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {DiamondTestSetup} from "../utils/DiamondTestSetup.sol";

import {IGame} from "../../src/interfaces/IGame.sol";
import {IBuyback} from "../../src/interfaces/IBuyback.sol";
import {IClaims} from "../../src/interfaces/IClaims.sol";
import {IGovernance} from "../../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {LibMath} from "../../src/libraries/LibMath.sol";
import {ProtocolConfig, Round} from "../../src/shared/Types.sol";

contract EconomicFuzzTest is DiamondTestSetup {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    IGame internal game;
    IGovernance internal governance;
    IPotatoToken internal potato;

    function setUp() public {
        _deployCore();
        game = IGame(address(diamond));
        governance = IGovernance(address(diamond));
        potato = IPotatoToken(address(diamond));
    }

    function testFuzz_PriceIsExactAndStrictlyIncreasing(uint128 rawStart, uint16 rawBps, uint8 rawDepth) public {
        uint256 start = bound(uint256(rawStart), 1, 1_000 ether);
        uint16 increaseBps = uint16(bound(uint256(rawBps), 1, 10_000));
        uint256 depth = bound(uint256(rawDepth), 1, 24);
        vm.prank(authority);
        governance.setProtocolConfig(_configWithPrice(start, increaseBps));

        uint256 expected = start;
        for (uint256 i; i < depth; ++i) {
            address buyer = address(uint160(1_000 + i));
            vm.deal(buyer, expected);
            vm.prank(buyer);
            game.buyPotato{value: expected}();
            Round memory round = game.getRound(1);
            uint256 next = expected + LibMath.mulBpsUp(expected, increaseBps);
            assertEq(round.nextPrice, next);
            assertGt(next, expected);
            expected = next;
        }
    }

    function testFuzz_HolderDurationControlsOnlyEarnedEmission(uint16 rawDuration) public {
        uint256 duration = bound(uint256(rawDuration), 0, 600);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.prank(alice);
        game.buyPotato{value: 0.01 ether}();
        vm.warp(vm.getBlockTimestamp() + duration);
        vm.prank(bob);
        game.buyPotato{value: 0.011 ether}();

        uint256 capped = duration > 120 ? 120 : duration;
        uint256 expected = 10_000 ether * capped / 120;
        Round memory round = game.getRound(1);
        assertEq(potato.balanceOf(alice), expected);
        assertEq(round.emittedPotato, expected);
        assertEq(round.remainingEmission, 100_000 ether - expected);
        assertEq(round.holderMaxReward, (100_000 ether - expected) * 1_000 / 10_000);
    }

    function testFuzz_LinearAccrualUsesMultiplicationBeforeDivision(uint128 rawMaximum, uint16 rawDuration)
        public
        pure
    {
        uint256 maximum = uint256(rawMaximum);
        uint256 duration = uint256(rawDuration);
        uint256 capped = duration > 120 ? 120 : duration;
        assertEq(LibMath.linearEarned(maximum, duration, 120), maximum * capped / 120);
    }

    function testFuzz_RecoverySplitBurnsExactRemainder(uint128 rawAmount) public pure {
        uint256 amount = uint256(rawAmount);
        (uint256 burned, uint256 treasuryPotato) = LibMath.splitRecovery(amount, 1_000);
        assertEq(treasuryPotato, amount * 1_000 / 10_000);
        assertEq(burned + treasuryPotato, amount);
    }

    function testFuzz_FourWayPurchaseSplitConservesEveryWei(uint128 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 1, 1_000 ether);
        ProtocolConfig memory config = _defaultConfig();
        config.startingPrice = amount;
        config.priceIncreaseBps = 0;
        vm.prank(authority);
        governance.setProtocolConfig(config);

        vm.deal(alice, amount);
        vm.prank(alice);
        game.buyPotato{value: amount}();

        Round memory round = game.getRound(1);
        uint256 treasuryShare = IClaims(address(diamond)).treasuryEthAvailable();
        uint256 buybackShare = IBuyback(address(diamond)).buybackReserveEth();
        assertEq(round.winnerPool, amount * 2_500 / 10_000);
        assertEq(round.recoveryPool, amount * 4_000 / 10_000);
        assertEq(buybackShare, amount * 1_000 / 10_000);
        assertEq(round.winnerPool + round.recoveryPool + treasuryShare + buybackShare, amount);
    }
}
