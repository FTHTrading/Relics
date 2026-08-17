# Business model: who's the issuer

The more important fork isn't which securities exemption to use — it's who's on the hook for it. This repo currently answers that question by default (`ArtEditionSPV.sol` names UnyKorn LLC as SPV manager, and the site markets pieces directly), without anyone deciding it on purpose. This document makes it an explicit decision.

---

## The comparable-platform record

Every direct precedent for "retail fractional-share collectibles platform" was checked against current sources, not assumed from memory:

| Platform | Outcome | Date | Detail |
|---|---|---|---|
| **Rally (Rally Rd.)** | Shut down, rolled into a closed-end vehicle (PIKA, NYSE) | Announced 2026-07-17 | Sourcing fees >20% of asset value frontloaded revenue on constant new listings; revenue "completely dried up" once the 2022 collectibles boom cooled; 110 realized exits averaged **1.37x gross** before fees/taxes/holding costs |
| **Otis** | Acquired by Public.com in a fire sale, subsequently divested | 2022 | — |
| **Collectable** | Liquidated most assets | 2023 | Failed to attract further investment |
| **Mythic Markets** | Closed | 2021 | — |
| **Vint** | Dropped its Reg A+ retail offering entirely, now accredited-only | 2023-12 | — |
| **Here.co** | Ceased operations | 2024-01 | — |
| **LEX Markets** | Shut down, sold IP to Monark Markets | 2023 | — |
| **Dibbs** | Shut down its retail marketplace, **pivoted to tokenization-as-a-service** | 2023-03 | The one pivot that worked — see below |
| **Masterworks** | Still operating, the one survivor at scale | — | Closed-end fund structure (not blockchain fractionalization), blue-chip-only ticket sizes, real secondary trading volume |

*Sourced 2026-08-17 — [Let's mourn Rally](https://alternativeassets.substack.com/p/lets-mourn-rally), [The State of Fractional Investing](https://alts.co/the-state-of-fractional-investing/).*

**Why they failed, consistently:** compliance cost (filings, audits, custody) doesn't scale down to lower-ticket assets; sourcing-fee-frontloaded revenue creates a treadmill dependency on constantly launching new pieces instead of serving existing holders; secondary liquidity never materializes, so "retail investors become the exit strategy" instead of getting one. Masterworks is the exception, and it's the exception specifically because of scale and average ticket size neither this catalog nor most of the failed comps had.

**The one relevant success pattern:** Dibbs didn't fix the retail marketplace — it **stopped running one** and became an infrastructure vendor to other issuers instead. That's Option B below.

---

## Option A — UnyKorn is the issuer

`ArtEditionSPV` names UnyKorn LLC as SPV manager. `relics.unykorn.ai` markets pieces directly with pricing and a buy flow. This is the path the repo is currently on by default.

**What UnyKorn takes on:**
- Reg A+ Tier 2 audit cost and Form 1-A drafting liability, per active SPV
- Ongoing 1-K/1-SA/1-U filing obligations
- Offering-circular disclosure liability (Rule 10b-5 exposure if any claim about a piece — authentication, provenance, appraisal — turns out wrong)
- The exact unit-economics problem in the comparable-platform table: compliance cost against a collectibles ticket size, not a blue-chip-art ticket size

**Fits:** if the goal is to *be* a Masterworks-for-collectibles company, own the whole stack, and the SPV/audit overhead is treated as the cost of owning the upside.

## Option B — UnyKorn is the infrastructure vendor

`ArtEditionSPV` / `ArtCustodyReceipt` / the IPFS pipeline / the BitGo wallet-provisioning script get licensed to whoever actually sponsors an offering — LD Capital, Bottega Mortet or OG4ever directly, or a licensed platform partner. UnyKorn charges setup + SaaS + attestation fees (the same taxonomy already used elsewhere in the stack) and never signs an offering circular.

**What UnyKorn avoids:**
- Issuer liability and audit cost entirely
- The exact failure pattern in the table above
- Any inconsistency with the standing posture already locked in for the rest of the platform

**What UnyKorn keeps:** the actual product — the contracts, the rights-review discipline, the IPFS/BitGo pipeline — as licensable infrastructure regardless of who's the issuer on any given piece. Nothing built so far is wasted under this option; only who operates the storefront and signs the 1-A changes.

**Consistency check, not a new argument:** [`unykorn-brand`](../README.md) already states the standing posture for every other vertical on this stack — *"Unykorn is the GATEWAY AND RAILS, never the funder... paid for enabling the transaction (technology and service fees), not for taking the risk."* Relics, as currently built, is the one vertical where that posture isn't being applied. Option B is the option that makes Relics consistent with everything else UnyKorn has already decided.

---

## Recommendation

Given the comparable-platform record above, **Option B carries materially lower failure risk** — it removes the exact unit-economics mismatch (compliance cost vs. ticket size) that took down seven of eight direct comps, and it's the one pattern (Dibbs' pivot) that's actually held up. It's also the option that doesn't require a new exception to a posture already decided everywhere else on the stack.

This doesn't have to be all-or-nothing per piece: Option B as the default, with Path C (custody receipts, no securities exposure at all) as the primary product for most of the catalog, and Option A reserved for the rare flagship piece where a properly capitalized sponsor — not UnyKorn — wants to run a Reg A+ offering and can absorb the audit overhead.

**Open — needs an operator decision, not an engineering one:** which option `relics.unykorn.ai` actually launches under. The site currently reads as Option A by default. If Option B is chosen, the storefront, the "Buy" flow copy, and the SPV-manager field in `ArtEditionSPV.sol`'s deployment parameters all need to change before this goes further — see the [status legend](../README.md#status-legend) for what's still GATED either way.
