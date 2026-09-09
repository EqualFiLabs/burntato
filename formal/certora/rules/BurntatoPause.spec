methods {
    function formalConfigurePauseState(address, address, bool, bool) external envfree;
    function authority() external returns (address) envfree;
    function guardian() external returns (address) envfree;
    function paused() external returns (bool) envfree;
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
}

rule guardianCanPause(address admin, address guardian_) {
    require admin != 0;
    require guardian_ != 0;
    require admin != guardian_;
    formalConfigurePauseState(admin, guardian_, false, true);

    env e;
    require e.msg.sender == guardian_;
    require e.msg.value == 0;
    setPaused(e, true);

    assert paused(), "guardian cannot pause";
}

rule guardianCannotUnpause(address admin, address guardian_) {
    require admin != 0;
    require guardian_ != 0;
    require admin != guardian_;
    formalConfigurePauseState(admin, guardian_, true, true);

    env e;
    require e.msg.sender == guardian_;
    require e.msg.value == 0;
    setPaused@withrevert(e, false);
    bool reverted = lastReverted;

    assert reverted, "guardian unpauses";
    assert paused(), "failed guardian unpause clears state";
}

rule unauthorizedCallerCannotPause(address admin, address guardian_, address caller) {
    require admin != 0;
    require guardian_ != 0;
    require caller != admin;
    require caller != guardian_;
    formalConfigurePauseState(admin, guardian_, false, true);

    env e;
    require e.msg.sender == caller;
    require e.msg.value == 0;
    setPaused@withrevert(e, true);
    bool reverted = lastReverted;

    assert reverted, "unauthorized caller pauses";
    assert !paused(), "failed unauthorized pause changes state";
}

rule authoritySetsEitherPauseState(address admin, address guardian_, bool initialState, bool nextState) {
    require admin != 0;
    require admin != guardian_;
    formalConfigurePauseState(admin, guardian_, initialState, true);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    setPaused(e, nextState);

    assert paused() == nextState, "authority cannot set pause state";
}

rule unsafeAuthorityRenunciationReverts(address admin, address guardian_, bool paused_) {
    require admin != 0;
    require guardian_ != 0 || paused_;
    formalConfigurePauseState(admin, guardian_, paused_, true);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    setAuthority@withrevert(e, 0);
    bool reverted = lastReverted;

    assert reverted, "authority renounces with live guardian or pause";
    assert authority() == admin, "failed renunciation changes authority";
}

rule cleanAuthorityRenunciationSucceeds(address admin) {
    require admin != 0;
    formalConfigurePauseState(admin, 0, false, true);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    setAuthority(e, 0);

    assert authority() == 0, "clean authority renunciation fails";
    assert guardian() == 0, "clean authority renunciation creates guardian";
    assert !paused(), "clean authority renunciation pauses protocol";
}

rule uninitializedAuthorityRenunciationReverts(address admin) {
    require admin != 0;
    formalConfigurePauseState(admin, 0, false, false);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    setAuthority@withrevert(e, 0);
    bool reverted = lastReverted;

    assert reverted, "authority renounces before purchase initialization";
    assert authority() == admin, "failed pre-initialization renunciation changes authority";
}

rule pausedProtocolMintRevertsWithoutSupplyChange(address admin, address recipient, uint256 amount) {
    require admin != 0;
    require recipient != 0;
    formalConfigurePauseState(admin, 0, true, true);
    uint256 supplyBefore = totalSupply();
    uint256 balanceBefore = balanceOf(recipient);

    env e;
    require e.msg.value == 0;
    formalProtocolMint@withrevert(e, recipient, amount);
    bool reverted = lastReverted;

    assert reverted, "paused protocol mint succeeds";
    assert totalSupply() == supplyBefore, "paused mint changes total supply";
    assert balanceOf(recipient) == balanceBefore, "paused mint changes recipient balance";
}
