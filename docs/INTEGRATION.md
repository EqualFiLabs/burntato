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
- `IClaims.winnerClaimed()`, `recoveryClaimed()`, and
  `claimableRecovery()` for account claim state;
- Treasury claimable ETH and POTATO views; and
- `IMarket.marketConfig()`, `canonicalPoolKey()`, `marketState()`, and
  `marketReady()`;
- `IPotatoToken.isDistributor(account)` for the governed transfer allowlist; and
- `IBuyback.buybackConfig()`, `buybackReserveEth()`, and `lastBuybackBlock()`;
  and
- `ITreasuryRewards.rewardAllocator()`, `treasuryRewardsReserved()`,
  `rewardSchedule()`, and `nextTreasuryRewardBudget()`.

`Round.deadline` is authoritative for the active countdown. Each successful
purchase sets it from that purchase's timestamp using the round's snapshotted
`roundTimeout`, `roundTimeoutDecay`, `minimumRoundTimeout`, and pre-increment
`purchaseIndex`. Integrators should display the stored deadline rather than
reconstructing it from transaction ordering. A new round restarts at the
initial timeout; after the configured floor is reached, later purchases keep
resetting to that floor.

The canonical hook is a separate administered contract. Read `owner()`,
`token()`, `poolManager()`, `tickSpacing()`, `feeAddress()`, `feeBps()`,
`operatorRewardsRouter()`, `operatorRewardShareBps()`, `deploymentBlock()`, and
`externalBuysEnabled()` from the hook itself.

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

Genesis reserves the configured POTATO allocation in Diamond custody. The
initial square-root price must equal `TickMath.getSqrtPriceAtTick(tickUpper)`,
making the locked launch position entirely POTATO-sided; `launchMarket()` is
nonpayable and does not consume Treasury ETH. The local default allocation is
100 million POTATO. Because external buys start closed, the first protocol
buybacks add ETH-side pool inventory before ordinary users may buy, while POTATO
holders may sell whenever the pool has ETH available.

The hook follows FWA.fun's bilateral revenue-capture path:

- [FWA hook fee mechanics](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWATokenHook.sol#L205-L302)
- [FWA initialization-squatting regression](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/test/FWATokenHookSquat.t.sol)

Buy fees are taken in POTATO and internally converted once; sell fees are taken
in ETH. Both realized native fees are split between the standalone Operator
router and `feeAddress`, with division dust assigned to `feeAddress`. `HookFee`,
`HookFeeAllocated`, and `Trade` are hook events. There is no Diamond hook-fee
claim.

Hook ownership may update `feeAddress`, `feeBps`, and the atomic Operator router
and share configuration before or after launch and Diamond finalization. Both
BPS values are bounded to 10,000. The Operator path is disabled only as
`(address(0), 0)`; an enabled router must be deployed and distinct from known
system and Treasury destinations.

External buys are disabled by default. `setExternalBuysEnabled(bool)` is an
owner-only hook control that remains repeatable after launch and Diamond
finalization. Disabling buys does not disable exact-input POTATO sells. The
Diamond's canonical buyback is the sole privileged buy path and pays no hook
fee.

## Statics Operator rewards router

`BurntatoOperatorRewardsRouter` is a standalone, immutable integration contract;
it does not modify or custody funds inside Statics. Its fixed Robinhood
dependencies are the Operators NFT
`0xad5E9F96A91D1A6F550580b157af2068A0e8F0BE` and Activation Registry
`0xfC62e99CaE93878f83801f3d6Bb4f1762E720B30`.

Both the hook and `buyPotato()` send native revenue to this one router. Clients
can read the fixed Diamond binding through `purchaseOperatorRewardsRouter()`;
purchase routing emits `OperatorPurchaseRevenueQueued` after the internal
Winner, Recovery, Treasury, and buyback obligations have been recorded.

- `register(operatorId)` is current-owner-only and starts at the current
  `multiplierBps` without historical rewards.
- `sync(operatorId)` is permissionless. Higher weights apply only after old
  weight accrual settles.
- `claim(operatorId, receiver)` is current-owner-only and permits an explicit
  receiver.
- `accrue()` recognizes queued and force-sent native revenue.
- `claimTreasury()` pays zero-registration and sole-forfeiture revenue to the
  Diamond's current Treasury recipient.

If `ownerOf` differs from the registered owner, or the canonical multiplier is
lower than the stored weight, synchronization invalidates the registration and
redistributes all unpaid value to the remaining registered Operators. It pays
nothing to the new owner, who must register explicitly. Because settlement is
lazy, transfer away and back to the original owner followed by restoration of
the exact stored tier before any router read cannot be distinguished from no
transfer; Statics' transfer reset and reactivation cost bound this edge case.

### Robinhood production-compatible routing

For the persistent fork, consume
`artifacts/robinhood-local/deployment.json`. The committed manifest pins the
canonical Universal Router at `0x8876789976dEcBfCbBbe364623C63652db8C0904`
and Permit2 at `0x000000000022D473030F116dDEE9F6B43aC78BA3`.

External buys remain closed after deployment. Once hook governance enables
them, native ETH-to-POTATO exact-input buys use the Universal Router `V4_SWAP`
command with `SWAP_EXACT_IN_SINGLE`, `SETTLE_ALL`, and `TAKE_ALL`. POTATO sells
prepend an exact-amount Permit2 `PermitSingle` using `PERMIT2_PERMIT` with the
Universal Router allow-revert flag (`0x8a`), followed by `V4_SWAP`. If another
caller submits the public Permit2 signature first, the duplicate permit may
revert without blocking the swap, which consumes the already-installed exact
allowance. Robinhood's pinned Router single-hop payload includes
`minHopPriceX36`; do not

For router traffic, `HookFee.sender` and `Trade.sender` are the Universal Router,
not the user's wallet. User identity comes from the submitted transaction and
Permit2 owner. Successful transactions must leave the Permit2 exact allowance
and POTATO transient PoolManager allowance at zero.

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

## Treasury reward schedules

`ITreasuryRewards.allocateTreasuryRewards(amount, firstRoundId, roundCount)` is
callable only by the current reward allocator. It checks the allocator's POTATO
balance and atomically moves the exact amount through the Diamond's one-shot
protocol-transfer path; no ERC-20 approval is required and no POTATO is minted.
`firstRoundId` must be later than the current activated round.

Schedules expose exact `perRound` and `firstRoundRemainder` fields. Multiple
schedules add together. `nextTreasuryRewardBudget()` reports only the next
unactivated round in constant time; activated history is read through
`IGame.getRound()`. Round fields distinguish base emission from Treasury-funded
budget, maximum, earned, remaining, emitted, and released values.

The current allocator may call `cancelTreasuryRewards(scheduleId)` once while a
schedule still has unactivated value. The function releases only that future
amount into `treasuryPotatoAvailable()`; it does not return tokens directly or
change the active round. Settlement similarly releases unused active-round
budget. `TreasuryRewardsAllocated`, `TreasuryRewardsCanceled`,
`TreasuryRewardRoundActivated`, `TreasuryRewardFinalized`, and
`TreasuryRewardReleased` provide the accounting event stream.

## Claims and recipients

Winner and Recovery claims accept an explicit external recipient and are
pull-based. Treasury ETH and POTATO claims always use the configured Diamond
Treasury recipient. Protocol custody addresses are rejected as external claim
recipients. Hook revenue bypasses these claims and arrives directly at the
hook's configured Treasury wallet. `winnerClaimed(roundId)` and
`recoveryClaimed(roundId, account)` report completion status.

`claimableRecovery(roundId, account)` is intentionally order- and
state-dependent. Before the final outstanding commitment, it returns the
ordinary floored pro-rata amount. Once that account's complete commitment would
close the round's claimed weight, it returns `recoveryPool - recoveryPaid`,
including all prior rounding remainder. It returns zero when the round is
unsettled, has no aggregate commitment, the account did not commit, the account
already claimed, or the account has a valid ordinary claim that rounds to zero.
Use `recoveryClaimed` to distinguish the last two zero-valued states.
