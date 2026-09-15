import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  assertConfig,
  buildCurve,
  buildSingleRange,
  emissionForRound,
  executeBuybackReserve,
  liquidationValue,
  potatoForLiquidationValue,
  protocolBuyExactEth,
  publicSellExactPotato,
  simulateScenario,
  sponsorshipBreakEven,
  stateAtPoolEth,
  stateAtPotatoOut,
  ticketRound,
} from "./model.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(await readFile(join(here, "config.json"), "utf8"));
assertConfig(config);
const curves = config.curves.map((curve) => buildCurve(config, curve));
const baselineCurve = buildSingleRange(config);

const fixed = (value, digits = 6) => Number(value).toFixed(digits);
const sig = (value, digits = 6) => Number(value).toPrecision(digits);
const integer = (value) => Math.round(value).toLocaleString("en-US");
const percent = (fraction, digits = 2) => `${fixed(fraction * 100, digits)}%`;
const csv = (value) => {
  if (typeof value === "number") return Number.isFinite(value) ? String(value) : "";
  const string = String(value ?? "");
  return /[",\n]/.test(string) ? `"${string.replaceAll('"', '""')}"` : string;
};

function curveMilestones(curve) {
  return config.milestonesPotato.map((potatoOut) => {
    const state = stateAtPotatoOut(curve, potatoOut);
    return {
      curve: curve.name,
      potatoOut,
      inventorySoldPercent: potatoOut / curve.inventory,
      poolEth: state.poolEth,
      spotEthPerPotato: state.spotEthPerPotato,
      mark100kEth: state.spotEthPerPotato * 100_000,
      averageEthPerPotato: state.poolEth / potatoOut,
    };
  });
}

function bootstrapMilestones(curve) {
  return config.bootstrapEthMilestones.map((eth) => {
    const state = stateAtPoolEth(curve, eth);
    return {
      curve: curve.name,
      poolEth: state.poolEth,
      potatoOut: state.potatoOut,
      inventorySoldPercent: state.potatoOut / curve.inventory,
      spotEthPerPotato: state.spotEthPerPotato,
      mark100kEth: state.spotEthPerPotato * 100_000,
    };
  });
}

function roundFlows() {
  const rows = [];
  for (const grabs of config.flowRoundGrabCounts) {
    const tickets = ticketRound(grabs, config.game);
    const emission = emissionForRound(grabs, 1, config.game);
    for (const soldShare of config.flowEmissionSellShares) {
      const soldPotato = emission.emittedPotato * soldShare;
      rows.push({
        grabs,
        ticketRevenueEth: tickets.totalRevenueEth,
        lastGrabPriceEth: tickets.pricesEth.at(-1),
        nextGrabPriceEth: tickets.nextPriceEth,
        winnerEth: tickets.currentWinnerEth,
        nextWinnerEth: tickets.nextWinnerEth,
        recoveryEth: tickets.recoveryEth,
        treasuryEth: tickets.treasuryEth,
        buybackReserveEth: tickets.buybackEth,
        operatorEth: tickets.operatorEth,
        emittedPotato: emission.emittedPotato,
        emissionSoldShare: soldShare,
        emittedSoldPotato: soldPotato,
        flowBalanceEthPerPotato: tickets.buybackEth / soldPotato,
        flowBalance100kMarkEth: tickets.buybackEth / soldPotato * 100_000,
      });
    }
  }
  return rows;
}

function sellStress(curve, withBuyback) {
  let state = stateAtPoolEth(curve, 50);
  const checkpoints = [];
  const tickets = ticketRound(10, config.game);
  const emissions = emissionForRound(10, 1, config.game);
  let reserve = 0;
  let treasuryPotato = 0;
  let userEth = 0;

  for (let round = 1; round <= 100; round += 1) {
    const sell = publicSellExactPotato(curve, state, emissions.emittedPotato, config.market.hookFeeBps);
    state = sell.state;
    userEth += sell.userEth;
    if (withBuyback) {
      reserve += tickets.buybackEth;
      const buyback = executeBuybackReserve(curve, state, reserve, config.market);
      state = buyback.state;
      reserve = buyback.remainingReserveEth;
      treasuryPotato += buyback.potatoReceived;
    }
    if ([1, 5, 10, 25, 50, 100].includes(round)) {
      checkpoints.push({
        curve: curve.name,
        withBuyback,
        round,
        poolEth: state.poolEth,
        potatoOut: state.potatoOut,
        spotEthPerPotato: state.spotEthPerPotato,
        mark100kEth: state.spotEthPerPotato * 100_000,
        cumulativeUserSaleEth: userEth,
        treasuryPotato,
      });
    }
  }
  return checkpoints;
}

function whaleResistance(curve) {
  const state = stateAtPoolEth(curve, 50);
  const incumbentPotato = potatoForLiquidationValue(curve, state, 5, config.market.hookFeeBps);
  return [0.25, 0.5, 0.75].map((targetShare) => {
    const requiredPotato = incumbentPotato * targetShare / (1 - targetShare);
    const buyState = stateAtPotatoOut(curve, Math.min(curve.inventory, state.potatoOut + requiredPotato / 0.99));
    const grossPotato = buyState.potatoOut - state.potatoOut;
    const feePotato = grossPotato * config.market.hookFeeBps / 10_000;
    const finalState = stateAtPotatoOut(curve, buyState.potatoOut - feePotato);
    return {
      curve: curve.name,
      bootstrapPoolEth: 50,
      incumbentPotato,
      incumbentLiquidationValueEth: liquidationValue(curve, state, incumbentPotato, config.market.hookFeeBps),
      targetRecoveryShare: targetShare,
      requiredNetPotato: grossPotato - feePotato,
      requiredBuyEth: buyState.poolEth - state.poolEth,
      hookFeeEth: buyState.poolEth - finalState.poolEth,
      resultingSpotEthPerPotato: finalState.spotEthPerPotato,
    };
  });
}

const milestoneRows = curves.flatMap(curveMilestones);
const bootstrapRows = curves.flatMap(bootstrapMilestones);
const flowRows = roundFlows();
const stressRows = curves.flatMap((curve) => [sellStress(curve, false), sellStress(curve, true)]).flat();
const whaleRows = curves.flatMap(whaleResistance);
const dynamicRuns = curves.flatMap((curve) => config.dynamicScenarios.map((scenario) => simulateScenario(config, curve, scenario)));
const breakEven = sponsorshipBreakEven(config, 10);
const baselineMilestones = curveMilestones(baselineCurve);
const baselineBootstrap = bootstrapMilestones(baselineCurve);

const results = {
  modelVersion: 1,
  config,
  curveSummaries: curves.map((curve) => ({
    name: curve.name,
    positionCount: curve.positions.length,
    initialSpotEthPerPotato: stateAtPotatoOut(curve, 0).spotEthPerPotato,
    maximumPoolEth: curve.maximumEth,
  })),
  baseline: {
    summary: {
      name: baselineCurve.name,
      positionCount: baselineCurve.positions.length,
      initialSpotEthPerPotato: stateAtPotatoOut(baselineCurve, 0).spotEthPerPotato,
      maximumPoolEth: baselineCurve.maximumEth,
    },
    milestones: baselineMilestones,
    bootstrapMilestones: baselineBootstrap,
  },
  milestones: milestoneRows,
  bootstrapMilestones: bootstrapRows,
  roundFlows: flowRows,
  sellStress: stressRows,
  recoveryWhaleResistance: whaleRows,
  sponsorshipBreakEven: breakEven,
  dynamicRuns,
};

await writeFile(join(here, "results.json"), `${JSON.stringify(results, null, 2)}\n`);

const traceHeaders = [
  "curve", "scenario", "round", "grabs", "openingWinnerEth", "openingRecoveryEth", "visibleFutureEth",
  "ticketRevenueEth", "emittedPotato", "soldPotato", "boughtPotato", "buybackSpendEth", "buybackPotato",
  "publicBuyEth", "publicEnabled", "poolEth", "poolPotatoOut", "spotEthPerPotato", "committedCurrentPotato",
  "committedNextPotato", "recoveryPaidEth", "modeledSupplyPotato", "treasuryPotato", "treasuryEth", "operatorEth",
];
const traceLines = [traceHeaders.join(",")];
for (const run of dynamicRuns) {
  for (const row of run.traces) {
    traceLines.push(traceHeaders.map((header) => csv(header === "curve" ? run.curve : header === "scenario" ? run.scenario : row[header])).join(","));
  }
}
await writeFile(join(here, "round-traces.csv"), `${traceLines.join("\n")}\n`);

const curveAt50m = milestoneRows.filter((row) => row.potatoOut === 50_000_000);
const baselineAt50m = baselineMilestones.find((row) => row.potatoOut === 50_000_000);
const baselineAt50Eth = baselineBootstrap.find((row) => Math.abs(row.poolEth - 50) < 0.01);
const dynamicSummary = dynamicRuns.map(({ traces, ...summary }) => summary);
const legacyEmissionGame = {...config.game, roundEmissionBudgetPotato: 100_000};
const launchEmissionAtTenGrabs = emissionForRound(10, 1, config.game).emittedPotato;
const legacyEmissionAtTenGrabs = emissionForRound(10, 1, legacyEmissionGame).emittedPotato;

const report = `# POTATO market-depth and game-economics model

Generated from \`config.json\` by \`generate-report.mjs\`. This is decision support, not a forecast or an implementation specification.

## Executive conclusion

The current single-range launch curve is too cheap for the intended recovery game: half of its 100 million launch inventory costs only **${fixed(baselineAt50m.poolEth, 2)} ETH**. A six-band layout materially improves scarcity, and **the aggressive curve is the selected launch profile**. It preserves the opening quote, reaches about **${fixed(curveAt50m.find((row) => row.curve === "aggressive").poolEth, 2)} ETH absorbed at 50 million POTATO**, and marks 100,000 POTATO at about **${fixed(curveAt50m.find((row) => row.curve === "aggressive").mark100kEth, 2)} ETH** there. The scarcity curve remains an upper sensitivity bound, but its ${fixed(curveAt50m.find((row) => row.curve === "scarcity").poolEth, 2)} ETH half-inventory cost is too aggressive for the initial launch.

This recommendation is conditional. The model says curve shape alone does not create durable price support: ticket activity, vesting, emission selling, recovery burns, and timely execution of the buyback reserve dominate the path. Public buys remain disabled during bootstrap; only Treasury buybacks create initial ETH depth. The public-buy threshold in scenarios is an analysis trigger, while the deployed protocol still requires an intentional administrative enablement decision.

## Modelled protocol facts

- Launch inventory: ${integer(config.market.initialInventoryPotato)} POTATO; modeled as 56 permanent Uniswap v4 positions across six bands.
- Opening pool tick: ${config.market.initialPoolTick}; opening spot quote is ${sig(curves[0] && stateAtPotatoOut(curves[0], 0).spotEthPerPotato)} ETH per POTATO.
- Ticket price: ${fixed(config.game.startingGrabPriceEth, 6)} ETH, increasing ${percent(config.game.priceIncreaseBps / 10_000, 0)} after each grab.
- The first ticket of every round goes entirely to the next round Winner reserve. Later tickets split ${percent(config.game.winnerBps / 10_000, 0)} current Winner, ${percent(config.game.nextRoundWinnerBps / 10_000, 0)} next Winner, ${percent(config.game.recoveryBps / 10_000, 0)} Recovery, ${percent(config.game.treasuryBps / 10_000, 0)} Treasury, ${percent(config.game.buybackBps / 10_000, 0)} buyback, and ${percent(config.game.operatorPurchaseBps / 10_000, 0)} Operators.
- Round emission budget: ${integer(config.game.roundEmissionBudgetPotato)} POTATO. Each holder opportunity earns ${percent(config.game.emissionStepBps / 10_000, 0)} of remaining emissions multiplied by its vesting fraction.
- Emission sensitivity: ten fully vested holder opportunities emit ${integer(launchEmissionAtTenGrabs)} POTATO at the selected 10,000 budget versus ${integer(legacyEmissionAtTenGrabs)} POTATO at the prior 100,000 budget. The larger budget is retained only as stress context.
- Recovery settlement destroys ${percent(config.game.recoveryBurnBps / 10_000, 0)} of committed POTATO and transfers ${percent(config.game.recoveryTreasuryBps / 10_000, 0)} to Treasury.
- Public swap hook fee: ${percent(config.market.hookFeeBps / 10_000, 0)}, split ${percent(config.market.hookTreasuryShareBps / 10_000, 0)} Treasury / ${percent((10_000 - config.market.hookTreasuryShareBps) / 10_000, 0)} Operators. Protocol buybacks bypass that fee, send POTATO to Treasury, and leave their ETH in the pool.

## Candidate curve comparison

### Current baseline

| Geometry | ETH absorbed at 50M out | 50M spot (ETH/POTATO) | POTATO out after 50 ETH | 50 ETH mark for 100k |
|---|---:|---:|---:|---:|
| current single range | ${fixed(baselineAt50m.poolEth, 3)} | ${sig(baselineAt50m.spotEthPerPotato)} | ${integer(baselineAt50Eth.potatoOut)} | ${fixed(baselineAt50Eth.mark100kEth, 4)} ETH |

The baseline uses the current one-position range [${config.market.currentSingleRange.tickLower}, ${config.market.currentSingleRange.tickUpper}] with POTATO as token1. It establishes the relative claim above; it is not mixed into the six-band scenario sweep.

### Six-band candidates

| Curve | ETH absorbed at 10M out | ETH absorbed at 50M out | 50M spot (ETH/POTATO) | 50M mark for 100k | Maximum theoretical ETH |
|---|---:|---:|---:|---:|---:|
${curves.map((curve) => {
  const at10 = milestoneRows.find((row) => row.curve === curve.name && row.potatoOut === 10_000_000);
  const at50 = milestoneRows.find((row) => row.curve === curve.name && row.potatoOut === 50_000_000);
  return `| ${curve.name} | ${fixed(at10.poolEth, 3)} | ${fixed(at50.poolEth, 3)} | ${sig(at50.spotEthPerPotato)} | ${fixed(at50.mark100kEth, 3)} ETH | ${fixed(curve.maximumEth, 1)} |`;
}).join("\n")}

The maximum is a mathematical endpoint of the permanent tail, not a realistic fundraising target. Near-boundary quotes become increasingly sensitive and should not be interpreted as attainable proceeds.

### Inventory milestones

| Curve | POTATO out | Inventory out | Pool ETH | Spot ETH/POTATO | 100k mark |
|---|---:|---:|---:|---:|---:|
${milestoneRows.map((row) => `| ${row.curve} | ${integer(row.potatoOut)} | ${percent(row.inventorySoldPercent, 1)} | ${fixed(row.poolEth, 3)} | ${sig(row.spotEthPerPotato)} | ${fixed(row.mark100kEth, 3)} ETH |`).join("\n")}

### Treasury bootstrap depth

| Curve | Treasury ETH bought | POTATO acquired | Inventory out | Spot ETH/POTATO | 100k mark |
|---|---:|---:|---:|---:|---:|
${bootstrapRows.map((row) => `| ${row.curve} | ${fixed(row.poolEth, 0)} | ${integer(row.potatoOut)} | ${percent(row.inventorySoldPercent, 2)} | ${sig(row.spotEthPerPotato)} | ${fixed(row.mark100kEth, 4)} ETH |`).join("\n")}

## Ticket revenue versus emission sell pressure

The flow-balance mark is the buyback allocation divided by newly emitted POTATO offered for sale. It is not the AMM price and ignores inventory, prior liquidity, recovery burning, external demand, and price impact. It exposes the key nonlinear relationship: ticket revenue grows geometrically while emissions approach a fixed ceiling.

| Grabs | Ticket revenue | Last grab | Buyback reserve | Full-vest emission | Emission sold | Flow-balance 100k mark |
|---:|---:|---:|---:|---:|---:|---:|
${flowRows.map((row) => `| ${row.grabs} | ${fixed(row.ticketRevenueEth, 6)} ETH | ${fixed(row.lastGrabPriceEth, 6)} ETH | ${fixed(row.buybackReserveEth, 6)} ETH | ${integer(row.emittedPotato)} | ${percent(row.emissionSoldShare, 0)} | ${fixed(row.flowBalance100kMarkEth, 4)} ETH |`).join("\n")}

Five-grab rounds cannot materially support price through buybacks alone. At ten grabs, the buyback is still only ${fixed(ticketRound(10, config.game).buybackEth, 6)} ETH against ${integer(emissionForRound(10, 1, config.game).emittedPotato)} maximum emitted POTATO. The intended flywheel becomes meaningfully stronger only when a round reaches the steeper portion of the ticket curve or when recovery permanently removes a large part of emissions.

## Emission-sale stress after a 50 ETH Treasury bootstrap

Each stress path starts with 50 ETH in the pool, runs 100 identical ten-grab/full-vesting rounds, and sells every newly emitted POTATO. “With buyback” executes the whole available reserve after each sale; it assumes keepers act and enough blocks elapse. This is deliberately punitive and does not include recovery burning or external buys.

| Curve | Buyback | Round | Pool ETH | POTATO out | 100k mark | Cumulative seller ETH |
|---|---|---:|---:|---:|---:|---:|
${stressRows.map((row) => `| ${row.curve} | ${row.withBuyback ? "yes" : "no"} | ${row.round} | ${fixed(row.poolEth, 3)} | ${integer(row.potatoOut)} | ${fixed(row.mark100kEth, 4)} ETH | ${fixed(row.cumulativeUserSaleEth, 3)} |`).join("\n")}

## Recovery whale-resistance illustration

At 50 ETH of bootstrap depth, an incumbent is assigned enough POTATO to have a 5 ETH liquidation value. The table estimates the ETH needed by a new buyer to acquire a target share of total Recovery commitments. It assumes no other buyers, no intervening sells, and immediate public purchase availability, so it is a lower-complexity comparison rather than a game-theoretic forecast.

| Curve | Incumbent POTATO | Target share | Required net POTATO | Buyer ETH | Resulting 100k mark |
|---|---:|---:|---:|---:|---:|
${whaleRows.map((row) => `| ${row.curve} | ${integer(row.incumbentPotato)} | ${percent(row.targetRecoveryShare, 0)} | ${integer(row.requiredNetPotato)} | ${fixed(row.requiredBuyEth, 3)} | ${fixed(row.resultingSpotEthPerPotato * 100_000, 3)} ETH |`).join("\n")}

## Behavioral scenario sweep

These scenarios use explicit response coefficients from \`config.json\`; they are **not predictions**. Grab counts respond logarithmically to current and visible future pots, public buying starts only after its configured ETH-depth threshold, and Recovery competition targets a fraction of the next expected Recovery pot. Scenario traces are in \`round-traces.csv\`.

| Scenario | Base/max grabs | Vesting | Emissions sold | Public threshold | Promotion funding |
|---|---:|---:|---:|---:|---|
${config.dynamicScenarios.map((scenario) => {
  const promotion = scenario.sponsorships.length === 0
    ? "none"
    : scenario.sponsorships.map((item) => `R${item.round}: ${item.winnerEth}+${item.recoveryEth} ETH`).join("; ");
  return `| ${scenario.name} | ${scenario.baseGrabs}/${scenario.maximumGrabs} | ${percent(scenario.vestingFraction, 0)} | ${percent(scenario.emissionSellShare, 0)} | ${fixed(scenario.publicEnablePoolEth, 0)} ETH | ${promotion} |`;
}).join("\n")}

In every dynamic path, the simulator sells the configured emission share, makes permissionless buyback calls until the round's reserve is exhausted, and only then allows modeled public demand if the threshold has been crossed. This assumes enough blocks and willing keepers; it is intentionally more operationally favorable than an unserviced reserve.

| Curve | Scenario | Rounds | Grabs | Ticket revenue | Final pool ETH | Final 100k mark | Emitted | Burned | Public enabled |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
${dynamicSummary.map((row) => `| ${row.curve} | ${row.scenario} | ${row.rounds} | ${row.totalGrabs} | ${fixed(row.totalTicketRevenueEth, 2)} | ${fixed(row.finalPoolEth, 2)} | ${fixed(row.final100kMarkEth, 3)} ETH | ${integer(row.totalEmittedPotato)} | ${integer(row.burnedPotato)} | ${row.publicEnabled ? `round ${row.firstPublicRound}` : "no"} |`).join("\n")}

### Promotion economics

A 5 ETH Winner plus 5 ETH Recovery sponsorship costs 10 ETH. Looking only at the direct ${percent(config.game.treasuryBps / 10_000, 0)} Treasury share of eligible ticket purchases, it requires approximately ${fixed(breakEven.ticketRevenueIgnoringFirstPurchaseEth, 2)} ETH of eligible revenue to repay. Under a single ${fixed(config.game.startingGrabPriceEth, 3)} ETH / ${percent(config.game.priceIncreaseBps / 10_000, 0)} price ladder, direct Treasury receipts first exceed 10 ETH at grab ${breakEven.grabsForDirectTreasuryShare}; cumulative ticket revenue is ${fixed(breakEven.ticketRevenueAtBreakEvenEth, 2)} ETH and that grab alone costs ${fixed(breakEven.lastTicketPriceEth, 2)} ETH. That arithmetic is not a recommendation to expect a ${breakEven.grabsForDirectTreasuryShare}-grab round: it demonstrates that direct ticket revenue alone is a demanding sponsorship-recovery mechanism.

The business case for sponsorship therefore depends on the combined system: higher ticket volume, Treasury POTATO acquired by buybacks, hook revenue after public opening, Recovery burns, and the residual ETH depth owned by the permanently locked LP. None of those should be counted as realized Treasury profit without defining who can monetize them and under what governance policy.

## Recommendation

1. Launch with the fixed **aggressive** profile; retain **scaled-statics** as the downside comparison and **scarcity** as the upside/stress bound.
2. Use a staged public-buy gate based on observed sell capacity and fork quotes, not merely a round number. Test at least 25, 50, and 100 ETH of protocol-created depth.
3. Treat keeper execution as part of launch readiness. A funded buyback reserve does nothing until \`buyback()\` is called; the model's “with buyback” paths assume prompt execution.
4. Establish operational limits for promotional funding. A 10 ETH headline round can generate attention, but its direct Treasury break-even requires extreme ticket activity. Model sponsorship as acquisition spend, not guaranteed recoupment.
5. Before deployment, reproduce the selected quotes on a Robinhood mainnet fork and measure gas for minting 56 positions. Compare continuous-model quotes with v4 execution around band crossings.

## What the model does not establish

- It does not predict player counts, vesting time, sell propensity, sponsorship conversion, or Recovery competition. Those are configurable sensitivities.
- It uses continuous concentrated-liquidity equations with JavaScript floating-point numbers. Solidity/v4 integer rounding, tick crossing, hook execution, routing, slippage limits, and gas are not simulated.
- It assumes the six-band positions remain permanently locked and ignores any migration, emergency intervention, or alternate venue.
- It assumes fee-free Treasury buybacks and a 1% public hook fee according to the current source behavior. It does not include unrelated router or base-pool fees.
- It assumes sell-first or buy-first round ordering. Real public markets introduce adversarial ordering and MEV after buys are enabled. Predictable buybacks without effective slippage protection must be tested separately.
- It values Recovery commitments using immediate AMM liquidation value only; players may value winning probability, future POTATO scarcity, and sunk emission cost differently.
- Supply accounting includes the 100 million launch inventory plus emissions minus burns. It does not impose a hard global cap because round emissions can increase total supply.
- It does not express USD values or assume an ETH/USD price.

## Validation performed

- Configuration validation requires aligned and ordered ticks, positive position counts, exactly 100% inventory allocation, and exactly 100% later-ticket revenue allocation.
- Invariant tests cover 56-position construction, inventory conservation, monotonic price/depth, POTATO/ETH inverse round trips, hook-fee direction, buyback reserve conservation and chunking, ticket splits, and emission arithmetic.
- The nested-position implementation was cross-checked against the committed Statics launch model at its original tick geometry; the small remaining difference at a displayed USD milestone is explained by that report evaluating the exact USD price while this check evaluated the nearest aligned tick.
- Generated outputs are deterministic: rerunning the generator from unchanged inputs produces identical report, JSON, and CSV hashes.

## Reproduction

From this directory:

\`node model.test.mjs\`

\`node generate-report.mjs\`

Inputs are in \`config.json\`; machine-readable results are in \`results.json\`; every dynamic round is in \`round-traces.csv\`.
`;

await writeFile(join(here, "report.md"), report);
console.log(`Generated ${dynamicRuns.length} scenario runs, ${traceLines.length - 1} trace rows, and report.md`);
