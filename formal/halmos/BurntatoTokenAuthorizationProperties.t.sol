// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {MockStatics} from "../../test/mocks/MockStatics.sol";
import {PotatoTokenFacet} from "../../src/facets/PotatoTokenFacet.sol";
import {IPotatoToken} from "../../src/interfaces/IPotatoToken.sol";
import {LibDiamond} from "../../src/libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../../src/libraries/LibProtocolStorage.sol";
import {Errors} from "../../src/shared/Errors.sol";

contract SymbolicPotatoHarness is PotatoTokenFacet {
    constructor(address statics, address authority) {
        LibProtocolStorage.wrapper().underlying = statics;
        LibProtocolStorage.wrapper().publicWrapCap = 2_000_000 ether;
        LibProtocolStorage.treasury().recipient = address(0xD00D);
        LibDiamond.transferAuthority(authority);
    }

    function formalProtocolMovement() external view returns (bytes32 movement) {
        bytes32 slot = LibProtocolStorage.PROTOCOL_MOVEMENT_SLOT;
        assembly ("memory-safe") { movement := tload(slot) }
    }
}

contract BurntatoTokenAuthorizationProperties is Test {
    address private constant HOLDER = address(0xCAFE);
    address private constant RECIPIENT = address(0xD00D);
    SymbolicPotatoHarness private token;
    MockStatics private statics;

    function setUp() public {
        statics = new MockStatics();
        token = new SymbolicPotatoHarness(address(statics), address(this));
    }

    function _wrap(uint256 amount) private {
        statics.mint(HOLDER, amount);
        vm.startPrank(HOLDER);
        statics.approve(address(token), amount);
        token.wrap(amount);
        vm.stopPrank();
    }

    function check_exactWrapAndUnwrapReopenCapacity(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 2_000_000 ether);
        _wrap(amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.backingBalance(), amount);
        assertEq(token.publicWrapOutstanding(), amount);
        vm.prank(HOLDER);
        token.unwrap(amount);
        assertEq(token.totalSupply(), 0);
        assertEq(token.publicWrapOutstanding(), 0);
        assertEq(statics.balanceOf(HOLDER), amount);
    }

    function check_publicCapRejectsWithoutTakingBacking(uint96 amount) public {
        vm.assume(amount > 2_000_000 ether);
        statics.mint(HOLDER, amount);
        vm.startPrank(HOLDER);
        statics.approve(address(token), amount);
        (bool ok,) = address(token).call(abi.encodeCall(IPotatoToken.wrap, (uint256(amount))));
        vm.stopPrank();
        assertFalse(ok);
        assertEq(token.totalSupply(), 0);
        assertEq(statics.balanceOf(HOLDER), amount);
    }

    function check_reserveFundingDoesNotConsumePublicCapacity(uint96 amount) public {
        vm.assume(amount > 0);
        statics.mint(address(this), amount);
        statics.approve(address(token), amount);
        token.fundRewardReserve(amount);
        assertEq(token.rewardReserve(), amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.backingBalance(), amount);
        assertEq(token.publicWrapOutstanding(), 0);
        assertEq(token.balanceOf(address(token)), amount);
    }

    function check_lowerCapNeverPreventsRedemption(uint96 amount, uint96 cap) public {
        vm.assume(amount > 0 && amount <= 2_000_000 ether);
        vm.assume(cap < amount);
        _wrap(amount);
        token.setPublicWrapCap(cap);
        assertEq(token.availablePublicWrapCapacity(), 0);
        vm.prank(HOLDER);
        token.unwrap(amount);
        assertEq(token.publicWrapOutstanding(), 0);
        assertEq(token.availablePublicWrapCapacity(), cap);
    }

    function check_protocolMovementAuthorizationIsSingleUse(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 1_000_000 ether);
        _wrap(uint256(amount) * 2);
        vm.prank(address(token));
        token.protocolTransfer(HOLDER, RECIPIENT, amount);
        assertEq(token.formalProtocolMovement(), bytes32(0));
        vm.prank(HOLDER);
        (bool ok,) = address(token).call(abi.encodeCall(IPotatoToken.transfer, (RECIPIENT, uint256(amount))));
        assertFalse(ok);
        assertEq(token.balanceOf(HOLDER), amount);
        assertEq(token.balanceOf(RECIPIENT), amount);
    }

    function check_nonProtocolCannotCreditReserveOrRedeemRecovery(address caller, uint96 amount) public {
        vm.assume(caller != address(token));
        vm.prank(caller);
        (bool credit,) =
            address(token).call(abi.encodeCall(IPotatoToken.protocolCreditRewardReserve, (uint256(amount), 0)));
        vm.prank(caller);
        (bool redeem,) = address(token).call(abi.encodeCall(IPotatoToken.protocolRedeemRecovery, (uint256(amount))));
        assertFalse(credit);
        assertFalse(redeem);
        assertEq(token.totalSupply(), 0);
        assertEq(token.rewardReserve(), 0);
    }

    function check_recoveryUsesSameRedemptionAndCapacityAccounting(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 2_000_000 ether);
        _wrap(amount);
        vm.prank(address(token));
        token.protocolTransfer(HOLDER, address(token), amount);
        vm.prank(address(token));
        token.protocolRedeemRecovery(amount);
        assertEq(token.totalSupply(), 0);
        assertEq(token.publicWrapOutstanding(), 0);
        assertEq(statics.balanceOf(RECIPIENT), amount);
    }
}
