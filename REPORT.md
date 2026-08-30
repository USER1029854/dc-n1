# Re-check: Metropolis DLMM Vaults (Sonic) — F-1 "spot over-mint"

**Target:** `metropolis-dlmm-vaults` on Sonic (chainid 146). Family ALM-SLOT0.
**Finding under review:** F-1 `[PROVEN][HIGH]` — "wS→WETH spot moves over-mint shares on the WETH/wS oracle vault" (`0x6bE5a84D4A92269eC0Eb228B6c4dAdecED4C7D54`, vault #54).
**State pinned:** Sonic block `78,400,000`; live figures re-read at head `78,405,753`. Deployment verified on-chain (impls are explorer-verified; the clones' impls were recovered from runtime bytecode).

---

## TL;DR

The finding points at a **real design flaw** and the right decisive check for this family
(share issuance is priced off a *spot-derived* price, not a manipulation-resistant one). But three
things are wrong with F-1 as written, and all three shrink the scope:

1. **Wrong mechanism.** F-1 blames `strategy.getBalances()` bin *composition* valued at the oracle.
   That is not the exploitable knob. At a fixed price, `previewShares ∝ 1/totalValueInY` and the
   LP composition value is **minimized** at pool≈oracle — so from equilibrium, moving the active bin
   *raises* `totalValueInY` and gives you **fewer** shares. Reproduced on a fork: a 5,000 wS swap
   *decreases* `previewShares`. The real manipulable input is the **DexLens spot oracle price**
   feeding `getPrice()` (WETH has no Chainlink feed; its price is the reserve-weighted active-bin
   spot of the WETH/wS LB pairs — the vault's own pair dominates that weight).

2. **Wrong (too-low) PoC profit.** F-1's proven number is `+$0.82–$2.08`. The correct attack (push
   the DexLens spot up, deposit WETH, unwind) nets **~$570** on this vault — ~700× larger than F-1's
   PoC — because F-1 used a tiny 5,000 wS nudge and the wrong deposit leg.

3. **Wrong (too-high) severity.** Despite the larger true profit, `HIGH` is not supportable. The
   `±5%` oracle-vs-TWAP guard, the DexLens reserve-weighting, and the strategy owning ~99% of the
   vault pair together **cap** share inflation at ~1.1% (measured) of a **$56k** vault, and the whole
   protocol is only **$256k** across 123 vaults. Corrected severity: **LOW** (genuine, systemic,
   but small and capital-inefficient).

**Rescoped answer to the three questions (vault #54, the largest reachable instance):**

| Question | F-1's claim | Corrected (this audit) |
|---|---|---|
| How much **at risk** | implied whole-vault ("HIGH") | ≤ ~1.1% of TVL ≈ **~$620** on the $56k vault; **~$256k** fleet TVL, aggregate extractable **~$3–6k** |
| How much **needed** | ~$0.32–1.36 manip | ~$4.5k manipulation (recoverable −0.2% fee) **plus** large *recoverable* deposit (≈$0.5–2.5M to reach the cap; ≈$56k for ~$300) held through a non-atomic 600s+ queue |
| Attacker **profit** | +$0.82–$2.08 | **~$570 max** single-shot on #54 (≈1.1% × TVL cap); tiny vs capital; **~$3–6k** fleet-wide |

---

## The real mechanism (corrected)

`OracleVault._previewShares` (evidence `deployment/OracleVault.sol:80-112`) mints
`shares = valueInY · totalShares / totalValueInY`, where **both** `valueInY` (the deposit) and
`totalValueInY` (the backing) are computed with the **same** `price = getPrice()`.
So the only manipulable input is `price` (and, second-order, the composition `totalX/totalY`).

`getPrice()` (evidence `deployment/OracleHelper.sol:160-167`) = `oracleX/oracleY`, and each oracle is
an `OracleLensAggregator` returning `lens.getTokenPriceNative(token)` with `updatedAt = block.timestamp`
(never stale) — **a live DEX price, not Chainlink** (`deployment/OracleLensAggregator.sol:19-55`).
The lens is Trader Joe's `DexLens`. WETH has **no whitelisted feed** (`getDataFeeds(WETH)==[]`), so it
uses the `_v2_2FallbackPrice` path (`deployment/DexLens.sol:976-1002`): price =
`getPriceFromId(activeId)` — the **active-bin spot** — reserve-weighted across all five V2.2 WETH/wS
pairs. The vault's own pair (`0x9eDE…9Bc3`, binStep 10) carries ~all the near-active weight, so
`getPrice()` ≈ that pair's spot price, which anyone can move with a swap.

**Attack (proven on fork, `evidence/fork/PoC.t.sol`, output `PoC_output.txt`):**
1. Swap 150,000 wS → WETH on the vault pair → active bin 8,399,916 → 8,399,939, oracle
   81,011.85 → 82,895.16 wS/WETH (**+2.32%**).
2. `checkPriceInDeviation()` still **PASSES** (guard compares oracle to the *pair's 120s TWAP*, which
   an atomic swap does not move).
3. `deposit(1000 WETH)` mints **+1.11%** more shares than honest (share_inflation_bps = 111).
4. Unwind the manipulation swap; redeem pro-rata later (`_previewAmounts` is pure pro-rata on token
   balances, `deployment/BaseVault.sol:901`).
5. Net **+19,002 wS ≈ $570** valued at the true price after all swap costs; gas ~1.2M (≈$0.01 on Sonic).

## Why it is capped (the three caps that make it LOW, not HIGH)

- **The guard.** `_checkPrice` (`deployment/OracleHelper.sol:192-214`) reverts if `getPrice` leaves
  `±5%` of the pair's 120s TWAP. Atomic manipulation can't move the TWAP, so the oracle push is
  bounded to ~5%; the achievable *share* inflation is roughly half that (the wS leg of the backing
  doesn't move), ≈2.5% ceiling.
- **DexLens reserve-weighting.** Pushing the vault pair's active bin into thin bins collapses that
  pair's weight in the oracle average, so the unmanipulated sibling pairs drag the oracle back —
  self-limiting.
- **Thin pair inventory.** The vault pair holds only ~1.8–3.3 WETH, so the UP push runs out of WETH
  after ~+2.3–4% before hitting the guard. Measured max share inflation ≈ **1.1%**, so max extractable
  ≈ 1.1% × $56k ≈ **~$620**, and profit **asymptotes** (evidence `Attack2.t.sol testAsymptoteUp`:
  ~19,500 wS regardless of deposit size).

To *approach* that cap you must deposit far more than the vault holds (≈$0.5–2.5M of WETH), all
recoverable, but held through the **non-atomic** 600s cooldown + operator-driven queue — exposing
that whole position to market risk that dwarfs the ~$570 edge. A realistic ~$56k deposit nets ~$300.
The DOWN direction (deflate, deposit wS) is weaker (~$188) because the strategy's range only extends
~11 bins below active.

## Fleet (the scope multiplier — and why it stays small)

123 Oracle vaults (evidence `live/fleet_summary.txt`, `live/fleet_final.json`):
- **92 vaults hold $255,703 (99.8% of TVL)** on the `OracleRewardVault`/DexLens impls, **all** with the
  same `twapEnabled=1, deviation=5, twap=120` guard → each exposed to ≤~1–2.5% of its TVL.
- **31 older-impl vaults** (`getOracleHelper()` reverts) hold **$571 total** — negligible.
- Largest vault is $56,596; **none exceeds $57k**. Total protocol TVL **~$256k** (matches DefiLlama).

Aggregate theoretically extractable across the whole fleet ≈ **$3–6k**, requiring per-vault capital far
exceeding the take, one-shot each, through non-atomic queues. Uneconomical.

## Flash-loan analysis (does it change cost/severity? No)

The attack has two capital legs that behave oppositely under flash loans:

- **Manipulation leg (push the oracle): atomic → flash-loanable, but moot.** The wS→WETH→wS round
  trip is one transaction, so the ~$4.5k could be flash-borrowed — but it is already cheap and
  self-recovering, and its effect is **capped by pair liquidity, not capital**. The vault pair holds
  only ~1.8–3.3 WETH; the DexLens reserve-weighting and the ±5% guard cap the oracle push at ~+2.3–4%
  no matter how much wS is supplied. A $1B flash loan buys the same ~3 WETH and yields the same ~1.1%
  share-inflation ceiling. Flash-loaning this leg raises neither cost nor ceiling.

- **Deposit leg (scales profit toward the ~$620/vault cap): NOT flash-loanable.** Deposit→exit cannot
  be one transaction, verified in the deployed code:
  - `queueWithdrawal` is gated by `cooldownPassed`: `userDeposited + getDepositToWithdrawCooldown() >
    block.timestamp` reverts. Live cooldown = **600 s** — you can't even queue in the deposit tx.
  - `_redeemWithdrawal` reverts `BaseVault__InvalidRound` while `round >= currentRound`; a round is only
    redeemable **after the operator advances it via `rebalance()`** (operator `0xA63C…D329`; current
    round 40). Redemption is a separate, later, operator-gated tx.
  - No synchronous withdraw; `emergencyWithdraw()` only in admin-set emergency mode (pro-rata anyway).

  So the profit-scaling capital must be **real, locked ≥600 s + until an operator rebalance, and
  market-risk-exposed** throughout (the operator rebalances at the corrected price).

The one leg a flash loan could amplify (deposit) is exactly the non-atomic one; the atomic leg
(manipulation) is already cheap and liquidity-capped. This queued/cooldown/operator-gated withdrawal
is the standard ALM defense against flash-loan share-price attacks, and it is intact here — which is
precisely why this stays LOW rather than a flash-loan-drainable HIGH. **Flash loans do not change the
cost or the severity.**

## Severity: HIGH → LOW

It is a **real, systemic** value-integrity defect (spot-priced issuance guarded only by a band that
does not reference the manipulated spot — the classic ALM-SLOT0 shape, same family as the cited Arrakis
incident) and it is permissionless and live. But its economic impact is small in both absolute
(~$256k protocol, ~$620 per-vault cap) and relative terms (capped %, capital-inefficient, non-atomic).
It is worth fixing — and would become materially worse if TVL grows, if a vault prices a token off a
genuinely thin external pool, or if any high-TVL vault ships with the guard disabled — but on the
deployment as it stands it is **LOW**, not HIGH.

## Minimal fix

Price share issuance/backing off a **manipulation-resistant** value: use the LB pair's TWAP price
(the vault already samples it) as the valuation price for both legs, or value the strategy at the
TWAP-implied composition; and/or bind `getPrice()` to a real Chainlink feed for WETH instead of the
DexLens active-bin spot fallback. The current guard checks the wrong thing (oracle vs TWAP) while the
value is taken from spot — align the checked scope with the acted-on scope.

## What would falsify this re-assessment

- A WETH/wS (or other vault-token) pool with deep, cheaply-manipulable liquidity **outside** the
  guard's TWAP reference, letting the oracle move >5% while the guard passes → higher `g`.
- A high-TVL vault with `twapPriceCheckEnabled=false` (none today; the 31 unguarded vaults are dust).
- A withdrawal path that *is* price-dependent (checked: `_previewAmounts` is pro-rata, so no).

## Evidence

Deployment sources: `audit/evidence/deployment/`. Fork tests + outputs: `audit/evidence/fork/`
(`PoC.t.sol`/`PoC_output.txt` = documented single run; `Attack.t.sol`,`Attack2.t.sol` = profit grid +
asymptote/DOWN; `Probe*.t.sol` = direction/guard sweeps). Fleet: `audit/evidence/live/`. Prices:
`audit/evidence/reference/fleet_prices.json` (WETH $2458.04, wS $0.029937). Re-runnable via
`audit/commands.sh`.
