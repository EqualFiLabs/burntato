# Integration guide

## Diamond interfaces

Integrators use the `BurntatoDiamond` address for gameplay, POTATO ERC-20 and
Permit operations, wrapping, Recovery, settlement, claims, reserve views, and
governance.
Use the EIP-2535 loupe to resolve the installed facet for each selector.

Important state reads include:

- `IGame.currentRoundId()`, `getRound()`, `currentEarnedEmission()`, and
  `winnerReserveEth()`;
- `IGovernance.protocolConfig()`, `foundationConfigured()`, purchase
  initialization, authority, guardian, pause, and finalization views;
- `IRecovery.recoveryCommitment()`, `totalRecoveryCommitment()`,
  `recoveryReserveEth()`, and `stalledRecoveryWithdrawalAt()`;
- `IClaims.winnerClaimed()`, `recoveryClaimed()`, and
  `claimableRecovery()` for account claim state;
- Treasury claimable ETH and POTATO views;
- `IPotatoToken.underlying()`, `backingBalance()`, `publicWrapCap()`,
  `publicWrapOutstanding()`, `availablePublicWrapCapacity()`, `rewardReserve()`,
  `availableRewardInventory()`, `nextRoundFundingStatus()`, and
  `isDistributor(account)`; and
- `IBuyback.buybackMarket()`, `buybackConfig()`, `buybackReserveEth()`, and
  `lastBuybackBlock()`; and
- `ITreasuryRewards.rewardAllocator()`, `treasuryRewardsReserved()`,
  `rewardSchedule()`, and `nextTreasuryRewardBudget()`.

`Round.deadline` is authoritative for the active countdown. Each successful
purchase sets it from that purchase's timestamp using the round's snapshotted
`roundTimeout`, `roundTimeoutDecay`, `minimumRoundTimeout`, and pre-increment
`purchaseIndex`. Integrators should display the stored deadline rather than
reconstructing it from transaction ordering. A new round restarts at the
initial timeout; after the configured floor is reached, later purchases keep
resetting to that floor.

`fundWinnerReserve(targetRoundId)` and
`fundRecoveryReserve(targetRoundId)` permissionlessly add positive native value
to any future round's tracked reserves even while the protocol is paused.
`fundRoundReserves(targetRoundId, winnerAmount, recoveryAmount)` funds either or
both in one transaction when their exact sum equals `msg.value`. Active and past
targets revert. `roundReserves(roundId)` returns the named round's two pending
amounts. `roundFunding(roundId)` returns those same aggregate amounts followed
by the Winner and Recovery portions contributed through the permissionless
funding entry points. Subtract sponsored from aggregate to display the
protocol/game-funded remainder. `winnerReserveEth()` and `recoveryReserveEth()`
return aggregate future liabilities. The named reserves move into `Round.winnerPool` and
`Round.recoveryPool` only when that round activates. Integrators should index
`WinnerReserveFunded`, `NextRoundWinnerFunded`, `WinnerReserveApplied`,
`RecoveryReserveFunded`, and `RecoveryReserveApplied`; a plain native transfer
is deliberately untracked. The genesis seed, first-Grab allocation, and
configured later-Grab allocation are not sponsorship. Funding is irreversible
and does not snapshot a distant round's configuration.

The first Grab of every round contributes its complete price to the following
round's Winner reserve. The configured Winner, next-Winner, Recovery, Treasury,
buyback, and Operator BPS split applies only from the second Grab onward:
25% / 5% / 30% / 15% / 10% / 15%. Before the first Grab, check purchase
initialization, pause and `nextRoundFundingStatus()`. The complete snapshotted
base reward budget must be funded; an insufficient reserve reverts payment.

Holder rewards transfer existing base and Treasury inventory. The next purchase
finalizes the outgoing opportunity; after full vesting, anyone may call
`materializeMaturedEmission()`. `currentEarnedEmission()` includes already
materialized earnings, so check `holderEmissionFinalized` for payment state.

The wrapper interfaces and removal of market/Recovery-ratio fields change the
ABI, selector manifest, and Diamond storage. Integrators must update their ABI
before connecting to this fresh-deployment package; it is not an in-place upgrade.

## POTATO behavior

POTATO is Solady ERC-20 plus EIP-2612 Permit behind the Diamond. `name`, `symbol`,
`decimals`, balances, supply, approvals, `permit`, nonces, and domain separator
follow the Solady implementation. `wrap(amount)` pulls the caller's exact
STATICS deposit and mints equal POTATO to that caller; approve STATICS to the
Diamond first. `unwrap(amount)` burns caller POTATO and returns equal STATICS
without requiring approval, including during pause. Public `burn(amount)` and
unbacked mint selectors are removed.

The initial public wrap cap is 2,000,000 POTATO. Wrapping increases
`publicWrapOutstanding`; every public or Recovery redemption reduces it by
`min(amount, publicWrapOutstanding)` regardless of token origin. Lowering the
cap below outstanding usage blocks new wraps without preventing redemption.
`fundRewardReserve(amount)` accepts the caller's approved STATICS and mints
equal POTATO only into the accounted Diamond reserve, outside public capacity.
Buybacks fund that same reserve. Backing must cover total supply; unsolicited
STATICS creates surplus without changing redemption value. Index `Wrapped`,
`Unwrapped`, `RewardReserveFunded` and `PublicWrapCapSet`.

`availableRewardInventory()` deducts the occupied unsettled round's remaining
base budget. `nextRoundFundingStatus()` returns the current holderless round
or queued next round, its required budget, available inventory and funding
status. Reserve accounting excludes Recovery escrow and Treasury inventory.

An ERC-20 approval or Permit does not make ordinary transfers valid. The
transfer hook permits only:

1. minting and burning within backed issuance and redemption;
2. transfers where either endpoint is an administered distributor;
3. transfers where either endpoint is the current protocol authority;
4. an exact protocol transfer authorized and consumed during a Diamond self-call.

All other underlying POTATO movements revert. Public transfers to or from
`address(0)` also revert. Protocol transfer, reserve-credit and Recovery-redemption
entrypoints are Diamond-self-call-only.
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

## Configured STATICS/WETH market

`IBuyback.buybackMarket()` reports the external PoolManager, WETH and exact
PoolKey. Chain-specific `statics-market-*.json` manifests pin STATICS, WETH,
PoolManager, hook runtimes, provenance and currency ordering. No POTATO pool,
hook, LP, gauge, market seed or launch selector is installed. Normal external
STATICS pool fees apply; no Burntato hook exemption is needed.

## Statics Operator rewards router

`BurntatoOperatorRewardsRouter` is a standalone, immutable integration contract;
it does not modify or custody funds inside Statics. Its fixed Robinhood Mainnet
dependencies are the Operators NFT
`0xad5E9F96A91D1A6F550580b157af2068A0e8F0BE` and Activation Registry
`0xfC62e99CaE93878f83801f3d6Bb4f1762E720B30`. Chain-specific bindings, including
testnet, are pinned in `statics-operators-robinhood-*.json`.

`buyPotato()` sends its later-Grab Operator revenue to this router. Clients
can read the fixed Diamond binding through `purchaseOperatorRewardsRouter()`;
purchase routing emits `OperatorPurchaseRevenueQueued` after the internal
Winner, Recovery, Treasury, and buyback obligations have been recorded.

- `register(operatorId)` is current-owner-only and starts at the current
  `multiplierBps` without historical rewards.
- `registerBatch(operatorIds)` applies the same registration rules atomically
  to a nonempty, strictly increasing list owned by one caller.
- `sync(operatorId)` is permissionless. Higher weights apply only after old
  weight accrual settles.
- `syncBatch(operatorIds)` applies the same permissionless synchronization
  rules atomically to a nonempty, strictly increasing registered list.
- `claim(operatorId, receiver)` is current-owner-only and permits an explicit
  receiver.
- `claimBatch(operatorIds, receiver)` claims a nonempty, strictly increasing
  list of currently owned registrations through one native transfer.
- `totalRegisteredOperators()` returns the number of registrations currently
  contributing to the Burntato Operator reward pool.
- `totalRegisteredWeight()` returns their combined activation-weighted reward
  denominator.
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

## Permissionless buyback

Call payable `IBuyback.fundBuybackReserve()` to add a positive native amount to
the tracked reserve. Any address may fund it. The call emits
`BuybackReserveFunded(funder, amount, reserveEth)`, adds the exact amount, and
does not execute a swap or change `lastBuybackBlock`. Purchase initialization,
the global protocol pause and Diamond finalization do not gate funding. A
zero-value call reverts. Sending native ETH to the Diamond's plain receive function does not credit the reserve.

Calling the standalone facet implementation directly also reverts, preventing
native funds from being stranded outside Diamond accounting.

Call `IBuyback.buyback()` without parameters while the protocol is unpaused and
with a configured STATICS/WETH market. It selects the governed gross slice
from `buybackReserveEth`, derives a swap budget that leaves room for the
configured reward, wraps ETH into WETH and swaps exact-input WETH for STATICS
at the extreme Uniswap price limit in the configured currency direction.
The swap must spend the complete requested input, and the reward is calculated from that exact spend. There is
intentionally no caller-provided quote, slippage, deadline, or recipient
parameter.

The Diamond settles real WETH with PoolManager and measures received STATICS.
Exactly equal backed POTATO is minted into its base reward reserve, outside
public capacity. Observe `BuybackExecuted` for gross slice, actual ETH spent,
STATICS acquired, POTATO reserve funded, caller reward, and final ETH reserve.
The default cap, reward, and delay are 1 ETH, 50 BPS, and one block. The reward rate cannot exceed 100 BPS.

If the swap partially fills, spends zero ETH, or returns zero STATICS,
the complete call reverts: PoolManager changes roll back, no reward is paid,
reserve is unchanged, and the cooldown is not consumed. Backing mismatch,
reserve-credit failure or rejected tip payment likewise reverts all effects.
The global pause also blocks `buyback()` before market or reserve validation. Integrators should
expose the current cap, reward, delay, reserve, and pause state; no new user
input is required.

`BootstrapBurntatoBuyback.s.sol` provides an optional two-transaction launch
helper: it funds the reserve and then calls `buyback()`. It accepts the Diamond,
funding amount in wei, and broadcaster key through
`BURNTATO_DIAMOND`, `BURNTATO_BOOTSTRAP_BUYBACK_WEI`, and `PRIVATE_KEY`. It
requires a configured market, inactive game purchases, no prior buyback, and a
positive complete-reserve amount that may exceed `maxSpend`. If the funding
transaction succeeded but the buyback transaction did not, rerunning resumes
only when the tracked reserve still equals the exact requested amount. The
helper does not activate purchases. `ExecuteBurntatoBuyback.s.sol` performs one
later execution without funding and rejects an unconfigured, paused, or
empty-reserve state.

- [FWA permissionless buyback and callback](https://github.com/token-works/fwa-relaunch/blob/1085bf6ee255d6d4d13c374a66110bb25229dc76/src/FWAToken.sol#L310-L383)

## Stalled Recovery withdrawal

`commitRecovery(amount)` moves caller POTATO into escrow for
`currentRoundId + 1` through the exact protocol-transfer path without approval.
At target settlement, all commitments are burned and equal STATICS goes to the
current Treasury. `RoundSettled` distinguishes POTATO burned and STATICS
recovered; an underlying transfer failure rolls back settlement and successor
setup. Successor underfunding does not block settlement or existing claims.

Recovery normally needs no additional UI beyond commitment and later claim.
For the exceptional holderless-predecessor state,
`stalledRecoveryWithdrawalAt(targetRoundId)` returns the shared Unix timestamp
when withdrawals open, or zero when no stalled exit is available. After that
timestamp, a committer may call `withdrawStalledRecovery(targetRoundId)` to
recover their complete commitment. The method remains callable while the global
protocol pause is active.

The exit is valid only while the target is `currentRoundId + 1`, its activated
predecessor has never had a holder, and the target has not activated. The first
predecessor purchase makes the view return zero and permanently closes the exit
for those commitments. Clients should therefore treat a nonzero deadline as a
conditional liveness escape, refresh it before submitting, and handle an
ordinary state-change revert.

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
recipients: zero, the Diamond, bound Operator router, STATICS, configured
PoolManager/WETH and configured pool hook. Recovery STATICS reaches Treasury
at settlement, independently of Treasury ETH and POTATO claims.
`winnerClaimed(roundId)` and `recoveryClaimed(roundId, account)` report completion status.

`claimableRecovery(roundId, account)` is intentionally order- and
state-dependent. Before the final outstanding commitment, it returns the
ordinary floored pro-rata amount. Once that account's complete commitment would
close the round's claimed weight, it returns `recoveryPool - recoveryPaid`,
including all prior rounding remainder. It returns zero when the round is
unsettled, has no aggregate commitment, the account did not commit, the account
already claimed, or the account has a valid ordinary claim that rounds to zero.
Use `recoveryClaimed` to distinguish the last two zero-valued states.
