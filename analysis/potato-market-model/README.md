# POTATO economics model

Local, reproducible decision-support model for candidate six-band POTATO/ETH launch curves and their interaction with Burntato ticket revenue, emissions, Recovery commitments, swap fees, Treasury buybacks, and future-round sponsorship.

Run:

```sh
node model.test.mjs
node generate-report.mjs
```

The generated decision report is `report.md`. Full results are written to
`results.json`, and round-level behavioral scenario traces are written to
`round-traces.csv`. Those two large generated files are intentionally ignored;
rerun the generator whenever machine-readable output is needed.

The committed report selects the fixed aggressive launch curve and 10,000
POTATO default round emissions. The 100,000 POTATO setting remains in the
report only as an explicitly labelled sensitivity comparison.
