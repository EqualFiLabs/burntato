# POTATO market-depth and game-economics model

Generated from `config.json` by `generate-report.mjs`. This is decision support, not a forecast or an implementation specification.

## Executive conclusion

The current single-range launch curve is too cheap for the intended recovery game: half of its 100 million launch inventory costs only **4.03 ETH**. A six-band layout materially improves scarcity, and **the aggressive curve is the selected launch profile**. It preserves the opening quote, reaches about **1786.98 ETH absorbed at 50 million POTATO**, and marks 100,000 POTATO at about **18.17 ETH** there. The scarcity curve remains an upper sensitivity bound, but its 4664.83 ETH half-inventory cost is too aggressive for the initial launch.

This recommendation is conditional. The model says curve shape alone does not create durable price support: ticket activity, vesting, emission selling, recovery burns, and timely execution of the buyback reserve dominate the path. Public buys remain disabled during bootstrap; only Treasury buybacks create initial ETH depth. The public-buy threshold in scenarios is an analysis trigger, while the deployed protocol still requires an intentional administrative enablement decision.

## Modelled protocol facts

- Launch inventory: 100,000,000 POTATO; modeled as 56 permanent Uniswap v4 positions across six bands.
- Opening pool tick: 170280; opening spot quote is 4.02906e-8 ETH per POTATO.
- Ticket price: 0.003000 ETH, increasing 50% after each grab.
- The first ticket of every round goes entirely to the next round Winner reserve. Later tickets split 25% current Winner, 2% next Winner, 30% Recovery, 18% Treasury, 10% buyback, and 15% Operators.
- Round emission budget: 10,000 POTATO. Each holder opportunity earns 10% of remaining emissions multiplied by its vesting fraction.
- Emission sensitivity: ten fully vested holder opportunities emit 6,513 POTATO at the selected 10,000 budget versus 65,132 POTATO at the prior 100,000 budget. The larger budget is retained only as stress context.
- Recovery settlement destroys 90% of committed POTATO and transfers 10% to Treasury.
- Public swap hook fee: 1%, split 60% Treasury / 40% Operators. Protocol buybacks bypass that fee, send POTATO to Treasury, and leave their ETH in the pool.

## Candidate curve comparison

### Current baseline

| Geometry | ETH absorbed at 50M out | 50M spot (ETH/POTATO) | POTATO out after 50 ETH | 50 ETH mark for 100k |
|---|---:|---:|---:|---:|
| current single range | 4.029 | 1.61162e-7 | 92,542,798 | 0.7245 ETH |

The baseline uses the current one-position range [-887220, 170280] with POTATO as token1. It establishes the relative claim above; it is not mixed into the six-band scenario sweep.

### Six-band candidates

| Curve | ETH absorbed at 10M out | ETH absorbed at 50M out | 50M spot (ETH/POTATO) | 50M mark for 100k | Maximum theoretical ETH |
|---|---:|---:|---:|---:|---:|
| scaled-statics | 3.378 | 686.906 | 0.0000626235 | 6.262 ETH | 5.246172493467503e+24 |
| aggressive | 4.722 | 1786.977 | 0.000181731 | 18.173 ETH | 1.0396451688518485e+25 |
| scarcity | 6.654 | 4664.827 | 0.000522301 | 52.230 ETH | 2.0541156679073955e+25 |

The maximum is a mathematical endpoint of the permanent tail, not a realistic fundraising target. Near-boundary quotes become increasingly sensitive and should not be interpreted as attainable proceeds.

### Inventory milestones

| Curve | POTATO out | Inventory out | Pool ETH | Spot ETH/POTATO | 100k mark |
|---|---:|---:|---:|---:|---:|
| scaled-statics | 1,000,000 | 1.0% | 0.081 | 1.08219e-7 | 0.011 ETH |
| scaled-statics | 2,500,000 | 2.5% | 0.284 | 1.59588e-7 | 0.016 ETH |
| scaled-statics | 5,000,000 | 5.0% | 0.851 | 3.27598e-7 | 0.033 ETH |
| scaled-statics | 10,000,000 | 10.0% | 3.378 | 6.58749e-7 | 0.066 ETH |
| scaled-statics | 25,000,000 | 25.0% | 37.719 | 0.00000496764 | 0.497 ETH |
| scaled-statics | 50,000,000 | 50.0% | 686.906 | 0.0000626235 | 6.262 ETH |
| scaled-statics | 75,000,000 | 75.0% | 4657.378 | 0.000272821 | 27.282 ETH |
| scaled-statics | 85,000,000 | 85.0% | 7800.379 | 0.000361372 | 36.137 ETH |
| scaled-statics | 90,000,000 | 90.0% | 10510.666 | 0.000813086 | 81.309 ETH |
| scaled-statics | 95,000,000 | 95.0% | 18641.527 | 0.00325234 | 325.234 ETH |
| scaled-statics | 99,000,000 | 99.0% | 83688.418 | 0.0813086 | 8130.861 ETH |
| scaled-statics | 99,900,000 | 99.9% | 815465.937 | 8.13086 | 813086.132 ETH |
| aggressive | 1,000,000 | 1.0% | 0.090 | 1.24526e-7 | 0.012 ETH |
| aggressive | 2,500,000 | 2.5% | 0.331 | 1.95198e-7 | 0.020 ETH |
| aggressive | 5,000,000 | 5.0% | 1.058 | 4.39200e-7 | 0.044 ETH |
| aggressive | 10,000,000 | 10.0% | 4.722 | 9.93858e-7 | 0.099 ETH |
| aggressive | 25,000,000 | 25.0% | 67.990 | 0.00000984242 | 0.984 ETH |
| aggressive | 50,000,000 | 50.0% | 1786.977 | 0.000181731 | 18.173 ETH |
| aggressive | 75,000,000 | 75.0% | 15423.495 | 0.00101468 | 101.468 ETH |
| aggressive | 85,000,000 | 85.0% | 27464.363 | 0.00141919 | 141.919 ETH |
| aggressive | 90,000,000 | 90.0% | 38108.255 | 0.00319317 | 319.317 ETH |
| aggressive | 95,000,000 | 95.0% | 70039.930 | 0.0127727 | 1277.267 ETH |
| aggressive | 99,000,000 | 99.0% | 325493.331 | 0.319317 | 31931.675 ETH |
| aggressive | 99,900,000 | 99.9% | 3199344.088 | 31.9317 | 3193167.508 ETH |
| scarcity | 1,000,000 | 1.0% | 0.099 | 1.42687e-7 | 0.014 ETH |
| scarcity | 2,500,000 | 2.5% | 0.386 | 2.38085e-7 | 0.024 ETH |
| scarcity | 5,000,000 | 5.0% | 1.319 | 5.91070e-7 | 0.059 ETH |
| scarcity | 10,000,000 | 10.0% | 6.654 | 0.00000150572 | 0.151 ETH |
| scarcity | 25,000,000 | 25.0% | 123.083 | 0.0000194146 | 1.941 ETH |
| scarcity | 50,000,000 | 50.0% | 4664.827 | 0.000522301 | 52.230 ETH |
| scarcity | 75,000,000 | 75.0% | 51211.764 | 0.00374429 | 374.429 ETH |
| scarcity | 85,000,000 | 85.0% | 97092.866 | 0.00554011 | 554.011 ETH |
| scarcity | 90,000,000 | 90.0% | 138643.720 | 0.0124653 | 1246.526 ETH |
| scarcity | 95,000,000 | 95.0% | 263296.283 | 0.0498610 | 4986.103 ETH |
| scarcity | 99,000,000 | 99.0% | 1260516.787 | 1.24653 | 124652.563 ETH |
| scarcity | 99,900,000 | 99.9% | 12479247.451 | 124.653 | 12465256.294 ETH |

### Treasury bootstrap depth

| Curve | Treasury ETH bought | POTATO acquired | Inventory out | Spot ETH/POTATO | 100k mark |
|---|---:|---:|---:|---:|---:|
| scaled-statics | 2 | 7,676,720 | 7.68% | 5.21357e-7 | 0.0521 ETH |
| scaled-statics | 5 | 12,133,429 | 12.13% | 9.61580e-7 | 0.0962 ETH |
| scaled-statics | 10 | 15,666,313 | 15.67% | 0.00000187430 | 0.1874 ETH |
| scaled-statics | 25 | 21,551,995 | 21.55% | 0.00000316705 | 0.3167 ETH |
| scaled-statics | 50 | 26,977,175 | 26.98% | 0.00000749102 | 0.7491 ETH |
| scaled-statics | 100 | 31,543,531 | 31.54% | 0.0000147355 | 1.4735 ETH |
| aggressive | 2 | 6,718,296 | 6.72% | 6.50241e-7 | 0.0650 ETH |
| aggressive | 5 | 10,276,305 | 10.28% | 0.00000102149 | 0.1021 ETH |
| aggressive | 10 | 13,634,005 | 13.63% | 0.00000222166 | 0.2222 ETH |
| aggressive | 25 | 18,095,548 | 18.10% | 0.00000448923 | 0.4489 ETH |
| aggressive | 50 | 22,620,241 | 22.62% | 0.00000650973 | 0.6510 ETH |
| aggressive | 100 | 27,388,177 | 27.39% | 0.0000171470 | 1.7147 ETH |
| scarcity | 2 | 5,983,082 | 5.98% | 7.88111e-7 | 0.0788 ETH |
| scarcity | 5 | 8,829,639 | 8.83% | 0.00000131567 | 0.1316 ETH |
| scarcity | 10 | 11,931,879 | 11.93% | 0.00000220345 | 0.2203 ETH |
| scarcity | 25 | 15,770,543 | 15.77% | 0.00000581125 | 0.5811 ETH |
| scarcity | 50 | 19,113,367 | 19.11% | 0.00000912228 | 0.9122 ETH |
| scarcity | 100 | 23,531,179 | 23.53% | 0.0000134370 | 1.3437 ETH |

## Ticket revenue versus emission sell pressure

The flow-balance mark is the buyback allocation divided by newly emitted POTATO offered for sale. It is not the AMM price and ignores inventory, prior liquidity, recovery burning, external demand, and price impact. It exposes the key nonlinear relationship: ticket revenue grows geometrically while emissions approach a fixed ceiling.

| Grabs | Ticket revenue | Last grab | Buyback reserve | Full-vest emission | Emission sold | Flow-balance 100k mark |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 0.039563 ETH | 0.015188 ETH | 0.003656 ETH | 4,095 | 25% | 0.3571 ETH |
| 5 | 0.039563 ETH | 0.015188 ETH | 0.003656 ETH | 4,095 | 50% | 0.1786 ETH |
| 5 | 0.039563 ETH | 0.015188 ETH | 0.003656 ETH | 4,095 | 100% | 0.0893 ETH |
| 10 | 0.339990 ETH | 0.115330 ETH | 0.033699 ETH | 6,513 | 25% | 2.0696 ETH |
| 10 | 0.339990 ETH | 0.115330 ETH | 0.033699 ETH | 6,513 | 50% | 1.0348 ETH |
| 10 | 0.339990 ETH | 0.115330 ETH | 0.033699 ETH | 6,513 | 100% | 0.5174 ETH |
| 15 | 2.621363 ETH | 0.875788 ETH | 0.261836 ETH | 7,941 | 25% | 13.1889 ETH |
| 15 | 2.621363 ETH | 0.875788 ETH | 0.261836 ETH | 7,941 | 50% | 6.5945 ETH |
| 15 | 2.621363 ETH | 0.875788 ETH | 0.261836 ETH | 7,941 | 100% | 3.2972 ETH |
| 20 | 19.945540 ETH | 6.650513 ETH | 1.994254 ETH | 8,784 | 25% | 90.8106 ETH |
| 20 | 19.945540 ETH | 6.650513 ETH | 1.994254 ETH | 8,784 | 50% | 45.4053 ETH |
| 20 | 19.945540 ETH | 6.650513 ETH | 1.994254 ETH | 8,784 | 100% | 22.7027 ETH |

Five-grab rounds cannot materially support price through buybacks alone. At ten grabs, the buyback is still only 0.033699 ETH against 6,513 maximum emitted POTATO. The intended flywheel becomes meaningfully stronger only when a round reaches the steeper portion of the ticket curve or when recovery permanently removes a large part of emissions.

## Emission-sale stress after a 50 ETH Treasury bootstrap

Each stress path starts with 50 ETH in the pool, runs 100 identical ten-grab/full-vesting rounds, and sells every newly emitted POTATO. “With buyback” executes the whole available reserve after each sale; it assumes keepers act and enough blocks elapse. This is deliberately punitive and does not include recovery burning or external buys.

| Curve | Buyback | Round | Pool ETH | POTATO out | 100k mark | Cumulative seller ETH |
|---|---|---:|---:|---:|---:|---:|
| scaled-statics | no | 1 | 49.951 | 26,970,661 | 0.7483 ETH | 0.048 |
| scaled-statics | no | 5 | 49.757 | 26,944,609 | 0.7450 ETH | 0.241 |
| scaled-statics | no | 10 | 49.515 | 26,912,043 | 0.7409 ETH | 0.480 |
| scaled-statics | no | 25 | 48.797 | 26,814,344 | 0.7289 ETH | 1.191 |
| scaled-statics | no | 50 | 47.626 | 26,651,514 | 0.7095 ETH | 2.350 |
| scaled-statics | no | 100 | 45.389 | 26,325,853 | 0.6629 ETH | 4.565 |
| scaled-statics | yes | 1 | 49.985 | 26,975,141 | 0.7488 ETH | 0.048 |
| scaled-statics | yes | 5 | 49.924 | 26,967,021 | 0.7478 ETH | 0.241 |
| scaled-statics | yes | 10 | 49.848 | 26,956,906 | 0.7465 ETH | 0.482 |
| scaled-statics | yes | 25 | 49.624 | 26,926,791 | 0.7428 ETH | 1.202 |
| scaled-statics | yes | 50 | 49.259 | 26,877,357 | 0.7366 ETH | 2.394 |
| scaled-statics | yes | 100 | 48.556 | 26,781,281 | 0.7249 ETH | 4.749 |
| aggressive | no | 1 | 49.958 | 22,613,727 | 0.6507 ETH | 0.042 |
| aggressive | no | 5 | 49.788 | 22,587,675 | 0.6495 ETH | 0.210 |
| aggressive | no | 10 | 49.577 | 22,555,108 | 0.6481 ETH | 0.419 |
| aggressive | no | 25 | 48.946 | 22,457,410 | 0.6438 ETH | 1.044 |
| aggressive | no | 50 | 47.903 | 22,294,580 | 0.6368 ETH | 2.076 |
| aggressive | no | 100 | 45.852 | 21,968,919 | 0.6231 ETH | 4.107 |
| aggressive | yes | 1 | 49.991 | 22,618,880 | 0.6509 ETH | 0.042 |
| aggressive | yes | 5 | 49.956 | 22,613,441 | 0.6507 ETH | 0.210 |
| aggressive | yes | 10 | 49.912 | 22,606,653 | 0.6504 ETH | 0.419 |
| aggressive | yes | 25 | 49.780 | 22,586,361 | 0.6495 ETH | 1.048 |
| aggressive | yes | 50 | 49.562 | 22,552,777 | 0.6480 ETH | 2.094 |
| aggressive | yes | 100 | 49.133 | 22,486,485 | 0.6451 ETH | 4.178 |
| scarcity | no | 1 | 49.941 | 19,106,854 | 0.9116 ETH | 0.059 |
| scarcity | no | 5 | 49.703 | 19,080,801 | 0.9090 ETH | 0.294 |
| scarcity | no | 10 | 49.408 | 19,048,235 | 0.9058 ETH | 0.586 |
| scarcity | no | 25 | 48.528 | 18,950,537 | 0.8964 ETH | 1.458 |
| scarcity | no | 50 | 47.081 | 18,787,706 | 0.8809 ETH | 2.890 |
| scarcity | no | 100 | 44.261 | 18,462,045 | 0.8512 ETH | 5.682 |
| scarcity | yes | 1 | 49.974 | 19,110,531 | 0.9119 ETH | 0.059 |
| scarcity | yes | 5 | 49.871 | 19,099,200 | 0.9108 ETH | 0.294 |
| scarcity | yes | 10 | 49.742 | 19,085,062 | 0.9094 ETH | 0.587 |
| scarcity | yes | 25 | 49.359 | 19,042,815 | 0.9053 ETH | 1.465 |
| scarcity | yes | 50 | 48.729 | 18,972,962 | 0.8985 ETH | 2.918 |
| scarcity | yes | 100 | 47.501 | 18,835,341 | 0.8854 ETH | 5.793 |

## Recovery whale-resistance illustration

At 50 ETH of bootstrap depth, an incumbent is assigned enough POTATO to have a 5 ETH liquidation value. The table estimates the ETH needed by a new buyer to acquire a target share of total Recovery commitments. It assumes no other buyers, no intervening sells, and immediate public purchase availability, so it is a lower-complexity comparison rather than a game-theoretic forecast.

| Curve | Incumbent POTATO | Target share | Required net POTATO | Buyer ETH | Resulting 100k mark |
|---|---:|---:|---:|---:|---:|
| scaled-statics | 718,106 | 25% | 239,369 | 1.849 | 0.780 ETH |
| scaled-statics | 718,106 | 50% | 718,106 | 5.789 | 0.849 ETH |
| scaled-statics | 718,106 | 75% | 2,154,318 | 19.703 | 1.063 ETH |
| aggressive | 796,819 | 25% | 265,606 | 1.763 | 0.663 ETH |
| aggressive | 796,819 | 50% | 796,819 | 5.387 | 0.688 ETH |
| aggressive | 796,819 | 75% | 2,390,458 | 18.335 | 0.987 ETH |
| scarcity | 570,723 | 25% | 190,241 | 1.771 | 0.931 ETH |
| scarcity | 570,723 | 50% | 570,723 | 5.428 | 0.971 ETH |
| scarcity | 570,723 | 75% | 1,712,168 | 17.372 | 1.092 ETH |

## Behavioral scenario sweep

These scenarios use explicit response coefficients from `config.json`; they are **not predictions**. Grab counts respond logarithmically to current and visible future pots, public buying starts only after its configured ETH-depth threshold, and Recovery competition targets a fraction of the next expected Recovery pot. Scenario traces are in `round-traces.csv`.

| Scenario | Base/max grabs | Vesting | Emissions sold | Public threshold | Promotion funding |
|---|---:|---:|---:|---:|---|
| closed-low-activity | 5/12 | 50% | 75% | 25 ETH | none |
| closed-active | 10/16 | 75% | 50% | 50 ETH | none |
| single-5-plus-5-promotion | 7/20 | 75% | 40% | 25 ETH | R10: 5+5 ETH |
| recurring-5-plus-5-promotions | 7/20 | 75% | 40% | 25 ETH | R10: 5+5 ETH; R20: 5+5 ETH; R30: 5+5 ETH; R40: 5+5 ETH |
| maximum-emission-sell-stress | 10/10 | 100% | 100% | 25 ETH | none |
| recovery-frenzy | 8/20 | 90% | 25% | 25 ETH | R10: 5+10 ETH; R20: 5+10 ETH |

In every dynamic path, the simulator sells the configured emission share, makes permissionless buyback calls until the round's reserve is exhausted, and only then allows modeled public demand if the threshold has been crossed. This assumes enough blocks and willing keepers; it is intentionally more operationally favorable than an unserviced reserve.

| Curve | Scenario | Rounds | Grabs | Ticket revenue | Final pool ETH | Final 100k mark | Emitted | Burned | Public enabled |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| scaled-statics | closed-low-activity | 30 | 150 | 1.19 | 0.10 | 0.012 ETH | 67,866 | 16,288 | no |
| scaled-statics | closed-active | 30 | 300 | 10.20 | 0.99 | 0.036 ETH | 162,425 | 73,091 | no |
| scaled-statics | single-5-plus-5-promotion | 30 | 361 | 187.10 | 18.46 | 0.271 ETH | 172,846 | 93,397 | no |
| scaled-statics | recurring-5-plus-5-promotions | 50 | 881 | 783.99 | 93.07 | 1.384 ETH | 363,353 | 2,108,625 | round 14 |
| scaled-statics | maximum-emission-sell-stress | 30 | 300 | 10.20 | 0.96 | 0.036 ETH | 195,396 | 0 | no |
| scaled-statics | recovery-frenzy | 30 | 507 | 405.02 | 59.89 | 0.924 ETH | 232,863 | 2,893,313 | round 13 |
| aggressive | closed-low-activity | 30 | 150 | 1.19 | 0.10 | 0.013 ETH | 67,866 | 16,288 | no |
| aggressive | closed-active | 30 | 300 | 10.20 | 0.99 | 0.042 ETH | 162,425 | 73,091 | no |
| aggressive | single-5-plus-5-promotion | 30 | 361 | 187.10 | 18.42 | 0.367 ETH | 172,846 | 93,397 | no |
| aggressive | recurring-5-plus-5-promotions | 50 | 881 | 783.99 | 92.50 | 1.572 ETH | 363,353 | 1,926,184 | round 14 |
| aggressive | maximum-emission-sell-stress | 30 | 300 | 10.20 | 0.96 | 0.041 ETH | 195,396 | 0 | no |
| aggressive | recovery-frenzy | 30 | 507 | 405.02 | 55.19 | 0.687 ETH | 232,863 | 2,308,676 | round 13 |
| scarcity | closed-low-activity | 30 | 150 | 1.19 | 0.10 | 0.015 ETH | 67,866 | 16,288 | no |
| scarcity | closed-active | 30 | 300 | 10.20 | 0.98 | 0.046 ETH | 162,425 | 73,091 | no |
| scarcity | single-5-plus-5-promotion | 30 | 361 | 187.10 | 18.38 | 0.448 ETH | 172,846 | 93,397 | no |
| scarcity | recurring-5-plus-5-promotions | 50 | 881 | 783.99 | 92.22 | 1.283 ETH | 363,353 | 1,592,686 | round 14 |
| scarcity | maximum-emission-sell-stress | 30 | 300 | 10.20 | 0.96 | 0.045 ETH | 195,396 | 0 | no |
| scarcity | recovery-frenzy | 30 | 507 | 405.02 | 55.37 | 0.971 ETH | 232,863 | 1,732,433 | round 13 |

### Promotion economics

A 5 ETH Winner plus 5 ETH Recovery sponsorship costs 10 ETH. Looking only at the direct 18% Treasury share of eligible ticket purchases, it requires approximately 55.56 ETH of eligible revenue to repay. Under a single 0.003 ETH / 50% price ladder, direct Treasury receipts first exceed 10 ETH at grab 23; cumulative ticket revenue is 67.33 ETH and that grab alone costs 22.45 ETH. That arithmetic is not a recommendation to expect a 23-grab round: it demonstrates that direct ticket revenue alone is a demanding sponsorship-recovery mechanism.

The business case for sponsorship therefore depends on the combined system: higher ticket volume, Treasury POTATO acquired by buybacks, hook revenue after public opening, Recovery burns, and the residual ETH depth owned by the permanently locked LP. None of those should be counted as realized Treasury profit without defining who can monetize them and under what governance policy.

## Recommendation

1. Launch with the fixed **aggressive** profile; retain **scaled-statics** as the downside comparison and **scarcity** as the upside/stress bound.
2. Use a staged public-buy gate based on observed sell capacity and fork quotes, not merely a round number. Test at least 25, 50, and 100 ETH of protocol-created depth.
3. Treat keeper execution as part of launch readiness. A funded buyback reserve does nothing until `buyback()` is called; the model's “with buyback” paths assume prompt execution.
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

`node model.test.mjs`

`node generate-report.mjs`

Inputs are in `config.json`; machine-readable results are in `results.json`; every dynamic round is in `round-traces.csv`.
