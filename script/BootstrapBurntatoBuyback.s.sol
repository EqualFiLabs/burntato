// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {BuybackConfig} from "../src/shared/Types.sol";

contract BootstrapBurntatoBuyback is Script {
    error InvalidDiamond(address diamond);
    error InvalidPrivateKey();
    error MarketNotLaunched();
    error PurchasesAlreadyInitialized();
    error BuybackAlreadyExecuted(uint256 lastBuybackBlock);
    error InvalidBootstrapAmount(uint256 amount, uint256 maxSpend);
    error UnexpectedBuybackReserve(uint256 expected, uint256 actual);

    function run() external returns (uint256 funded, uint256 potatoBought, uint256 reserveAfter) {
        address diamond = vm.envAddress("BURNTATO_DIAMOND");
        uint256 amount = vm.envUint("BURNTATO_BOOTSTRAP_BUYBACK_WEI");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        if (privateKey == 0) revert InvalidPrivateKey();

        bool fundingRequired = checkBootstrapState(diamond, amount);
        IBuyback buybacks = IBuyback(diamond);

        if (fundingRequired) {
            vm.startBroadcast(privateKey);
            buybacks.fundBuybackReserve{value: amount}();
            vm.stopBroadcast();
            funded = amount;

            uint256 fundedReserve = buybacks.buybackReserveEth();
            if (fundedReserve != amount) revert UnexpectedBuybackReserve(amount, fundedReserve);
        }

        vm.startBroadcast(privateKey);
        potatoBought = buybacks.buyback();
        vm.stopBroadcast();

        reserveAfter = buybacks.buybackReserveEth();
        console2.log("Initial buyback reserve funding", funded);
        console2.log("Initial buyback POTATO output", potatoBought);
        console2.log("Buyback reserve after execution", reserveAfter);
    }

    function checkBootstrapState(address diamond, uint256 amount) public view returns (bool fundingRequired) {
        if (diamond == address(0) || diamond.code.length == 0) revert InvalidDiamond(diamond);

        (,, bool launching, bool launched) = IMarket(diamond).marketState();
        if (launching || !launched) revert MarketNotLaunched();
        if (IGovernance(diamond).purchasesInitialized()) revert PurchasesAlreadyInitialized();

        IBuyback buybacks = IBuyback(diamond);
        uint256 lastExecutionBlock = buybacks.lastBuybackBlock();
        if (lastExecutionBlock != 0) revert BuybackAlreadyExecuted(lastExecutionBlock);

        BuybackConfig memory config = buybacks.buybackConfig();
        if (amount == 0 || amount > config.maxSpend) revert InvalidBootstrapAmount(amount, config.maxSpend);

        uint256 reserve = buybacks.buybackReserveEth();
        if (reserve == 0) return true;
        if (reserve == amount) return false;
        revert UnexpectedBuybackReserve(amount, reserve);
    }
}
