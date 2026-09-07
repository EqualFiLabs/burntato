methods {
    function formalConfigureState(address, bool, bool) external envfree;
    function formalFoundationInitialized() external returns (bool) envfree;
    function authority() external returns (address) envfree;
    function purchasesInitialized() external returns (bool) envfree;
}

rule foundationConfigurationIsRequired(address admin) {
    require admin != 0;
    formalConfigureState(admin, false, false);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    initializePurchases@withrevert(e);
    bool reverted = lastReverted;

    assert reverted, "admin activates purchases before foundation configuration";
    assert !purchasesInitialized(), "failed activation mutates purchase state";
}

rule onlyCurrentAuthorityCanInitialize(address admin, address caller) {
    require admin != 0;
    require caller != admin;
    formalConfigureState(admin, true, false);

    env e;
    require e.msg.sender == caller;
    require e.msg.value == 0;
    initializePurchases@withrevert(e);
    bool reverted = lastReverted;

    assert reverted, "non-authority initializes purchases";
    assert !purchasesInitialized(), "unauthorized call mutates purchase state";
}

rule currentAuthorityInitializes(address admin) {
    require admin != 0;
    formalConfigureState(admin, true, false);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    initializePurchases(e);

    assert purchasesInitialized(), "authority cannot initialize purchases";
}

rule activationIsOneShot(address admin) {
    require admin != 0;
    formalConfigureState(admin, true, true);

    env e;
    require e.msg.sender == admin;
    require e.msg.value == 0;
    initializePurchases@withrevert(e);
    bool reverted = lastReverted;

    assert reverted, "purchase activation succeeds more than once";
    assert purchasesInitialized(), "repeat activation clears purchase state";
}

rule successorAuthorityCanInitialize(address admin, address successor) {
    require admin != 0;
    require successor != 0;
    require successor != admin;
    formalConfigureState(admin, true, false);

    env transferEnv;
    require transferEnv.msg.sender == admin;
    require transferEnv.msg.value == 0;
    setAuthority(transferEnv, successor);
    assert authority() == successor, "authority transfer does not install successor";

    env activationEnv;
    require activationEnv.msg.sender == successor;
    require activationEnv.msg.value == 0;
    initializePurchases(activationEnv);
    assert purchasesInitialized(), "successor authority cannot initialize purchases";
}
