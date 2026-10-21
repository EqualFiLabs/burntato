// SPDX-License-Identifier: BUSL-1.1
// ============================================================================
//                                BURNTATO
//                                Grab it.
//                          https://burntato.fun
//                              EqualFi Labs
// ============================================================================
pragma solidity 0.8.26;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibProtocolStorage} from "../libraries/LibProtocolStorage.sol";
import {LibGuard} from "../libraries/LibGuard.sol";
import {Errors} from "../shared/Errors.sol";
import {Round} from "../shared/Types.sol";

contract PotatoTokenFacet is ERC20, LibGuard {
    event Wrapped(address indexed account, uint256 staticsDeposited, uint256 potatoMinted);
    event Unwrapped(address indexed account, address indexed recipient, uint256 potatoBurned, uint256 staticsReturned);
    event RewardReserveFunded(address indexed funder, uint256 staticsDeposited, uint256 potatoMinted, uint256 reserve);
    event PublicWrapCapSet(uint256 previousCap, uint256 cap);
    event DistributorSet(address indexed account, bool allowed);

    function name() public pure override returns (string memory) {
        return "Burntato Potato";
    }

    function symbol() public pure override returns (string memory) {
        return "POTATO";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function underlying() public view returns (address) {
        return LibProtocolStorage.wrapper().underlying;
    }

    function backingBalance() public view returns (uint256) {
        return SafeTransferLib.balanceOf(underlying(), address(this));
    }

    function publicWrapCap() external view returns (uint256) {
        return LibProtocolStorage.wrapper().publicWrapCap;
    }

    function publicWrapOutstanding() external view returns (uint256) {
        return LibProtocolStorage.wrapper().publicWrapOutstanding;
    }

    function availablePublicWrapCapacity() public view returns (uint256) {
        LibProtocolStorage.WrapperStorage storage ws = LibProtocolStorage.wrapper();
        return ws.publicWrapCap > ws.publicWrapOutstanding ? ws.publicWrapCap - ws.publicWrapOutstanding : 0;
    }

    function rewardReserve() public view returns (uint256) {
        return LibProtocolStorage.wrapper().rewardReserve;
    }

    /// @notice Inventory available after reserving the active round's remaining base budget.
    function availableRewardInventory() public view returns (uint256) {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        Round storage round = gs.rounds[gs.currentRoundId];
        uint256 committed = round.currentHolder != address(0) && !round.settled ? round.remainingEmission : 0;
        uint256 inventory = rewardReserve();
        return inventory > committed ? inventory - committed : 0;
    }

    function nextRoundFundingStatus()
        external
        view
        returns (uint256 roundId, uint256 required, uint256 available, bool funded)
    {
        LibProtocolStorage.GameStorage storage gs = LibProtocolStorage.game();
        uint256 current = gs.currentRoundId;
        roundId = current == 0 ? 1 : (gs.rounds[current].currentHolder == address(0) ? current : current + 1);
        Round storage next = gs.rounds[roundId];
        required = next.roundId == 0 ? gs.config.roundEmissionBudget : next.config.roundEmissionBudget;
        available = availableRewardInventory();
        funded = available >= required;
    }

    function setPublicWrapCap(uint256 cap) external {
        LibDiamond.enforceAuthority();
        LibProtocolStorage.WrapperStorage storage ws = LibProtocolStorage.wrapper();
        emit PublicWrapCapSet(ws.publicWrapCap, cap);
        ws.publicWrapCap = cap;
    }

    function wrap(uint256 amount) external nonReentrant {
        if (LibProtocolStorage.governance().paused) revert Errors.ProtocolPaused();
        uint256 capacity = availablePublicWrapCapacity();
        if (amount > capacity) revert Errors.PublicWrapCapacityExceeded(capacity, amount);
        _deposit(msg.sender, amount);
        LibProtocolStorage.wrapper().publicWrapOutstanding += amount;
        _mint(msg.sender, amount);
        _enforceBacking();
        emit Wrapped(msg.sender, amount, amount);
    }

    /// @notice Redemption remains available while paused and above a lowered cap.
    function unwrap(uint256 amount) external nonReentrant {
        _redeem(msg.sender, msg.sender, amount);
    }

    /// @notice Irreversible, backed reserve contributions remain available while paused.
    function fundRewardReserve(uint256 amount) external nonReentrant {
        _deposit(msg.sender, amount);
        _creditReserve(msg.sender, amount);
    }

    /// @dev Only buyback's guarded self-call can credit newly acquired backing.
    function protocolCreditRewardReserve(uint256 amount, uint256 backingBefore) external {
        _enforceProtocol();
        if (backingBalance() != backingBefore + amount) revert Errors.InvalidBacking();
        _creditReserve(address(this), amount);
    }

    /// @dev Settlement redeems only Diamond escrow to the current Treasury recipient.
    function protocolRedeemRecovery(uint256 amount) external {
        _enforceProtocol();
        _redeem(address(this), LibProtocolStorage.treasury().recipient, amount);
    }

    function _deposit(address from, uint256 amount) private {
        if (amount == 0) revert Errors.ZeroAmount();
        uint256 beforeBalance = backingBalance();
        SafeTransferLib.safeTransferFrom(underlying(), from, address(this), amount);
        if (backingBalance() != beforeBalance + amount) revert Errors.InvalidBacking();
    }

    function _creditReserve(address funder, uint256 amount) private {
        if (amount == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.wrapper().rewardReserve += amount;
        _mint(address(this), amount);
        _enforceBacking();
        emit RewardReserveFunded(funder, amount, amount, rewardReserve());
    }

    function _redeem(address account, address recipient, uint256 amount) private {
        if (amount == 0) revert Errors.ZeroAmount();
        LibProtocolStorage.WrapperStorage storage ws = LibProtocolStorage.wrapper();
        _burn(account, amount);
        ws.publicWrapOutstanding -= amount < ws.publicWrapOutstanding ? amount : ws.publicWrapOutstanding;
        uint256 beforeBalance = backingBalance();
        uint256 recipientBefore = SafeTransferLib.balanceOf(underlying(), recipient);
        SafeTransferLib.safeTransfer(underlying(), recipient, amount);
        if (
            backingBalance() != beforeBalance - amount
                || SafeTransferLib.balanceOf(underlying(), recipient) != recipientBefore + amount
        ) {
            revert Errors.InvalidBacking();
        }
        _enforceBacking();
        emit Unwrapped(account, recipient, amount, amount);
    }

    function _enforceBacking() private view {
        if (backingBalance() < totalSupply()) revert Errors.InvalidBacking();
    }

    function isDistributor(address account) external view returns (bool) {
        return LibProtocolStorage.token().distributors[account];
    }

    function setDistributor(address account, bool allowed) external {
        LibDiamond.enforceAuthority();
        if (account == address(0)) revert Errors.InvalidAddress();
        LibProtocolStorage.token().distributors[account] = allowed;
        emit DistributorSet(account, allowed);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == address(0)) revert Errors.TransferRestricted(msg.sender, to);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (from == address(0) || to == address(0)) revert Errors.TransferRestricted(from, to);
        return super.transferFrom(from, to, amount);
    }

    function protocolTransfer(address from, address to, uint256 amount) external {
        _enforceProtocol();
        if (from == address(0) || to == address(0)) revert Errors.TransferRestricted(from, to);
        _setProtocolMovement(keccak256(abi.encode(from, to, amount)));
        _transfer(from, to, amount);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) return;
        if (_protocolMovement() == keccak256(abi.encode(from, to, amount))) {
            _setProtocolMovement(bytes32(0));
            return;
        }
        LibProtocolStorage.TokenStorage storage ts = LibProtocolStorage.token();
        if (ts.distributors[from] || ts.distributors[to]) return;
        address authority = LibDiamond.authority();
        if (from == authority || to == authority) return;
        revert Errors.TransferRestricted(from, to);
    }

    function _enforceProtocol() private view {
        if (msg.sender != address(this)) revert Errors.NotProtocol(msg.sender);
    }

    function _protocolMovement() private view returns (bytes32 movement) {
        bytes32 slot = LibProtocolStorage.PROTOCOL_MOVEMENT_SLOT;
        assembly ("memory-safe") { movement := tload(slot) }
    }

    function _setProtocolMovement(bytes32 movement) private {
        bytes32 slot = LibProtocolStorage.PROTOCOL_MOVEMENT_SLOT;
        assembly ("memory-safe") { tstore(slot, movement) }
    }
}
