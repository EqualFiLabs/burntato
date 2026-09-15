const BPS = 10_000;

export function tickPrice(tick) {
  return 1.0001 ** tick;
}

export function alignTickUp(tick, spacing) {
  return Math.ceil(tick / spacing) * spacing;
}

export function assertConfig(config) {
  if (config.market.tickSpacing <= 0) throw new Error("tickSpacing must be positive");
  if (config.market.initialInventoryPotato <= 0) throw new Error("initialInventoryPotato must be positive");

  for (const curve of config.curves) {
    const shares = curve.bands.reduce((sum, band) => sum + band.shareBps, 0);
    if (shares !== BPS) throw new Error(`${curve.name}: band shares total ${shares}, expected ${BPS}`);
    for (const band of curve.bands) {
      if (band.tickLower >= band.tickUpper) throw new Error(`${curve.name}/${band.name}: invalid tick interval`);
      if (band.tickLower % config.market.tickSpacing || band.tickUpper % config.market.tickSpacing) {
        throw new Error(`${curve.name}/${band.name}: ticks are not aligned to spacing`);
      }
      if (band.positions <= 0) throw new Error(`${curve.name}/${band.name}: positions must be positive`);
    }
  }

  const allocationBps = [
    config.game.winnerBps,
    config.game.nextRoundWinnerBps,
    config.game.recoveryBps,
    config.game.treasuryBps,
    config.game.buybackBps,
    config.game.operatorPurchaseBps,
  ].reduce((sum, value) => sum + value, 0);
  if (allocationBps !== BPS) throw new Error(`ticket allocation totals ${allocationBps}, expected ${BPS}`);
}

export function buildCurve(config, curveConfig) {
  const inventory = config.market.initialInventoryPotato;
  const spacing = config.market.tickSpacing;
  const positions = [];

  for (const band of curveConfig.bands) {
    const bandAmount = inventory * band.shareBps / BPS;
    const amountPerPosition = bandAmount / band.positions;

    // Curve ticks quote ETH per POTATO. POTATO is token1, so the pool tick
    // interval is the sign-flipped canonical interval.
    const farTick = -band.tickUpper;
    const closeTick = -band.tickLower;
    const spread = closeTick - farTick;

    for (let i = 0; i < band.positions; i += 1) {
      // Doppler's multicurve topology uses a nested ladder whose positions all
      // share the far edge. Reproduce that geometry independently here.
      const lowerTick = farTick;
      const upperTick = alignTickUp(closeTick - Math.floor(i * spread / band.positions), spacing);
      const sqrtLower = 1.0001 ** (lowerTick / 2);
      const sqrtUpper = 1.0001 ** (upperTick / 2);
      const liquidity = amountPerPosition / (sqrtUpper - sqrtLower);
      positions.push({
        band: band.name,
        lowerTick,
        upperTick,
        amountPotato: amountPerPosition,
        liquidity,
        sqrtLower,
        sqrtUpper,
      });
    }
  }

  const minPoolTick = Math.min(...positions.map((position) => position.lowerTick));
  const maxPoolTick = Math.max(...positions.map((position) => position.upperTick));
  const curve = {
    name: curveConfig.name,
    description: curveConfig.description,
    inventory,
    positions,
    minPoolTick,
    maxPoolTick,
  };
  curve.maximumEth = stateAtPoolTick(curve, minPoolTick).poolEth;
  return curve;
}

export function buildSingleRange(config) {
  const { tickLower, tickUpper } = config.market.currentSingleRange;
  const sqrtLower = 1.0001 ** (tickLower / 2);
  const sqrtUpper = 1.0001 ** (tickUpper / 2);
  const amountPotato = config.market.initialInventoryPotato;
  const curve = {
    name: "current-single-range",
    description: "Current Burntato deployment geometry used as the baseline.",
    inventory: amountPotato,
    positions: [{
      band: "single-range",
      lowerTick: tickLower,
      upperTick: tickUpper,
      amountPotato,
      liquidity: amountPotato / (sqrtUpper - sqrtLower),
      sqrtLower,
      sqrtUpper,
    }],
    minPoolTick: tickLower,
    maxPoolTick: tickUpper,
  };
  curve.maximumEth = stateAtPoolTick(curve, tickLower).poolEth;
  return curve;
}

export function stateAtPoolTick(curve, poolTick) {
  const sqrtPrice = 1.0001 ** (poolTick / 2);
  let remainingPotato = 0;
  let poolEth = 0;

  for (const position of curve.positions) {
    const { liquidity, sqrtLower, sqrtUpper, amountPotato } = position;
    if (sqrtPrice >= sqrtUpper) {
      remainingPotato += amountPotato;
    } else if (sqrtPrice <= sqrtLower) {
      poolEth += liquidity * (1 / sqrtLower - 1 / sqrtUpper);
    } else {
      remainingPotato += liquidity * (sqrtPrice - sqrtLower);
      poolEth += liquidity * (1 / sqrtPrice - 1 / sqrtUpper);
    }
  }

  const potatoOut = Math.max(0, Math.min(curve.inventory, curve.inventory - remainingPotato));
  const canonicalTick = -poolTick;
  return {
    poolTick,
    canonicalTick,
    potatoOut,
    remainingPotato,
    poolEth,
    spotEthPerPotato: tickPrice(canonicalTick),
  };
}

function binarySearchTick(curve, predicate) {
  let low = curve.minPoolTick;
  let high = curve.maxPoolTick;
  for (let i = 0; i < 160; i += 1) {
    const middle = (low + high) / 2;
    const state = stateAtPoolTick(curve, middle);
    // Both potatoOut and poolEth increase as pool tick decreases.
    if (predicate(state)) high = middle;
    else low = middle;
  }
  return stateAtPoolTick(curve, (low + high) / 2);
}

export function stateAtPotatoOut(curve, potatoOut) {
  if (potatoOut <= 0) return stateAtPoolTick(curve, curve.maxPoolTick);
  if (potatoOut >= curve.inventory) return stateAtPoolTick(curve, curve.minPoolTick);
  return binarySearchTick(curve, (state) => state.potatoOut < potatoOut);
}

export function stateAtPoolEth(curve, poolEth) {
  if (poolEth <= 0) return stateAtPoolTick(curve, curve.maxPoolTick);
  if (poolEth >= curve.maximumEth) return stateAtPoolTick(curve, curve.minPoolTick);
  return binarySearchTick(curve, (state) => state.poolEth < poolEth);
}

export function protocolBuyExactEth(curve, state, ethInput) {
  const next = stateAtPoolEth(curve, Math.min(curve.maximumEth, state.poolEth + Math.max(0, ethInput)));
  return {
    state: next,
    ethSpent: next.poolEth - state.poolEth,
    potatoReceived: next.potatoOut - state.potatoOut,
  };
}

export function publicBuyExactEth(curve, state, ethInput, feeBps) {
  const gross = protocolBuyExactEth(curve, state, ethInput);
  const feePotato = gross.potatoReceived * feeBps / BPS;
  const finalOut = Math.max(state.potatoOut, gross.state.potatoOut - feePotato);
  const finalState = stateAtPotatoOut(curve, finalOut);
  return {
    state: finalState,
    ethInput: gross.ethSpent,
    potatoReceived: gross.potatoReceived - feePotato,
    feePotato,
    hookFeeEth: gross.state.poolEth - finalState.poolEth,
  };
}

export function publicBuyExactPotato(curve, state, desiredPotato, feeBps) {
  const grossPotato = Math.max(0, desiredPotato) * BPS / (BPS - feeBps);
  const grossState = stateAtPotatoOut(curve, Math.min(curve.inventory, state.potatoOut + grossPotato));
  const actualGross = grossState.potatoOut - state.potatoOut;
  const feePotato = actualGross * feeBps / BPS;
  const finalState = stateAtPotatoOut(curve, grossState.potatoOut - feePotato);
  return {
    state: finalState,
    ethInput: grossState.poolEth - state.poolEth,
    potatoReceived: actualGross - feePotato,
    feePotato,
    hookFeeEth: grossState.poolEth - finalState.poolEth,
  };
}

export function publicSellExactPotato(curve, state, potatoInput, feeBps) {
  const actualInput = Math.min(Math.max(0, potatoInput), state.potatoOut);
  const finalState = stateAtPotatoOut(curve, state.potatoOut - actualInput);
  const grossEth = state.poolEth - finalState.poolEth;
  const hookFeeEth = grossEth * feeBps / BPS;
  return {
    state: finalState,
    potatoInput: actualInput,
    grossEth,
    userEth: grossEth - hookFeeEth,
    hookFeeEth,
  };
}

export function executeBuybackReserve(curve, state, reserveEth, marketConfig) {
  let currentState = state;
  let remaining = Math.max(0, reserveEth);
  let totalSpent = 0;
  let totalReward = 0;
  let totalPotato = 0;
  let calls = 0;

  while (remaining > 1e-12 && currentState.poolEth < curve.maximumEth - 1e-12) {
    const requestedSpend = Math.min(
      marketConfig.buybackMaxSpendEth,
      remaining * BPS / (BPS + marketConfig.buybackCallerRewardBps),
    );
    const buy = protocolBuyExactEth(curve, currentState, requestedSpend);
    if (buy.ethSpent <= 1e-12) break;
    const reward = buy.ethSpent * marketConfig.buybackCallerRewardBps / BPS;
    currentState = buy.state;
    remaining -= buy.ethSpent + reward;
    totalSpent += buy.ethSpent;
    totalReward += reward;
    totalPotato += buy.potatoReceived;
    calls += 1;
  }

  return {
    state: currentState,
    remainingReserveEth: Math.max(0, remaining),
    spentEth: totalSpent,
    callerRewardEth: totalReward,
    potatoReceived: totalPotato,
    calls,
  };
}

export function ticketRound(grabs, game) {
  let price = game.startingGrabPriceEth;
  const result = {
    grabs,
    totalRevenueEth: 0,
    currentWinnerEth: 0,
    nextWinnerEth: 0,
    recoveryEth: 0,
    treasuryEth: 0,
    buybackEth: 0,
    operatorEth: 0,
    pricesEth: [],
  };

  for (let index = 0; index < grabs; index += 1) {
    result.pricesEth.push(price);
    result.totalRevenueEth += price;
    if (index === 0) {
      result.nextWinnerEth += price;
    } else {
      result.currentWinnerEth += price * game.winnerBps / BPS;
      result.nextWinnerEth += price * game.nextRoundWinnerBps / BPS;
      result.recoveryEth += price * game.recoveryBps / BPS;
      result.treasuryEth += price * game.treasuryBps / BPS;
      result.buybackEth += price * game.buybackBps / BPS;
      result.operatorEth += price * game.operatorPurchaseBps / BPS;
    }
    price *= 1 + game.priceIncreaseBps / BPS;
  }
  result.nextPriceEth = price;
  return result;
}

export function emissionForRound(grabs, vestingFraction, game) {
  let remaining = game.roundEmissionBudgetPotato;
  let emitted = 0;
  for (let index = 0; index < grabs; index += 1) {
    const opportunity = remaining * game.emissionStepBps / BPS;
    const earned = opportunity * vestingFraction;
    emitted += earned;
    remaining -= earned;
  }
  return { emittedPotato: emitted, remainingPotato: remaining };
}

export function liquidationValue(curve, state, potatoAmount, feeBps) {
  return publicSellExactPotato(curve, state, potatoAmount, feeBps).userEth;
}

export function potatoForLiquidationValue(curve, state, targetEth, feeBps) {
  if (targetEth <= 0) return 0;
  let low = 0;
  let high = state.potatoOut;
  for (let i = 0; i < 120; i += 1) {
    const middle = (low + high) / 2;
    if (liquidationValue(curve, state, middle, feeBps) < targetEth) low = middle;
    else high = middle;
  }
  return (low + high) / 2;
}

function addHookFee(accounting, hookFeeEth, market) {
  accounting.hookTreasuryEth += hookFeeEth * market.hookTreasuryShareBps / BPS;
  accounting.hookOperatorEth += hookFeeEth * (BPS - market.hookTreasuryShareBps) / BPS;
}

function visibleSponsorshipEth(sponsorships, round, lookahead) {
  return sponsorships
    .filter((item) => item.round > round && item.round <= round + lookahead)
    .reduce((sum, item) => sum + item.winnerEth + item.recoveryEth, 0);
}

export function simulateScenario(config, curve, scenario) {
  let marketState = stateAtPotatoOut(curve, 0);
  let buybackReserveEth = 0;
  let treasuryPotato = 0;
  let userPotato = 0;
  let modeledSupplyPotato = config.market.initialInventoryPotato;
  let burnedPotato = 0;
  let treasuryEth = 0;
  let operatorEth = 0;
  let recoveryCarryEth = 0;
  let publicEnabled = false;
  const winnerReserve = new Map([[1, config.game.initialWinnerReserveEth]]);
  const recoveryReserve = new Map();
  const commitments = new Map();
  const accounting = {
    sponsorshipEth: 0,
    hookTreasuryEth: 0,
    hookOperatorEth: 0,
    callerRewardsEth: 0,
    externalBuyEth: 0,
    userSellEth: 0,
    recoveryPaidEth: 0,
    totalEmittedPotato: 0,
  };
  const traces = [];

  for (const sponsor of scenario.sponsorships) {
    winnerReserve.set(sponsor.round, (winnerReserve.get(sponsor.round) || 0) + sponsor.winnerEth);
    recoveryReserve.set(sponsor.round, (recoveryReserve.get(sponsor.round) || 0) + sponsor.recoveryEth);
    accounting.sponsorshipEth += sponsor.winnerEth + sponsor.recoveryEth;
  }

  for (let round = 1; round <= scenario.rounds; round += 1) {
    const openingWinnerEth = winnerReserve.get(round) || 0;
    const openingRecoveryEth = (recoveryReserve.get(round) || 0) + recoveryCarryEth;
    const visibleFutureEth = visibleSponsorshipEth(scenario.sponsorships, round, scenario.lookaheadRounds);
    const reference = config.game.startingGrabPriceEth;
    const response =
      scenario.winnerResponse * Math.log2(1 + openingWinnerEth / reference)
      + scenario.recoveryResponse * Math.log2(1 + openingRecoveryEth / reference)
      + scenario.futureResponse * Math.log2(1 + visibleFutureEth / reference);
    const grabs = Math.max(1, Math.min(scenario.maximumGrabs, scenario.baseGrabs + Math.floor(response)));
    const tickets = ticketRound(grabs, config.game);
    const emissions = emissionForRound(grabs, scenario.vestingFraction, config.game);

    winnerReserve.set(round + 1, (winnerReserve.get(round + 1) || 0) + tickets.nextWinnerEth);
    buybackReserveEth += tickets.buybackEth;
    treasuryEth += tickets.treasuryEth;
    operatorEth += tickets.operatorEth;
    userPotato += emissions.emittedPotato;
    modeledSupplyPotato += emissions.emittedPotato;
    accounting.totalEmittedPotato += emissions.emittedPotato;

    let soldPotato = 0;
    let boughtPotato = 0;
    let buybackPotato = 0;
    let publicBuyEth = 0;
    let buybackSpendEth = 0;

    const executeUserSale = () => {
      const desiredSale = emissions.emittedPotato * scenario.emissionSellShare;
      const sale = publicSellExactPotato(curve, marketState, Math.min(desiredSale, userPotato), config.market.hookFeeBps);
      marketState = sale.state;
      soldPotato += sale.potatoInput;
      userPotato -= sale.potatoInput;
      accounting.userSellEth += sale.userEth;
      addHookFee(accounting, sale.hookFeeEth, config.market);
    };

    const executeProtocolBuyback = () => {
      const buyback = executeBuybackReserve(curve, marketState, buybackReserveEth, config.market);
      marketState = buyback.state;
      buybackReserveEth = buyback.remainingReserveEth;
      treasuryPotato += buyback.potatoReceived;
      buybackPotato += buyback.potatoReceived;
      buybackSpendEth += buyback.spentEth;
      accounting.callerRewardsEth += buyback.callerRewardEth;
    };

    if (scenario.marketOrder === "buy-first") {
      executeProtocolBuyback();
      executeUserSale();
    } else {
      executeUserSale();
      executeProtocolBuyback();
    }

    if (!publicEnabled && marketState.poolEth >= scenario.publicEnablePoolEth) publicEnabled = true;

    if (publicEnabled) {
      const promotionSignal = scenario.lookaheadRounds > 0
        ? visibleFutureEth / scenario.lookaheadRounds
        : 0;
      const demandEth = scenario.basePublicBuyEth + scenario.futurePotBuyRatio * promotionSignal;
      if (demandEth > 0) {
        const buy = publicBuyExactEth(curve, marketState, demandEth, config.market.hookFeeBps);
        marketState = buy.state;
        userPotato += buy.potatoReceived;
        boughtPotato += buy.potatoReceived;
        publicBuyEth += buy.ethInput;
        accounting.externalBuyEth += buy.ethInput;
        addHookFee(accounting, buy.hookFeeEth, config.market);
      }
    }

    // Recovery competition targets a market value relative to the next round's
    // expected recovery pot. Purchases are allowed only after public enablement.
    const nextBaseTickets = ticketRound(scenario.baseGrabs, config.game);
    const nextExpectedRecoveryEth = (recoveryReserve.get(round + 1) || 0) + nextBaseTickets.recoveryEth;
    const desiredCommitment = potatoForLiquidationValue(
      curve,
      marketState,
      nextExpectedRecoveryEth * scenario.recoveryCompetitionRatio,
      config.market.hookFeeBps,
    );
    if (desiredCommitment > userPotato && publicEnabled) {
      const buy = publicBuyExactPotato(
        curve,
        marketState,
        desiredCommitment - userPotato,
        config.market.hookFeeBps,
      );
      marketState = buy.state;
      userPotato += buy.potatoReceived;
      boughtPotato += buy.potatoReceived;
      publicBuyEth += buy.ethInput;
      accounting.externalBuyEth += buy.ethInput;
      addHookFee(accounting, buy.hookFeeEth, config.market);
    }
    const committedNext = Math.min(userPotato, desiredCommitment);
    userPotato -= committedNext;
    commitments.set(round + 1, (commitments.get(round + 1) || 0) + committedNext);

    const committedCurrent = commitments.get(round) || 0;
    const currentRecoveryEth = openingRecoveryEth + tickets.recoveryEth;
    let recoveryPaidEth = 0;
    if (committedCurrent > 0) {
      recoveryPaidEth = currentRecoveryEth;
      recoveryCarryEth = 0;
      const burned = committedCurrent * config.game.recoveryBurnBps / BPS;
      const treasuryShare = committedCurrent * config.game.recoveryTreasuryBps / BPS;
      burnedPotato += burned;
      modeledSupplyPotato -= burned;
      treasuryPotato += treasuryShare;
      accounting.recoveryPaidEth += recoveryPaidEth;
    } else {
      recoveryCarryEth = currentRecoveryEth;
    }

    traces.push({
      round,
      grabs,
      openingWinnerEth,
      openingRecoveryEth,
      currentWinnerEth: openingWinnerEth + tickets.currentWinnerEth,
      currentRecoveryEth,
      visibleFutureEth,
      ticketRevenueEth: tickets.totalRevenueEth,
      emittedPotato: emissions.emittedPotato,
      soldPotato,
      boughtPotato,
      buybackSpendEth,
      buybackPotato,
      publicBuyEth,
      publicEnabled,
      poolEth: marketState.poolEth,
      poolPotatoOut: marketState.potatoOut,
      spotEthPerPotato: marketState.spotEthPerPotato,
      committedCurrentPotato: committedCurrent,
      committedNextPotato: committedNext,
      recoveryPaidEth,
      modeledSupplyPotato,
      treasuryPotato,
      treasuryEth,
      operatorEth,
    });
  }

  const totalTicketRevenueEth = traces.reduce((sum, row) => sum + row.ticketRevenueEth, 0);
  return {
    curve: curve.name,
    scenario: scenario.name,
    rounds: scenario.rounds,
    totalGrabs: traces.reduce((sum, row) => sum + row.grabs, 0),
    totalTicketRevenueEth,
    finalPoolEth: marketState.poolEth,
    finalPoolPotatoOut: marketState.potatoOut,
    finalSpotEthPerPotato: marketState.spotEthPerPotato,
    final100kMarkEth: marketState.spotEthPerPotato * 100_000,
    publicEnabled,
    firstPublicRound: traces.find((row) => row.publicEnabled)?.round || null,
    finalBuybackReserveEth: buybackReserveEth,
    treasuryPotato,
    userPotato,
    modeledSupplyPotato,
    burnedPotato,
    treasuryEth,
    operatorEth,
    ...accounting,
    traces,
  };
}

export function sponsorshipBreakEven(config, sponsorEth) {
  const targetEligibleRevenue = sponsorEth * BPS / config.game.treasuryBps;
  let grabs = 1;
  let round = ticketRound(grabs, config.game);
  while (round.treasuryEth < sponsorEth && grabs < 500) {
    grabs += 1;
    round = ticketRound(grabs, config.game);
  }
  return {
    sponsorEth,
    ticketRevenueIgnoringFirstPurchaseEth: targetEligibleRevenue,
    grabsForDirectTreasuryShare: grabs,
    ticketRevenueAtBreakEvenEth: round.totalRevenueEth,
    treasuryShareAtBreakEvenEth: round.treasuryEth,
    lastTicketPriceEth: round.pricesEth.at(-1),
  };
}

export const constants = { BPS };
