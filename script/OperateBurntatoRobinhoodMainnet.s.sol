// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {BurntatoSwapFeeHook} from "../src/hooks/BurntatoSwapFeeHook.sol";
import {IBuyback} from "../src/interfaces/IBuyback.sol";
import {IGovernance} from "../src/interfaces/IGovernance.sol";
import {IMarket} from "../src/interfaces/IMarket.sol";
import {IPotatoToken} from "../src/interfaces/IPotatoToken.sol";

contract OperateBurntatoRobinhoodMainnet is Script {
    uint256 private constant CHAIN_ID = 4_663;
    uint256 private constant DEFAULT_MAX_BOOTSTRAP_REMAINDER_WEI = 100;
    uint256 private constant MIN_BOOTSTRAP_POTATO = 10_200_000 ether;
    uint256 private constant MAX_BOOTSTRAP_POTATO = 10_400_000 ether;
    string private constant OUTPUT_PATH = "artifacts/robinhood-mainnet/deployment.json";

    error InvalidMainnetChain(uint256 actualChainId);
    error InvalidPrivateKey();
    error InvalidDeploymentAddress(address account);
    error UnexpectedAuthority(address expected, address actual);
    error UnexpectedGuardian(address expected, address actual);
    error UnexpectedHookOwner(address expected, address actual);
    error FoundationNotConfigured();
    error ProtocolPaused();
    error PurchasesAlreadyInitialized();
    error PurchasesNotInitialized();
    error MarketNotReady();
    error MarketNotLaunched();
    error ExternalBuysAlreadyEnabled();
    error ExternalBuysNotEnabled();
    error BuybackBootstrapIncomplete();
    error BuybackReserveTooLarge(uint256 maximum, uint256 actual);
    error UnexpectedBootstrapPotato(uint256 minimum, uint256 maximum, uint256 actual);
    error UnexpectedSigner(address expected, address actual);

    function launchMarket() external returns (bytes32 poolId, uint256 positionCount, uint256 potatoUsed) {
        _requireChain();
        (address diamond, address hook, address admin, address guardian,) = _deployment();
        checkDeployedDeployment(diamond, hook, admin, guardian);

        uint256 privateKey = _privateKey();
        vm.startBroadcast(privateKey);
        (poolId, positionCount, potatoUsed) = IMarket(diamond).launchMarket();
        vm.stopBroadcast();

        console2.logBytes32(poolId);
        console2.log("Locked market positions", positionCount);
        console2.log("POTATO used", potatoUsed);
    }

    function initializePurchases() external {
        _requireChain();
        (address diamond, address hook, address admin, address guardian, address treasury) = _deployment();
        checkReadyForInitializationDeployment(diamond, hook, admin, guardian, treasury, _maximumBootstrapRemainder());

        uint256 privateKey = _privateKey();
        _requireSigner(privateKey, admin);
        vm.startBroadcast(privateKey);
        IGovernance(diamond).initializePurchases();
        vm.stopBroadcast();
    }

    function enableExternalBuys() external {
        _requireChain();
        (address diamond, address hook, address admin, address guardian, address treasury) = _deployment();
        checkReadyForExternalBuysDeployment(diamond, hook, admin, guardian, treasury, _maximumBootstrapRemainder());

        uint256 privateKey = _privateKey();
        _requireSigner(privateKey, admin);
        vm.startBroadcast(privateKey);
        BurntatoSwapFeeHook(payable(hook)).setExternalBuysEnabled(true);
        vm.stopBroadcast();
    }

    function checkDeployed() external view returns (bool) {
        _requireChain();
        (address diamond, address hook, address admin, address guardian,) = _deployment();
        return checkDeployedDeployment(diamond, hook, admin, guardian);
    }

    function checkReadyForInitialization() external view returns (bool) {
        _requireChain();
        (address diamond, address hook, address admin, address guardian, address treasury) = _deployment();
        return
            checkReadyForInitializationDeployment(
                diamond, hook, admin, guardian, treasury, _maximumBootstrapRemainder()
            );
    }

    function checkReadyForExternalBuys() external view returns (bool) {
        _requireChain();
        (address diamond, address hook, address admin, address guardian, address treasury) = _deployment();
        return
            checkReadyForExternalBuysDeployment(diamond, hook, admin, guardian, treasury, _maximumBootstrapRemainder());
    }

    function checkFinalized() external view returns (bool) {
        _requireChain();
        (address diamond, address hook, address admin, address guardian, address treasury) = _deployment();
        return checkFinalizedDeployment(diamond, hook, admin, guardian, treasury, _maximumBootstrapRemainder());
    }

    function checkDeployedDeployment(address diamond, address hook, address admin, address guardian)
        public
        view
        returns (bool)
    {
        _checkDeploymentAddresses(diamond, hook, admin);
        IGovernance governance = IGovernance(diamond);
        if (!governance.foundationConfigured()) revert FoundationNotConfigured();
        if (governance.authority() != admin) revert UnexpectedAuthority(admin, governance.authority());
        if (governance.guardian() != guardian) revert UnexpectedGuardian(guardian, governance.guardian());
        if (governance.paused()) revert ProtocolPaused();
        if (governance.purchasesInitialized()) revert PurchasesAlreadyInitialized();
        if (BurntatoSwapFeeHook(payable(hook)).owner() != admin) {
            revert UnexpectedHookOwner(admin, BurntatoSwapFeeHook(payable(hook)).owner());
        }
        if (BurntatoSwapFeeHook(payable(hook)).externalBuysEnabled()) revert ExternalBuysAlreadyEnabled();

        (,, bool launching, bool launched) = IMarket(diamond).marketState();
        if (launching || launched || !IMarket(diamond).marketReady()) revert MarketNotReady();
        return true;
    }

    function checkReadyForInitializationDeployment(
        address diamond,
        address hook,
        address admin,
        address guardian,
        address treasury,
        uint256 maximumBootstrapRemainder
    ) public view returns (bool) {
        _checkSharedLaunchState(diamond, hook, admin, guardian, treasury, false, false, maximumBootstrapRemainder);
        return true;
    }

    function checkReadyForExternalBuysDeployment(
        address diamond,
        address hook,
        address admin,
        address guardian,
        address treasury,
        uint256 maximumBootstrapRemainder
    ) public view returns (bool) {
        _checkSharedLaunchState(diamond, hook, admin, guardian, treasury, true, false, maximumBootstrapRemainder);
        return true;
    }

    function checkFinalizedDeployment(
        address diamond,
        address hook,
        address admin,
        address guardian,
        address treasury,
        uint256 maximumBootstrapRemainder
    ) public view returns (bool) {
        _checkSharedLaunchState(diamond, hook, admin, guardian, treasury, true, true, maximumBootstrapRemainder);
        return true;
    }

    function _checkSharedLaunchState(
        address diamond,
        address hook,
        address admin,
        address guardian,
        address treasury,
        bool expectedInitialized,
        bool expectedExternalBuys,
        uint256 maximumBootstrapRemainder
    ) private view {
        _checkDeploymentAddresses(diamond, hook, admin);
        IGovernance governance = IGovernance(diamond);
        if (!governance.foundationConfigured()) revert FoundationNotConfigured();
        if (governance.authority() != admin) revert UnexpectedAuthority(admin, governance.authority());
        if (governance.guardian() != guardian) revert UnexpectedGuardian(guardian, governance.guardian());
        if (governance.paused()) revert ProtocolPaused();
        if (governance.purchasesInitialized() != expectedInitialized) {
            if (expectedInitialized) revert PurchasesNotInitialized();
            revert PurchasesAlreadyInitialized();
        }

        BurntatoSwapFeeHook marketHook = BurntatoSwapFeeHook(payable(hook));
        if (marketHook.owner() != admin) revert UnexpectedHookOwner(admin, marketHook.owner());
        if (marketHook.externalBuysEnabled() != expectedExternalBuys) {
            if (expectedExternalBuys) revert ExternalBuysNotEnabled();
            revert ExternalBuysAlreadyEnabled();
        }

        (,, bool launching, bool launched) = IMarket(diamond).marketState();
        if (launching || !launched) revert MarketNotLaunched();

        IBuyback buybacks = IBuyback(diamond);
        if (buybacks.lastBuybackBlock() == 0) revert BuybackBootstrapIncomplete();
        uint256 reserve = buybacks.buybackReserveEth();
        if (reserve > maximumBootstrapRemainder) {
            revert BuybackReserveTooLarge(maximumBootstrapRemainder, reserve);
        }
        uint256 treasuryPotato = IPotatoToken(diamond).balanceOf(treasury);
        if (treasuryPotato < MIN_BOOTSTRAP_POTATO || treasuryPotato > MAX_BOOTSTRAP_POTATO) {
            revert UnexpectedBootstrapPotato(MIN_BOOTSTRAP_POTATO, MAX_BOOTSTRAP_POTATO, treasuryPotato);
        }
    }

    function _deployment()
        private
        view
        returns (address diamond, address hook, address admin, address guardian, address treasury)
    {
        string memory deployment = vm.readFile(OUTPUT_PATH);
        diamond = vm.parseJsonAddress(deployment, ".diamond");
        hook = vm.parseJsonAddress(deployment, ".hook");
        admin = vm.parseJsonAddress(deployment, ".admin");
        guardian = vm.parseJsonAddress(deployment, ".guardian");
        treasury = vm.parseJsonAddress(deployment, ".treasuryRecipient");
    }

    function _maximumBootstrapRemainder() private pure returns (uint256) {
        return DEFAULT_MAX_BOOTSTRAP_REMAINDER_WEI;
    }

    function _privateKey() private view returns (uint256 privateKey) {
        privateKey = vm.envUint("PRIVATE_KEY");
        if (privateKey == 0) revert InvalidPrivateKey();
    }

    function _requireSigner(uint256 privateKey, address expected) private pure {
        address actual = vm.addr(privateKey);
        if (actual != expected) revert UnexpectedSigner(expected, actual);
    }

    function _checkDeploymentAddresses(address diamond, address hook, address admin) private view {
        if (diamond == address(0) || diamond.code.length == 0) revert InvalidDeploymentAddress(diamond);
        if (hook == address(0) || hook.code.length == 0) revert InvalidDeploymentAddress(hook);
        if (admin == address(0)) revert InvalidDeploymentAddress(admin);
    }

    function _requireChain() private view {
        if (block.chainid != CHAIN_ID) revert InvalidMainnetChain(block.chainid);
    }
}
