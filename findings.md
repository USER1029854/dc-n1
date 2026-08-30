# findings.md — metropolis-dlmm-vaults (Sonic) re-audit

## [LOW][PROVEN] Share issuance priced off a manipulable DexLens active-bin spot, guarded only by a spot-evading TWAP band
- **Type:** value moved from users to depositor (share over-mint / dilution). Economic, permissionless, live.
- **Root cause:** `OracleVault._previewShares` mints `valueInY·totalShares/totalValueInY` using
  `getPrice()`, which resolves (for WETH, no whitelisted feed) to `DexLens._v2_2FallbackPrice` =
  active-bin **spot** of the WETH/wS LB pairs. `checkPriceInDeviation` bounds oracle vs the pair's
  120s **TWAP** (±5%), which an atomic swap does not move → the checked scope ≠ the acted-on scope
  (Lens G). (F-1 mis-attributed this to `strategy.getBalances()` composition; that is minimized at
  equilibrium and is not the knob — see REPORT.md.)
- **Proof:** fork at block 78,400,000. Push oracle +2.32% (guard PASSES) → +1.11% shares on a
  1000 WETH deposit → net **+19,002 wS ≈ $570** after costs (`audit/evidence/fork/PoC_output.txt`).
- **$ at risk / profit:** capped ≈ **1.1% of vault TVL**. Vault #54 (WETH/wS) TVL ≈ **$55.9k** (head
  78,405,753) → max ≈ **$620**, profit asymptotes ~$570–600 regardless of deposit size. Requires
  large *recoverable* deposit capital held through a non-atomic 600s+ queue.
- **Fleet:** 123 oracle vaults, **~$256k** total; 92 vaults ($255.7k, 99.8%) share this exact
  config (DexLens spot + ±5% guard). Aggregate extractable ≈ **$3–6k**. Largest vault $56.6k; none >$57k.
- **Fix:** value both legs off the LB TWAP (already sampled) or a real Chainlink WETH feed; align the
  guard's checked price with the price actually used for issuance.
- **Severity rationale:** genuine + systemic, but small absolute ($256k protocol) and relative
  (capped %, capital-inefficient, non-atomic) → LOW. Would rise if TVL grows, a token is priced off a
  thin external pool, or a high-TVL vault ships with the guard disabled.

## Verdict on F-1 as submitted
- Real class of bug and correct decisive check, but **wrong mechanism** (DexLens spot oracle, not bin
  composition), **wrong PoC magnitude** (true ~$570, not $0.82), and **wrong severity** (LOW, not HIGH).
