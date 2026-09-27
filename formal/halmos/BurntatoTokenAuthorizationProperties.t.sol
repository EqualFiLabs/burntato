// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {LibProtocolStorage} from "../../src/libraries/LibProtocolStorage.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {Errors} from "../../src/shared/Errors.sol";

contract SymbolicPotatoHarness is PotatoTokenFacet {
    function formalConfigureMarket(address hook, address manager) external {
        LibProtocolStorage.TokenStorage storage tokenStorage = LibProtocolStorage.token();
        tokenStorage.canonicalHook = hook;
        tokenStorage.poolManager = manager;
    }

    function formalProtocolMovement() external view returns (bytes32 movement) {
        bytes32 slot = LibProtocolStorage.PROTOCOL_MOVEMENT_SLOT;
        assembly ("memory-safe") {
            movement := tload(slot)
        }
    }
}

contract BurntatoTokenAuthorizationProperties is Test {
    address private constant HOOK = address(0xA11CE);
    address private constant MANAGER = address(0xB0B);
    address private constant HOLDER = address(0xCAFE);
    address private constant RECIPIENT = address(0xD00D);

    SymbolicPotatoHarness private harness;
    IPotatoToken private token;

    function setUp() public {
        harness = new SymbolicPotatoHarness();
        token = IPotatoToken(address(harness));
        harness.formalConfigureMarket(HOOK, MANAGER);
    }

    function check_onlyCanonicalHookCanAuthorize(address caller, uint96 amount) public {
        vm.assume(caller != address(0) && caller != HOOK);
        uint256 beforeAllowance = token.transientPoolManagerAllowance();

        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(
            abi.encodeCall(IPotatoToken.authorizePoolManagerTransfer, (uint256(amount)))
        );

        assertFalse(success);
        assertEq(_selector(reason), Errors.NotCanonicalHook.selector);
        assertEq(token.transientPoolManagerAllowance(), beforeAllowance);
    }

    function check_poolManagerAllowanceIsConsumedExactly(uint96 amount) public {
        vm.assume(amount > 0);
        _protocolMint(HOLDER, amount);

        vm.prank(HOOK);
        token.authorizePoolManagerTransfer(amount);
        assertEq(token.transientPoolManagerAllowance(), amount);

        vm.prank(HOLDER);
        assertTrue(token.transfer(MANAGER, amount));

        assertEq(token.transientPoolManagerAllowance(), 0);
        assertEq(token.balanceOf(HOLDER), 0);
        assertEq(token.balanceOf(MANAGER), amount);
    }

    function check_poolManagerOverspendRollsBack(uint96 allowance_, uint96 excess) public {
        vm.assume(excess > 0);
        uint256 allowanceAmount = allowance_;
        uint256 required = allowanceAmount + uint256(excess);
        vm.assume(required <= type(uint96).max);
        _protocolMint(HOLDER, required);

        vm.prank(HOOK);
        token.authorizePoolManagerTransfer(allowanceAmount);
        uint256 holderBefore = token.balanceOf(HOLDER);
        uint256 managerBefore = token.balanceOf(MANAGER);

        vm.prank(HOLDER);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(IPotatoToken.transfer, (MANAGER, required)));

        assertFalse(success);
        assertEq(_selector(reason), Errors.PoolManagerAllowanceExceeded.selector);
        assertEq(token.transientPoolManagerAllowance(), allowanceAmount);
        assertEq(token.balanceOf(HOLDER), holderBefore);
        assertEq(token.balanceOf(MANAGER), managerBefore);
    }

    function check_consumedAllowanceCannotBeReused(uint96 amount) public {
        vm.assume(amount > 0 && amount <= type(uint96).max / 2);
        _protocolMint(HOLDER, uint256(amount) * 2);

        vm.prank(HOOK);
        token.authorizePoolManagerTransfer(amount);
        vm.prank(HOLDER);
        token.transfer(MANAGER, amount);

        vm.prank(HOLDER);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(IPotatoToken.transfer, (MANAGER, uint256(amount))));

        assertFalse(success);
        assertEq(_selector(reason), Errors.PoolManagerAllowanceExceeded.selector);
        assertEq(token.transientPoolManagerAllowance(), 0);
        assertEq(token.balanceOf(HOLDER), amount);
        assertEq(token.balanceOf(MANAGER), amount);
    }

    function check_protocolMovementAuthorizationIsSingleUse(uint96 amount) public {
        vm.assume(amount > 0);
        _protocolMint(HOLDER, uint256(amount) * 2);

        vm.prank(address(harness));
        token.protocolTransfer(HOLDER, RECIPIENT, amount);
        assertEq(harness.formalProtocolMovement(), bytes32(0));
        assertEq(token.balanceOf(RECIPIENT), amount);

        vm.prank(HOLDER);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(IPotatoToken.transfer, (RECIPIENT, uint256(amount))));
        assertFalse(success);
        assertEq(_selector(reason), Errors.TransferRestricted.selector);
        assertEq(token.balanceOf(HOLDER), amount);
        assertEq(token.balanceOf(RECIPIENT), amount);
    }

    function check_nonProtocolCannotMint(address caller, uint96 amount) public {
        vm.assume(caller != address(harness));
        uint256 supplyBefore = token.totalSupply();
        uint256 balanceBefore = token.balanceOf(RECIPIENT);

        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(
            abi.encodeCall(IPotatoToken.protocolMint, (RECIPIENT, uint256(amount)))
        );

        assertFalse(success);
        assertEq(_selector(reason), Errors.NotProtocol.selector);
        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(RECIPIENT), balanceBefore);
    }

    function _protocolMint(address recipient, uint256 amount) private {
        vm.prank(address(harness));
        token.protocolMint(recipient, amount);
    }

    function _selector(bytes memory reason) private pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
        }
    }
}
