import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  assertConfig,
  buildCurve,
  buildSingleRange,
  emissionForRound,
  executeBuybackReserve,
  protocolBuyExactEth,
  publicBuyExactEth,
  publicSellExactPotato,
  stateAtPoolEth,
  stateAtPotatoOut,
  ticketRound,
} from "./model.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const config = JSON.parse(await readFile(join(here, "config.json"), "utf8"));
assertConfig(config);

const near = (actual, expected, tolerance, message) => {
  assert.ok(Math.abs(actual - expected) <= tolerance, `${message}: ${actual} != ${expected}`);
};

const baseline = buildSingleRange(config);
assert.equal(baseline.positions.length, 1, "baseline position count");
near(stateAtPotatoOut(baseline, 0).poolTick, config.market.initialPoolTick, 1e-9, "baseline opening tick");
near(stateAtPotatoOut(baseline, 50_000_000).poolEth, 4.029055926894, 1e-9, "baseline half-inventory ETH");

const expectedHalfInventoryEth = new Map([
  ["scaled-statics", 686.9059413587],
  ["aggressive", 1786.9768973867],
  ["scarcity", 4664.8272467686],
]);

for (const curveConfig of config.curves) {
  const curve = buildCurve(config, curveConfig);
  assert.equal(curve.positions.length, 56, `${curve.name}: position count`);
  near(curve.positions.reduce((sum, position) => sum + position.amountPotato, 0), 100_000_000, 1e-5, `${curve.name}: inventory`);
  assert.ok(curve.positions.every((position) => position.lowerTick < position.upperTick), `${curve.name}: positive position widths`);
  assert.ok(curve.positions.every((position) => position.lowerTick % 60 === 0 && position.upperTick % 60 === 0), `${curve.name}: tick alignment`);
  near(stateAtPotatoOut(curve, 50_000_000).poolEth, expectedHalfInventoryEth.get(curve.name), 1e-8, `${curve.name}: pinned half-inventory ETH`);

  let previousEth = -1;
  let previousSpot = -1;
  for (const out of [0, 1_000_000, 10_000_000, 25_000_000, 50_000_000, 75_000_000, 95_000_000]) {
    const state = stateAtPotatoOut(curve, out);
    near(state.potatoOut, out, 1e-4, `${curve.name}: inverse POTATO at ${out}`);
    assert.ok(state.poolEth >= previousEth, `${curve.name}: ETH monotonicity`);
    assert.ok(state.spotEthPerPotato >= previousSpot, `${curve.name}: spot monotonicity`);
    previousEth = state.poolEth;
    previousSpot = state.spotEthPerPotato;
    near(stateAtPoolEth(curve, state.poolEth).potatoOut, out, 1e-3, `${curve.name}: round-trip inverse at ${out}`);
  }

  const start = stateAtPotatoOut(curve, 0);
  const protocolBuy = protocolBuyExactEth(curve, start, 5);
  near(protocolBuy.state.poolEth, 5, 1e-8, `${curve.name}: protocol buy ETH`);
  const publicBuy = publicBuyExactEth(curve, start, 5, config.market.hookFeeBps);
  assert.ok(publicBuy.potatoReceived < protocolBuy.potatoReceived, `${curve.name}: public fee reduces output`);
  assert.ok(publicBuy.hookFeeEth > 0, `${curve.name}: public buy hook earns ETH`);
  const sale = publicSellExactPotato(curve, protocolBuy.state, protocolBuy.potatoReceived / 2, config.market.hookFeeBps);
  assert.ok(sale.userEth > 0 && sale.hookFeeEth > 0, `${curve.name}: public sell pays user and hook`);

  const buyback = executeBuybackReserve(curve, start, 5, config.market);
  near(buyback.spentEth + buyback.callerRewardEth + buyback.remainingReserveEth, 5, 1e-9, `${curve.name}: buyback conservation`);
  assert.equal(buyback.calls, 3, `${curve.name}: 2 ETH max-spend chunking`);
}

const five = ticketRound(5, config.game);
near(five.totalRevenueEth, 0.0395625, 1e-12, "five-grab ticket revenue");
near(five.buybackEth, 0.00365625, 1e-12, "five-grab buyback");
near(five.nextWinnerEth, 0.00373125, 1e-12, "first ticket plus next-round BPS");

const ten = ticketRound(10, config.game);
near(ten.totalRevenueEth, 0.339990234375, 1e-12, "ten-grab ticket revenue");
near(ten.buybackEth, 0.0336990234375, 1e-12, "ten-grab buyback");

near(emissionForRound(10, 1, config.game).emittedPotato, 6_513.215599, 1e-6, "ten-grab full-vest emission");
near(emissionForRound(5, 0.5, config.game).emittedPotato, 2_262.190625, 1e-6, "five-grab half-vest emission");

const legacyEmissionGame = {...config.game, roundEmissionBudgetPotato: 100_000};
near(
  emissionForRound(10, 1, legacyEmissionGame).emittedPotato,
  65_132.15599,
  1e-6,
  "100k sensitivity ten-grab full-vest emission",
);

console.log("model invariants: ok");
