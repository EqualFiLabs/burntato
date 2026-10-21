"""Exercise shell dispatch and file/receipt guards without RPCs or signing.

Only the private configuration paths are substituted in disposable copies.
cast/forge/git are stubbed; jq and the actual wrapper control flow are exercised.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMMIT = '1' * 40
TX = '0x' + '2' * 64
ADDR = '0x' + '3' * 40
CANONICAL = '0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316'

STUB = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps([name] + args) + '\\n')
if name == 'git':
    if args[:1] == ['rev-parse']: print(os.environ['SOURCE_HEAD'])
    elif args[:1] == ['diff']: sys.exit(int(os.environ.get('DIRTY_SOURCE', '0')))
elif name == 'forge':
    sys.exit(int(os.environ.get('FORGE_FAILURE', '0')))
elif name == 'cast':
    if args[0] == 'chain-id': print(os.environ['FIXTURE_CHAIN_ID'])
    elif args[0] == 'rpc':
        if os.environ.get('NOT_ANVIL'): sys.exit(1)
        print('true')
    elif args[0] == 'wallet': print(os.environ['SIGNER'])
    elif args[0] in ['calldata', 'abi-encode']: print('0x12345678')
    elif args[0] == 'receipt': print(json.dumps({'status': os.environ.get('RECEIPT_STATUS', '0x1')}))
    elif args[0] == 'block-number': print('123456')
'''

class WrapperFixture(unittest.TestCase):
    network = 'mainnet'
    chain = 4663

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='burntato-wrapper-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('cast', 'forge', 'git'):
            path = self.bin / name
            path.write_text(STUB)
            path.chmod(0o755)
        rpc = self.root / 'rpc-fixture'
        rpc.write_text('ROBINHOOD_MAINNET=http://fixture.invalid\nROBINHOOD_TESTNET=http://fixture.invalid\n')
        self.key = self.root / 'key-fixture'
        self.key.write_text('fixture-key')
        self.key.chmod(0o600)
        self.script = self.root / 'scripts' / f'deploy-robinhood-{self.network}.sh'
        source = (ROOT / 'scripts' / self.script.name).read_text()
        source = source.replace('/home/hooftly/.openclaw/workspace/.rpc', str(rpc))
        source = source.replace('/home/hooftly/.openclaw/workspace/.rhdeploy', str(self.key))
        self.script.write_text(source)
        shutil.copy(ROOT / 'scripts/verify-deployment.sh', self.root / 'scripts')
        self.output = self.root / 'artifacts' / f'robinhood-{self.network}'
        self.output.mkdir(parents=True)
        self.artifact = self.output / 'deployment.json'
        self.release = self.root / 'release.json'
        self.log = self.root / 'calls.jsonl'
        # Do not inherit private keys, RPC settings, or caller deployment overrides.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('BURNTATO_', 'ROBINHOOD_', 'STATICS_', 'ETH_', 'PRIVATE_KEY'))}
        self.env.update(PATH=str(self.bin) + ':' + os.environ['PATH'], CALL_LOG=str(self.log),
                        SOURCE_HEAD=COMMIT, FIXTURE_CHAIN_ID=str(self.chain), SIGNER=CANONICAL,
                        PRIVATE_KEY='fixture-key', BLOCKSCOUT_API_URL='http://explorer.invalid',
                        BURNTATO_RELEASE_RECORD=str(self.release))
        for role in ('DEPLOYER', 'FINAL_ADMIN', 'GUARDIAN', 'TREASURY', 'REWARD_ALLOCATOR'):
            self.env['BURNTATO_' + role] = CANONICAL
        self.deploy_name = 'DeployBurntatoRobinhood' + self.network.title()
        self.broadcast = self.root / 'broadcast' / (self.deploy_name + '.s.sol') / str(self.chain) / 'run-latest.json'

    def write_artifact(self):
        data = dict(schemaVersion=4, chainId=self.chain, sourceCommit=COMMIT)
        for field in ('diamond', 'deployer', 'admin', 'statics', 'diamondCutFacet', 'diamondLoupeFacet',
                      'governanceFacet', 'potatoTokenFacet', 'buybackFacet', 'gameFacet', 'recoveryFacet',
                      'settlementFacet', 'claimsFacet', 'treasuryRewardsFacet', 'foundationInit',
                      'operatorRewardsRouter', 'operatorsNft', 'activationRegistry'):
            data[field] = ADDR
        self.artifact.write_text(json.dumps(data))

    def write_broadcast(self, path=None, status='0x1'):
        path = path or self.broadcast
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({'receipts': [{'status': status, 'transactionHash': TX}]}))

    def run_mode(self, *args, success=True):
        result = subprocess.run(['bash', str(self.script), *args], cwd=self.root, env=self.env,
                                text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def calls(self, tool):
        if not self.log.exists(): return []
        return [x for x in map(json.loads, self.log.read_text().splitlines()) if x[0] == tool]

class WrapperTests(WrapperFixture):
    def test_read_only_phase_dispatch(self):
        self.write_artifact()
        for mode, signature in [('--inspect', 'checkDeployed()'), ('--check-staged', 'checkStaged()'), ('--check', 'checkActive()')]:
            self.run_mode(mode)
            call = self.calls('forge')[-1]
            self.assertIn(signature, call)
            self.assertNotIn('--broadcast', call)

    def test_initialize_dispatches_network_operation_and_records_receipt(self):
        self.write_artifact()
        name = 'OperateBurntatoRobinhood' + self.network.title()
        path = self.root / 'broadcast' / (name + '.s.sol') / str(self.chain) / 'initializePurchases-latest.json'
        self.write_broadcast(path)
        self.run_mode('--initialize')
        call = self.calls('forge')[-1]
        self.assertIn(f'script/{name}.s.sol:{name}', call)
        self.assertIn('initializePurchases()', call)
        self.assertIn('--broadcast', call)
        self.assertEqual(json.loads((self.output / 'operations.json').read_text()),
                         [dict(phase='initialize-purchases', transactionHashes=[TX])])

    def test_deploy_requires_explicit_broadcast_and_rejects_all_existing_state(self):
        self.run_mode('--deploy', success=False)
        for path in (self.artifact, self.broadcast, self.output / 'operations.json', self.output / 'initialize-call.json', self.release):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}')
            self.run_mode('--deploy', '--broadcast', success=False)
            path.unlink()
        self.assertEqual(self.calls('forge'), [])
        self.run_mode('--deploy', '--broadcast')
        self.assertIn('--broadcast', self.calls('forge')[-1])

    def test_resume_requires_existing_sequence_and_identical_clean_source(self):
        self.run_mode('--resume-deploy', '--broadcast', success=False)
        self.write_artifact()
        self.write_broadcast()
        self.env['SOURCE_HEAD'] = 'a' * 40
        self.run_mode('--resume-deploy', '--broadcast', success=False)
        self.env['SOURCE_HEAD'] = COMMIT
        self.env['DIRTY_SOURCE'] = '1'
        self.run_mode('--resume-deploy', '--broadcast', success=False)
        self.env['DIRTY_SOURCE'] = '0'
        self.run_mode('--resume-deploy', '--broadcast')
        self.assertIn('--resume', self.calls('forge')[-1])

    def test_source_verification_never_resumes_or_broadcasts(self):
        self.write_artifact()
        self.run_mode('--verify')
        calls = self.calls('forge')
        self.assertEqual(len(calls), 13)
        for call in calls:
            self.assertEqual(call[1], 'verify-contract')
            self.assertNotIn('--resume', call)
            self.assertNotIn('--broadcast', call)
        self.assertIn('--constructor-args', calls[0])
        self.assertIn('--constructor-args', calls[-1])

    def test_safe_bundle_requires_successful_readiness_and_never_signs(self):
        self.write_artifact()
        self.env['FORGE_FAILURE'] = '1'
        self.run_mode('--initialize-bundle', success=False)
        self.assertFalse((self.output / 'initialize-call.json').exists())
        self.env['FORGE_FAILURE'] = '0'
        self.env.pop('PRIVATE_KEY')
        self.run_mode('--initialize-bundle')
        self.assertIn('checkReadyForInitialization()', self.calls('forge')[-1])
        bundle = json.loads((self.output / 'initialize-call.json').read_text())
        self.assertEqual(bundle['call'], dict(to=ADDR, value='0', data='0x12345678', phase='initialize-purchases'))
        self.assertNotIn('--broadcast', self.calls('forge')[-1])

    def test_external_funding_and_initialization_record_without_buybacks(self):
        self.write_artifact()
        self.write_broadcast()
        self.env.update(BURNTATO_INITIALIZE_TX_HASH=TX, BURNTATO_FUNDING_TX_HASH=TX)
        self.run_mode('--record')
        record = json.loads(self.release.read_text())
        self.assertEqual([x['phase'] for x in record['operations']], ['initialize-purchases', 'fund-reward-reserve'])
        self.run_mode('--record', success=False)

    def test_failed_receipt_prevents_release_record(self):
        self.write_artifact()
        self.write_broadcast()
        self.env.update(BURNTATO_INITIALIZE_TX_HASH=TX, BURNTATO_FUNDING_TX_HASH=TX, RECEIPT_STATUS='0x0')
        self.run_mode('--record', success=False)
        self.assertFalse(self.release.exists())

    def test_bootstrap_requires_amount_and_records_only_successful_receipts(self):
        self.write_artifact()
        self.run_mode('--bootstrap', success=False)
        self.env['BURNTATO_BOOTSTRAP_BUYBACK_WEI'] = '1000000000000000000'
        path = self.root / 'broadcast/BootstrapBurntatoBuyback.s.sol' / str(self.chain) / 'run-latest.json'
        self.write_broadcast(path, status='0x0')
        self.run_mode('--bootstrap', success=False)
        self.assertFalse((self.output / 'operations.json').exists())
        self.write_broadcast(path)
        self.run_mode('--bootstrap')
        self.assertEqual(json.loads((self.output / 'operations.json').read_text())[0]['phase'], 'bootstrap-buyback')

    def test_wrong_chain_and_retired_market_modes_rejected(self):
        self.env['FIXTURE_CHAIN_ID'] = '1'
        self.run_mode('--preflight', success=False)
        for mode in ('--launch', '--enable', '--enable-bundle'):
            self.run_mode(mode, success=False)
        self.assertEqual(self.calls('forge'), [])

class TestnetWrapperTests(WrapperTests):
    network = 'testnet'
    chain = 46630

    def test_prepare_statics_preserves_handoff_provenance(self):
        source = self.root / 'statics.json'
        source.write_text('{}')
        self.env.update(STATICS_GENESIS_TESTNET_ARTIFACT=str(source), STATICS_SOURCE_COMMIT=COMMIT)
        (self.root / 'deployments').mkdir()
        handoff = dict(chainId=self.chain, genesisEpochEnd=2000000000, genesis=ADDR,
                       activationRegistry=ADDR, genesisVault=ADDR, finalizedBlock=123,
                       finalizedBlockHash=TX, staticsSourceCommit=COMMIT,
                       mainnetGenesisSourceCommit=COMMIT, genesisArtifactHash=TX,
                       operatorsNftRuntimeCodeHash=TX, activationRegistryRuntimeCodeHash=TX,
                       genesisVaultRuntimeCodeHash=TX)
        (self.output / 'statics-handoff.json').write_text(json.dumps(handoff))
        self.run_mode('--prepare-statics')
        manifest = json.loads((self.root / 'deployments/statics-operators-robinhood-testnet-46630.json').read_text())
        self.assertEqual(manifest['source']['commit'], COMMIT)
        self.assertEqual(manifest['finalizedBlockHash'], TX)
        self.assertEqual(manifest['genesisEpochEnd'], 2000000000)
        self.assertEqual(manifest['contracts']['genesisVault']['runtimeCodeHash'], TX)
        self.assertNotIn('--broadcast', self.calls('forge')[-1])

    def test_prepare_statics_rejects_malformed_handoff(self):
        source = self.root / 'statics.json'
        source.write_text('{}')
        self.env.update(STATICS_GENESIS_TESTNET_ARTIFACT=str(source), STATICS_SOURCE_COMMIT=COMMIT)
        (self.root / 'deployments').mkdir()
        (self.output / 'statics-handoff.json').write_text('{}')
        self.run_mode('--prepare-statics', success=False)
        self.assertFalse((self.root / 'deployments/statics-operators-robinhood-testnet-46630.json').exists())

    def test_canonical_fallback_key_checked_before_buyback(self):
        self.write_artifact()
        self.env.pop('PRIVATE_KEY')
        self.env['SIGNER'] = ADDR
        self.run_mode('--buyback', success=False)
        self.assertEqual(self.calls('forge'), [])
        self.assertTrue(any('wallet' in call for call in self.calls('cast')))

class MainnetRehearsalTests(WrapperFixture):
    def test_rehearsal_requires_anvil(self):
        self.env.update(BURNTATO_ANVIL_REHEARSAL='true', BURNTATO_LOCAL_RPC='http://127.0.0.1:8545', NOT_ANVIL='1')
        self.run_mode('--preflight', success=False)
        self.assertEqual(self.calls('forge'), [])

if __name__ == '__main__':
    unittest.main()
