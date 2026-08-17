// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {GenesisConfig} from "../DeploymentTypes.sol";

library BurntatoDeploymentConfig {
    error NarrowingOverflow();
    address internal constant ANVIL_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant ANVIL_PROPOSER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address internal constant ANVIL_GUARDIAN = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address internal constant ANVIL_TREASURY = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    int24 internal constant DEFAULT_TICK_SPACING = 60;
    int24 internal constant DEFAULT_INITIAL_TICK = 92_100;

    function localDefaults() internal pure returns (GenesisConfig memory config) {
        config = GenesisConfig({
            deployer: ANVIL_DEPLOYER,
            proposer: ANVIL_PROPOSER,
            guardian: ANVIL_GUARDIAN,
            treasuryRecipient: ANVIL_TREASURY,
            timelockDelay: 1 days,
            startingPrice: 0.01 ether,
            priceIncreaseBps: 1_000,
            initialTick: DEFAULT_INITIAL_TICK,
            tickSpacing: DEFAULT_TICK_SPACING,
            tickLower: TickMath.minUsableTick(DEFAULT_TICK_SPACING),
            tickUpper: TickMath.maxUsableTick(DEFAULT_TICK_SPACING),
            nativeSeed: 0.1 ether,
            potatoSeed: 1_000 ether
        });
    }

    function checkedUint16(uint256 value) internal pure returns (uint16 narrowed) {
        if (value > type(uint16).max) revert NarrowingOverflow();
        narrowed = uint16(value);
    }

    function checkedInt24(int256 value) internal pure returns (int24 narrowed) {
        if (value < type(int24).min || value > type(int24).max) revert NarrowingOverflow();
        narrowed = int24(value);
    }
}
