// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {IMarket} from "../../src/interfaces/IMarket.sol";
import {BurntatoLaunchCurves} from "../../src/libraries/BurntatoLaunchCurves.sol";
import {Errors} from "../../src/shared/Errors.sol";

contract BurntatoLaunchCurvesTest is Test {
    uint256 internal constant POTATO_SEED = 100_000_000 ether;

    function test_ProfilePinsAggressiveBandsAndAllocation() public pure {
        IMarket.MarketCurve[] memory curves = BurntatoLaunchCurves.profile();
        assertEq(curves.length, 6);

        int24[6] memory expectedLower = [int24(-170_280), -160_980, -145_080, -126_600, -100_020, -65_580];
        int24[6] memory expectedUpper = [int24(-153_000), -137_040, -118_500, -92_100, -65_580, 887_220];
        uint16[6] memory expectedPositions = [uint16(11), 11, 11, 11, 11, 1];
        uint16[6] memory expectedShares = [uint16(250), 750, 1_250, 2_000, 4_250, 1_500];

        uint256 totalPositions;
        uint256 totalShares;
        for (uint256 index; index < curves.length; ++index) {
            assertEq(curves[index].canonicalTickLower, expectedLower[index]);
            assertEq(curves[index].canonicalTickUpper, expectedUpper[index]);
            assertEq(curves[index].positions, expectedPositions[index]);
            assertEq(curves[index].shareBps, expectedShares[index]);
            totalPositions += curves[index].positions;
            totalShares += curves[index].shareBps;
        }

        assertEq(totalPositions, 56);
        assertEq(totalShares, 10_000);
        assertEq(BurntatoLaunchCurves.profileHash(), keccak256(abi.encode(curves)));
    }

    function test_PositionsAreNestedAlignedAndConserveSeed() public pure {
        BurntatoLaunchCurves.LaunchPosition[] memory positions = BurntatoLaunchCurves.buildPositions(POTATO_SEED);
        assertEq(positions.length, 56);

        int24[6] memory expectedFar = [int24(153_000), 137_040, 118_500, 92_100, 65_580, -887_220];
        int24[6] memory expectedClose = [int24(170_280), 160_980, 145_080, 126_600, 100_020, 65_580];
        uint256[6] memory offsets = [uint256(0), 11, 22, 33, 44, 55];
        uint256[6] memory counts = [uint256(11), 11, 11, 11, 11, 1];

        uint256 totalPotato;
        for (uint256 band; band < offsets.length; ++band) {
            uint256 offset = offsets[band];
            assertEq(positions[offset].tickLower, expectedFar[band]);
            assertEq(positions[offset].tickUpper, expectedClose[band]);

            int24 priorUpper = positions[offset].tickUpper;
            for (uint256 index; index < counts[band]; ++index) {
                BurntatoLaunchCurves.LaunchPosition memory position = positions[offset + index];
                assertEq(position.tickLower, expectedFar[band]);
                assertEq(position.tickLower % BurntatoLaunchCurves.tickSpacing(), 0);
                assertEq(position.tickUpper % BurntatoLaunchCurves.tickSpacing(), 0);
                assertGt(position.tickUpper, position.tickLower);
                assertLe(position.tickUpper, priorUpper);
                assertGt(position.liquidity, 0);
                assertGt(position.potatoAmountMax, 0);
                totalPotato += position.potatoAmountMax;
                priorUpper = position.tickUpper;
            }
        }

        assertEq(totalPotato, POTATO_SEED);
    }

    function test_RejectsSeedTooSmallForEveryPosition() public {
        vm.expectRevert(Errors.InvalidMarketConfiguration.selector);
        this.buildPositionCount(1);
    }

    function buildPositionCount(uint256 potatoSeed) external pure returns (uint256) {
        return BurntatoLaunchCurves.buildPositions(potatoSeed).length;
    }
}
