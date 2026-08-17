# Integration guide

## Diamond interfaces

Integrators use the `BurntatoDiamond` address for gameplay, POTATO ERC-20 and
Permit operations, Recovery, settlement, claims, market views, and governance.
Use the EIP-2535 loupe to resolve the installed facet for each selector.

Important state reads include:

- `IGame.currentRoundId()`, `getRound()`, and `currentEarnedEmission()`;
- `IGovernance.protocolConfig()`, authority, guardian, pause, and finalization
  views;
- `IRecovery.recoveryCommitment()` and `totalRecoveryCommitment()`;
- Treasury claimable ETH and POTATO views; and
- `IMarket.marketConfig()`, `canonicalPoolKey()`, `marketState()`, and
  `marketReady()`;
- `IPotatoToken.isDistributor(account)` for the governed transfer allowlist; and
- `IBuyback.buybackConfig()`, `buybackReserveEth()`, and `lastBuybackBlock()`.

The canonical hook is a separate administered contract. Read `owner()`,
`token()`, `poolManager()`, `tickSpacing()`, `feeAddress()`, `feeBps()`, and
`deploymentBlock()`, and `externalBuysEnabled()` from the hook itself.

## POTATO behavior

POTATO is Solady ERC-20 plus EIP-2612 Permit behind the Diamond. `name`, `symbol`,
`decimals`, balances, supply, approvals, `permit`, nonces, and domain separator
follow the Solady implementation. The token exposes `burn(amount)` for voluntary
self-burning.

An ERC-20 approval or Permit does not make ordinary transfers valid. The
transfer hook permits only:

1. minting and burning;
2. transfers where either endpoint is an administered distributor;
3. transfers where either endpoint is the current protocol authority;
4. an exact protocol transfer authorized and consumed during a Diamond self-call;
5. a transfer to or from the configured PoolManager covered by the exact
   transient allowance opened by the canonical hook.

All other underlying POTATO movements revert. The transient PoolManager
allowance expires with the transaction and is observable through
`transientPoolManagerAllowance()` for integration testing.
Public transfers to or from `address(0)` also revert. `burn(amount)` is the
supported voluntary destruction path and reduces `totalSupply()` exactly.
The authority administers distributors through `setDistributor(account,
allowed)`. The initial Treasury recipient is explicitly enabled at deployment.
Changing the Treasury recipient does not implicitly enable the replacement or
revoke the previous recipient; those transfer permissions remain explicit
governance decisions and remain available after Diamond-cut finalization.

This is the FWA.fun transfer-lock pattern adapted to collision-resistant Diamond
transient slots and exact protocol escrow/claim movements:

- [FWA token transfer allowance and `_afterTokenTransfer`](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWAToken.sol#L382-L425)
- [FWA transfer-lock tests](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/test/FWAToken.t.sol#L185-L210)
- [Pinned Solady revision](https://github.com/Vectorized/solady/tree/166f85b9576f311446b0f9b3082565bbe0c17af5)

The restriction applies to underlying POTATO ERC-20 movement. Standard Uniswap
v4 ERC-6909 currency claims and third-party wrappers are different assets whose
transfers do not invoke POTATO. They can represent POTATO exposure, but they are
not underlying POTATO balances and cannot be intercepted by its transfer hook.

## Canonical v4 pool and hook

The PoolKey is native ETH as currency0, the Burntato Diamond as currency1, zero
native LP fee, the configured tick spacing, and the exact hook. The hook binds
immutably to that POTATO address, PoolManager, and tick spacing. It rejects
foreign initialization, foreign PoolKeys, exact-output swaps, and unauthorized
liquidity addition.

Market infrastructure and reserves can be corrected through `configureMarket`
before launch. After launch, structural reconfiguration and a second launch
revert. The initial position NFT is held by
`0x000000000000000000000000000000000000dEaD`.

The hook follows FWA.fun's bilateral revenue-capture path:

- [FWA hook fee mechanics](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWATokenHook.sol#L205-L302)
- [FWA initialization-squatting regression](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/test/FWATokenHookSquat.t.sol)

Buy fees are taken in POTATO, internally converted once, and the realized ETH is
sent directly to `feeAddress`. Sell fees are taken in ETH and sent directly to
the same address. `HookFee` and `Trade` are hook events; `MarketConfigured` and
`MarketLaunched` are Diamond events. There is no Diamond hook-revenue receiver
or hook-fee claim.

Hook ownership may update `feeAddress` and `feeBps` before or after launch and
before or after Diamond finalization. The fee is bounded to 10,000 BPS. Market
frontends should read it from the hook instead of assuming the 1% genesis
default. The receiver cannot be zero, the hook, POTATO Diamond, or PoolManager;
those are system sinks, not Treasury destinations.

External buys are disabled by default. `setExternalBuysEnabled(bool)` is an
owner-only hook control that remains repeatable after launch and Diamond
finalization. Disabling buys does not disable exact-input POTATO sells. The
Diamond's canonical buyback is the sole privileged buy path and pays no hook
fee.

## Permissionless buyback

Call `IBuyback.buyback()` without parameters after market launch. It selects the
governed gross slice from `buybackReserveEth`, pays the caller reward, and swaps
the remainder as exact-input native ETH for POTATO at the extreme Uniswap price
limit. There is intentionally no caller-provided quote, slippage, deadline, or
recipient parameter. Partial fills restore unspent input to the reserve.

PoolManager sends output directly to the current `IClaims.treasuryRecipient()`.
The hook exact-authorizes that transfer even when the current recipient is not a
distributor, and the buyback leaves `externalBuysEnabled` unchanged. Observe
`BuybackExecuted` for gross slice, actual ETH spent, POTATO bought, caller
reward, and final reserve. The default cap, reward, and delay are 2 ETH, 50 BPS,
and one block.

This is the bounded Burntato adaptation of FWA's production buyback path:

The reward is gross-slice based, not fill based. A terminal-price partial fill
can therefore pay the configured reward even when little or no ETH is consumed
by the swap. Integrators should expose the current cap, reward, delay, and
reserve so governance and users can evaluate that explicit tradeoff.

- [FWA permissionless buyback and callback](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWAToken.sol#L310-L383)

## Claims and recipients

Winner and Recovery claims accept an explicit external recipient and are
pull-based. Treasury ETH and POTATO claims always use the configured Diamond
Treasury recipient. Protocol custody addresses are rejected as external claim
recipients. Hook revenue bypasses these claims and arrives directly at the
hook's configured Treasury wallet.
