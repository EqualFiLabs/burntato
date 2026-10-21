// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Script, console2} from "forge-std/Script.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";

contract InitializeBurntato is Script {
    error RewardReserveNotFunded(uint256 required, uint256 available);
    error UnexpectedAuthority(address expected, address actual);

    function checkReady(address diamond) public view {
        require(diamond.code.length != 0, "Diamond code required");
        IGovernance g = IGovernance(diamond);
        require(g.foundationConfigured() && !g.paused() && !g.purchasesInitialized(), "invalid activation state");
        (, uint256 required, uint256 available, bool funded) = IPotatoToken(diamond).nextRoundFundingStatus();
        if (!funded) revert RewardReserveNotFunded(required, available);
        require(IPotatoToken(diamond).backingBalance() >= IPotatoToken(diamond).totalSupply(), "insufficient backing");
    }

    function initializationCall(address diamond) external view returns (address target, bytes memory data) {
        checkReady(diamond);
        return (diamond, abi.encodeCall(IGovernance.initializePurchases, ()));
    }

    function run() public virtual returns (bool initialized) {
        address diamond = vm.envAddress("BURNTATO_DIAMOND");
        checkReady(diamond);
        uint256 key = vm.envUint("PRIVATE_KEY");
        address expected = IGovernance(diamond).authority();
        if (key == 0 || vm.addr(key) != expected) revert UnexpectedAuthority(expected, vm.addr(key));
        vm.startBroadcast(key);
        IGovernance(diamond).initializePurchases();
        vm.stopBroadcast();
        initialized = IGovernance(diamond).purchasesInitialized();
        console2.log("Burntato purchases initialized", initialized);
    }
}
