# Robinhood testnet deployment

This is the live Burntato and standalone Statics Genesis launch used for app
integration on Robinhood Chain testnet, chain ID `46630`. The canonical
machine-readable record is
[`deployments/robinhood-testnet-46630-launch.json`](../deployments/robinhood-testnet-46630-launch.json).

## Addresses

| Component | Address |
| --- | --- |
| Burntato Diamond / POTATO | [`0x1FA9a3c895e802670b35a9d577D42d4dE20e4818`](https://explorer.testnet.chain.robinhood.com/address/0x1FA9a3c895e802670b35a9d577d42d4de20e4818) |
| Burntato timelock | [`0xCE71F6339F52016a90c0FD90e0617039c5AD47A1`](https://explorer.testnet.chain.robinhood.com/address/0xce71f6339f52016a90c0fd90e0617039c5ad47a1) |
| Burntato swap-fee hook | [`0x5b7a45802d5a6076b510D2d9D9EC175a19EE2444`](https://explorer.testnet.chain.robinhood.com/address/0x5b7a45802d5a6076b510d2d9d9ec175a19ee2444) |
| Operator rewards router | [`0x09ac7A514db0bBf0B2E3630ace9C30b17393E24D`](https://explorer.testnet.chain.robinhood.com/address/0x09ac7a514db0bbf0b2e3630ace9c30b17393e24d) |
| Statics Genesis Operator NFT | [`0x8BB2E39abAE7346293Ff084fd4D104b064BEbC71`](https://explorer.testnet.chain.robinhood.com/address/0x8bb2e39abae7346293ff084fd4d104b064bebc71) |
| Genesis Activation Registry | [`0xcE4D413915B4C6dE7DfD486d233596Da35c5cFbD`](https://explorer.testnet.chain.robinhood.com/address/0xce4d413915b4c6de7dfd486d233596da35c5cfbd) |
| STATICS | [`0xcDe1F22F70DB6C42c7C0050e6F3B53d03a2006eD`](https://explorer.testnet.chain.robinhood.com/address/0xcde1f22f70db6c42c7c0050e6f3b53d03a2006ed) |
| 200K STATICS faucet | [`0xd2e561B46a2de6713F53d954C0415447100d2955`](https://explorer.testnet.chain.robinhood.com/address/0xd2e561b46a2de6713f53d954c0415447100d2955) |

The Burntato pool ID is
`0xd0bb2fb1266e97d81cf260a1b4d12d21eee323dd0189265483baf9b8987fd91b`.
The market launch permanently locked `1,000,400,500,818,288,116,093,059`
liquidity units at the dead recipient.

## Live configuration

Purchase revenue is split 25% Winner, 30% Recovery, 20% Treasury, 10%
buyback, and 15% Operators. The bilateral swap fee is 1%; 40% of that fee is
sent to the shared Operator router and 60% to Treasury. The Diamond and hook
are administered by the 120-second timelock. The broadcaster is proposer,
guardian, Treasury recipient, and reward allocator. External buys were enabled
through the timelock after market launch.

The Statics Genesis epoch ends at Unix timestamp `1789740317`, 15 days after
deployment. The faucet dispenses `200,000 STATICS` per wallet every 24 hours
and was funded for one initial claim.

## Evidence

- The exact-profile pre-launch verifier returned `true`.
- The live post-launch check confirmed the pool is launched and external buys
  are enabled.
- The Diamond, hook, Operator router, all eleven facets, initializer,
  and hook deployer are source-verified on Blockscout. The standard
  OpenZeppelin timelock is the only owned contract not source-verified; its
  submission was blocked by local standard-JSON dependency path resolution.
- The live Operator router reads the fresh Genesis NFT and Activation Registry,
  and both purchase and hook revenue point to that same router.
- The tracked runtime hashes and ceremony transaction hashes are recorded in
  the JSON manifest.

The faucet funding swap succeeded, but the first scripted allowance-cleanup
transaction exhausted its estimated gas before the transfer step. Operations
cleared the residual allowance with an explicit gas limit, transferred the
acquired 200K STATICS to the already-deployed faucet, unwrapped the WETH
refund, and verified the final faucet balance and zero residual allowance. The
reusable Statics script now consumes its full seeder allowance atomically and
uses a doubled broadcast gas-estimation margin.
