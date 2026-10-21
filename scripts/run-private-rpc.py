#!/usr/bin/env python3
"""Run a command with a configured RPC, redacting endpoint values from child output."""
import argparse
import os
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--network", choices=("mainnet", "testnet", "local"), required=True)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ["--"] else args.command
if not command:
    parser.error("command required")
variable = {"mainnet": "ROBINHOOD_MAINNET", "testnet": "ROBINHOOD_TESTNET", "local": "BURNTATO_LOCAL_RPC"}[args.network]
rpc = os.environ.get(variable)
if not rpc:
    parser.error(variable + " is unavailable after loading canonical RPC configuration")
env = dict(os.environ, ETH_RPC_URL=rpc, FOUNDRY_DISABLE_NIGHTLY_WARNING="1")
if command[:2] == ["forge", "script"]:
    command += ["--rpc-url", rpc]
elif command[0] == "anvil":
    command += ["--fork-url", rpc]
secrets = [v for k, v in env.items() if v and ("RPC" in k or k in ("ROBINHOOD_MAINNET", "ROBINHOOD_TESTNET", "PRIVATE_KEY"))]
with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1) as process:
    for line in process.stdout:
        for value in secrets:
            line = line.replace(value, "[REDACTED]")
        print(line, end="", flush=True)
    sys.exit(process.wait())
