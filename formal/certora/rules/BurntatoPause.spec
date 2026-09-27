methods {
    function formalConfigurePauseState(address, address, bool, bool) external envfree;
    function formalConfigureBuybackState(uint256, uint256) external envfree;
    function formalInstallBuybackFundingSelector() external envfree;
    function formalProtocolMintResult(address, uint256) external returns (bool, uint256);
    function authority() external returns (address) envfree;
    function guardian() external returns (address) envfree;
    function paused() external returns (bool) envfree;
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function buybackReserveEth() external returns (uint256) envfree;
    function lastBuybackBlock() external returns (uint256) envfree;
    function formalUnlockCount() external returns (uint256) envfree;
    function formalBuybackResult() external returns (bool, uint256);
    function formalProtocolPausedSelector() external returns (uint256) envfree;
    function buyback() external returns (uint256);
    function _.unlock(bytes) external => DISPATCHER(false);
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
    bool succeeded;
    uint256 revertSelector;
    succeeded, revertSelector = formalProtocolMintResult(e, recipient, amount);

    assert !succeeded, "paused protocol mint succeeds";
    assert revertSelector == formalProtocolPausedSelector(), "paused protocol mint reverts for the wrong reason";
    assert totalSupply() == supplyBefore, "paused mint changes total supply";
    assert balanceOf(recipient) == balanceBefore, "paused mint changes recipient balance";
}

rule unpausedProtocolMintChangesOnlySupplyAndRecipient(address admin, address recipient, uint256 amount) {
    require admin != 0;
    require recipient != 0;
    formalConfigurePauseState(admin, 0, false, true);
    uint256 supplyBefore = totalSupply();
    uint256 balanceBefore = balanceOf(recipient);
    require amount <= 115792089237316195423570985008687907853269984665640564039457584007913129639935 - supplyBefore;
    require amount <= 115792089237316195423570985008687907853269984665640564039457584007913129639935 - balanceBefore;

    env e;
    require e.msg.value == 0;
    bool succeeded;
    uint256 revertSelector;
    succeeded, revertSelector = formalProtocolMintResult(e, recipient, amount);

    assert succeeded, "unpaused protocol mint fails";
    assert revertSelector == 0, "successful protocol mint reports a revert selector";
    assert totalSupply() == supplyBefore + amount, "unpaused mint changes supply by the wrong amount";
    assert balanceOf(recipient) == balanceBefore + amount, "unpaused mint changes recipient by the wrong amount";
}

rule pausedBuybackRevertsWithoutAccountingChange(
    address admin,
    address treasury,
    uint256 reserve,
    uint256 lastExecutionBlock
) {
    require admin != 0;
    require reserve > 0;
    require lastExecutionBlock == 0;
    formalConfigurePauseState(admin, 0, true, true);
    formalConfigureBuybackState(reserve, lastExecutionBlock);
    uint256 treasuryBefore = balanceOf(treasury);

    env e;
    require e.msg.value == 0;
    bool succeeded;
    uint256 revertSelector;
    succeeded, revertSelector = formalBuybackResult(e);

    assert !succeeded, "paused buyback succeeds";
    assert revertSelector == formalProtocolPausedSelector(), "paused buyback reverts for the wrong reason";
    assert buybackReserveEth() == reserve, "paused buyback changes reserve";
    assert lastBuybackBlock() == lastExecutionBlock, "paused buyback changes cooldown";
    assert balanceOf(treasury) == treasuryBefore, "paused buyback changes Treasury POTATO";
    assert formalUnlockCount() == 0, "paused buyback reaches the PoolManager boundary";
}

rule unpausedExecutableBuybackReachesManager(address admin, uint256 reserve) {
    require admin != 0;
    require reserve > 0;
    require reserve <= 1000000000000000000;
    formalConfigurePauseState(admin, 0, false, true);
    formalConfigureBuybackState(reserve, 0);

    env e;
    require e.msg.value == 0;
    buyback(e);

    assert formalUnlockCount() == 1, "unpaused buyback does not reach the PoolManager boundary exactly once";
}

rule pausedDirectFundingRemainsAvailable(
    address admin,
    address caller,
    uint256 reserve,
    uint256 amount,
    uint256 lastExecutionBlock
) {
    require admin != 0;
    require amount > 0;
    require reserve < 340282366920938463463374607431768211456;
    require amount < 340282366920938463463374607431768211456;
    formalConfigurePauseState(admin, 0, true, true);
    formalConfigureBuybackState(reserve, lastExecutionBlock);
    formalInstallBuybackFundingSelector();

    env e;
    require e.msg.sender == caller;
    require e.msg.value == amount;
    fundBuybackReserve(e);

    assert buybackReserveEth() == reserve + amount, "paused funding does not increase reserve exactly";
    assert lastBuybackBlock() == lastExecutionBlock, "paused funding changes cooldown";
    assert paused(), "paused funding clears pause";
}
