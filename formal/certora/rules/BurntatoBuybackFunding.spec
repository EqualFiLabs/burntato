methods {
    function formalConfigureFundingState(uint256, uint256, uint256) external envfree;
    function formalReentrancyStatus() external returns (uint256) envfree;
    function buybackReserveEth() external returns (uint256) envfree;
    function lastBuybackBlock() external returns (uint256) envfree;
}

rule positiveFundingIsExact(uint256 reserve, uint256 amount, uint256 lastBlock, address caller) {
    require reserve < 340282366920938463463374607431768211456;
    require amount > 0;
    require amount < 340282366920938463463374607431768211456;
    formalConfigureFundingState(reserve, lastBlock, 1);

    env e;
    require e.msg.sender == caller;
    require e.msg.value == amount;
    fundBuybackReserve(e);

    assert buybackReserveEth() == reserve + amount, "positive funding is not additive";
    assert lastBuybackBlock() == lastBlock, "funding changes the execution cooldown";
    assert formalReentrancyStatus() == 1, "funding leaves the shared guard entered";
}

rule zeroFundingRevertsWithoutMutation(uint256 reserve, uint256 lastBlock, address caller) {
    formalConfigureFundingState(reserve, lastBlock, 1);

    env e;
    require e.msg.sender == caller;
    require e.msg.value == 0;
    fundBuybackReserve@withrevert(e);
    bool reverted = lastReverted;

    assert reverted, "zero funding succeeds";
    assert buybackReserveEth() == reserve, "zero funding changes the reserve";
    assert lastBuybackBlock() == lastBlock, "zero funding changes the execution cooldown";
    assert formalReentrancyStatus() == 1, "zero funding changes the shared guard";
}

rule enteredGuardRejectsFunding(uint256 reserve, uint256 amount, uint256 lastBlock, address caller) {
    require amount > 0;
    formalConfigureFundingState(reserve, lastBlock, 2);

    env e;
    require e.msg.sender == caller;
    require e.msg.value == amount;
    fundBuybackReserve@withrevert(e);
    bool reverted = lastReverted;

    assert reverted, "funding bypasses the entered shared guard";
    assert buybackReserveEth() == reserve, "reentrant funding changes the reserve";
    assert lastBuybackBlock() == lastBlock, "reentrant funding changes the execution cooldown";
    assert formalReentrancyStatus() == 2, "reentrant funding clears the entered guard";
}
