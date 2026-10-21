// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {BurntatoDeploymentConfig} from "./libraries/BurntatoDeploymentConfig.sol";
import {DeployBurntato} from "./DeployBurntato.s.sol";
import {
    BurntatoDeployment,
    GenesisConfig,
    StaticsMarketDependencies,
    StaticsOperatorDependencies
} from "./DeploymentTypes.sol";
import {StaticsMarketDeploymentConfig} from "./libraries/StaticsMarketDeploymentConfig.sol";
import {StaticsOperatorDeploymentConfig} from "./libraries/StaticsOperatorDeploymentConfig.sol";

interface ITestnetStaticsGenesis {
    function vault() external view returns (address);
}

interface ITestnetStaticsGenesisVault {
    function genesisEpochEnd() external view returns (uint256);
}

contract DeployBurntatoRobinhoodTestnet is DeployBurntato {
    uint256 public constant CHAIN_ID = 46630;
    string private constant STATICS_MANIFEST_PATH = "deployments/statics-operators-robinhood-testnet-46630.json";
    error InvalidStaticsGenesisVault(address expected, address actual);
    error InvalidStaticsGenesisVaultCodeHash(bytes32 expected, bytes32 actual);
    error InvalidStaticsGenesisEpoch(uint256 expected, uint256 actual);
    error ExpiredStaticsGenesisEpoch(uint256 epochEnd, uint256 currentTimestamp);

    function _environmentConfig() internal view override returns (GenesisConfig memory c) {
        require(block.chainid == CHAIN_ID, "incorrect Robinhood chain");
        c = BurntatoDeploymentConfig.launchDefaults();
        c.deployer = vm.envAddress("BURNTATO_DEPLOYER");
        c.finalAdmin = vm.envOr("BURNTATO_FINAL_ADMIN", c.deployer);
        c.guardian = vm.envOr("BURNTATO_GUARDIAN", c.deployer);
        c.treasuryRecipient = vm.envOr("BURNTATO_TREASURY", c.deployer);
        c.rewardAllocator = vm.envOr("BURNTATO_REWARD_ALLOCATOR", c.deployer);
        require(c.deployer == 0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316, "canonical testnet deployer required");
        return c;
    }

    function preflight()
        external
        view
        returns (GenesisConfig memory c, StaticsMarketDependencies memory m, StaticsOperatorDependencies memory o)
    {
        c = _environmentConfig();
        m = StaticsMarketDeploymentConfig.load();
        o = StaticsOperatorDeploymentConfig.load();
        StaticsMarketDeploymentConfig.validate(m);
        _validateOperators(o);
        c.statics = m.statics;
        _validateConfig(c, c.deployer);
        require(c.deployer.balance >= c.initialWinnerReserve, "initial Winner reserve not funded");
    }

    function _validateOperators(StaticsOperatorDependencies memory o) internal view override {
        StaticsOperatorDeploymentConfig.validate(o);
        _validateActiveStaticsReplica(o);
    }

    function _validateActiveStaticsReplica(StaticsOperatorDependencies memory operatorDependencies) private view {
        string memory manifest = vm.readFile(STATICS_MANIFEST_PATH);
        address expectedVault = vm.parseJsonAddress(manifest, ".contracts.genesisVault.address");
        bytes32 expectedVaultCodeHash = vm.parseJsonBytes32(manifest, ".contracts.genesisVault.runtimeCodeHash");
        uint256 expectedEpochEnd = vm.parseJsonUint(manifest, ".genesisEpochEnd");

        validateActiveStaticsReplica(
            operatorDependencies.operatorsNft, expectedVault, expectedVaultCodeHash, expectedEpochEnd
        );
    }

    function validateActiveStaticsReplica(
        address operatorsNft,
        address expectedVault,
        bytes32 expectedVaultCodeHash,
        uint256 expectedEpochEnd
    ) public view returns (bool) {
        address actualVault = ITestnetStaticsGenesis(operatorsNft).vault();
        if (actualVault != expectedVault) revert InvalidStaticsGenesisVault(expectedVault, actualVault);
        bytes32 actualVaultCodeHash = actualVault.codehash;
        if (actualVaultCodeHash != expectedVaultCodeHash) {
            revert InvalidStaticsGenesisVaultCodeHash(expectedVaultCodeHash, actualVaultCodeHash);
        }
        uint256 actualEpochEnd = ITestnetStaticsGenesisVault(actualVault).genesisEpochEnd();
        if (actualEpochEnd != expectedEpochEnd) revert InvalidStaticsGenesisEpoch(expectedEpochEnd, actualEpochEnd);
        if (actualEpochEnd <= block.timestamp) revert ExpiredStaticsGenesisEpoch(actualEpochEnd, block.timestamp);
        return true;
    }
}
