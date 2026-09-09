// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {LibMath} from "../../src/libraries/LibMath.sol";

/// @notice Branch and bound properties that Halmos resolves without approximation.
/// @dev Full arithmetic conservation properties live in the Certora suite.
contract BurntatoMathProperties is Test {
    function check_diminishingTimeoutStaysInConfiguredBounds(
        uint64 initialTimeout,
        uint64 decay,
        uint64 minimumTimeout,
        uint64 priorPurchases
    ) public pure {
        vm.assume(initialTimeout != 0);
        vm.assume(minimumTimeout != 0 && minimumTimeout <= initialTimeout);
        vm.assume(decay <= initialTimeout);

        uint256 duration = LibMath.diminishingTimeout(initialTimeout, decay, minimumTimeout, priorPurchases);
        assertGe(duration, minimumTimeout);
        assertLe(duration, initialTimeout);
    }

    function check_zeroDecayKeepsInitialTimeout(
        uint64 initialTimeout,
        uint64 minimumTimeout,
        uint64 priorPurchases
    ) public pure {
        vm.assume(initialTimeout != 0);
        vm.assume(minimumTimeout != 0 && minimumTimeout <= initialTimeout);
        assertEq(LibMath.diminishingTimeout(initialTimeout, 0, minimumTimeout, priorPurchases), initialTimeout);
    }

    function check_zeroPriorPurchasesKeepsInitialTimeout(
        uint64 initialTimeout,
        uint64 decay,
        uint64 minimumTimeout
    ) public pure {
        vm.assume(initialTimeout != 0);
        vm.assume(minimumTimeout != 0 && minimumTimeout <= initialTimeout);
        vm.assume(decay <= initialTimeout);
        assertEq(LibMath.diminishingTimeout(initialTimeout, decay, minimumTimeout, 0), initialTimeout);
    }

    function check_equalTimeoutBoundsStayFixed(uint64 initialTimeout, uint64 decay, uint64 priorPurchases)
        public
        pure
    {
        vm.assume(initialTimeout != 0);
        vm.assume(decay <= initialTimeout);
        assertEq(
            LibMath.diminishingTimeout(initialTimeout, decay, initialTimeout, priorPurchases), initialTimeout
        );
    }
}
