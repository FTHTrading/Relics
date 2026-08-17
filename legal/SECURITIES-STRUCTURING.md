# Securities structuring

Four ways a cleared piece can reach a buyer, what each one actually requires, and why the choice isn't a preference — it's dictated by the Howey analysis and the offering size/audience.

This document is engineering-adjacent legal reference, **not legal advice**. Every figure below is dated and sourced; none of it substitutes for securities counsel sign-off before a real offering document is filed. See the [status legend](../README.md#status-legend) convention — nothing here is described as decided unless it's decided.

---

## The Howey question, applied

An SEC investment contract exists when there is (1) an investment of money, (2) in a common enterprise, (3) with a reasonable expectation of profit, (4) derived from the efforts of others.

Every fractional-share sale on this stack satisfies (1) and (2) by construction — money changes hands into a pooled SPV. The design lever is (3) and (4):

- **`ArtEditionSPV`** (Path A / B / D below) is built to satisfy all four prongs deliberately — it's a security, and the contract's KYC gate, transfer restrictions, and `IComplianceModule` hook exist because of that, not despite it.
- **`ArtCustodyReceipt`** (Path C) is built to fail prong (3)/(4) deliberately — there's no pool, no management, no expectation of profit from anyone else's effort. It's a bailment/title instrument. The moment marketing copy for a Custody Receipt implies appreciation, a resale market, or "invest," that framing risks flipping it back into a security by conduct rather than by contract — see the [copy discipline note](#path-c--custody-receipt-non-security) below.

---

## Path A — Regulation A+, Tier 2

**What it is:** a qualified public offering. Broadest reach, highest cost, only exemption that lets a retail (non-accredited) buyer in at scale with no state-by-state registration.

| | |
|---|---|
| Offering cap | **$75M per rolling 12 months** |
| Investor eligibility | Public — retail and accredited |
| Non-accredited investor limit | **10% of the greater of annual income or net worth**, per investor |
| SEC review | Yes — Form 1-A must be qualified by SEC staff before any sale closes |
| Financials | **Audited financials required** in the offering circular, not added later |
| Ongoing reporting | Form 1-K (annual), Form 1-SA (semiannual), Form 1-U (material events) |
| State registration | Preempted for Tier 2 (this is the whole point of choosing Tier 2 over Tier 1) |
| Typical timeline | Several months of SEC review before qualification; "testing the waters" solicitation is allowed pre-filing |
| Typical cost | $40k–$80k to first qualification, then $15k–$25k/yr per active SPV for audit + filings (per-SPV estimate, not per-catalog) |
| Contract | `ArtEditionSPV` |

*Sourced: SEC Reg A Tier 2 requirements, current as of 2026 — [DealMaker: Reg A Tier 1 vs Tier 2](https://www.dealmaker.tech/content/the-difference-between-tier-1-and-tier-2-of-regulation-a).*

**Fits:** flagship pieces with no living-person depiction, or fully documented consent, where the audience is genuinely retail and the piece can justify the audit overhead.

---

## Path B — Regulation D, Rule 506(c)

**What it is:** a private placement, accredited-investors-only, no SEC review.

| | |
|---|---|
| Offering cap | None |
| Investor eligibility | **Accredited only** — issuer must take reasonable steps to verify accreditation (506(c) allows general solicitation in exchange for this) |
| SEC review | No — Form D is a notice filing within 15 days of first sale, not a review |
| Financials | No audit requirement |
| Ongoing reporting | None federally (state notice filings + fees still apply per state) |
| Resale | Restricted securities — typically a 6–12 month holding period (Rule 144) before any resale, longer for non-reporting issuers |
| Typical timeline | Weeks, not months |
| Contract | `ArtEditionSPV` |

**Fits:** a piece with some documented relationship to a living subject (e.g. the artist photographed with them at signing) that needs a private release rather than full public clearance, or any piece where the sponsor wants to move fast with a smaller qualified buyer set — and can convert to Path A later once there's a track record.

---

## Path D — Regulation Crowdfunding (Reg CF)

**Not yet in the architecture diagram — added here as the missing bridge option.** Retail-eligible like Path A, but far cheaper and faster; the natural way to test real demand before committing to Tier 2's audit overhead.

| | |
|---|---|
| Offering cap | **$5M per rolling 12 months** (Rule 100(a)(1); the rolling window is measured from each closing's own anniversary, not the calendar year) |
| Investor eligibility | Public — retail and accredited, subject to per-investor annual investment limits scaled to income/net worth |
| Distribution | **Must run through a registered funding portal or broker-dealer** — cannot be sold directly off `relics.unykorn.ai` |
| SEC review | No formal qualification — Form C filing, not a 1-A review |
| Financials | Scales with raise size: reviewed financials at lower tiers, audited above a threshold |
| Ongoing reporting | Form C-AR annually |
| Resale | 12-month restriction for most purchasers |
| Typical timeline | Weeks to ~2 months, funding-portal-dependent |
| Contract | `ArtEditionSPV` (same contract as A/B — only the exemption and distribution channel differ) |

*Sourced: SEC 2026 Reg CF Compliance & Disclosure Interpretations, Feb 2026 — [Crowdfunding Attorney: SEC Issues New Reg CF Guidance](https://crowdfundingattorney.com/2026/03/17/sec-issues-new-reg-cf-guidance/).*

**Fits:** a mid-tier piece where the goal is proving retail demand exists before spending Path A money, or a smaller flagship piece that doesn't need $75M of headroom. Requires picking a funding-portal partner — this repo doesn't build one, and per [`BUSINESS-MODEL-OPTIONS.md`](./BUSINESS-MODEL-OPTIONS.md), building one in-house is exactly the mistake the failed comps made.

---

## Path C — Custody receipt (non-security)

**What it is:** title, not an investment. One token, one physical item, no pool.

| | |
|---|---|
| Offering cap | N/A — not a securities offering |
| Investor eligibility | Anyone, no accreditation, no per-person cap |
| SEC review | None |
| Financials | None required |
| Ongoing reporting | None (still subject to general consumer-protection and custody law) |
| Resale | Freely transferable wallet-to-wallet, or redeemable for physical delivery at any time |
| Typical timeline | As fast as authentication + custody onboarding takes |
| Contract | `ArtCustodyReceipt` |

**Copy discipline note:** this path stays a non-security only if the marketing stays a bailment story, not an investment story. No "returns," no "appreciation," no implied pooled upside, no framing that a buyer is relying on UnyKorn's efforts for profit. The moment that language appears next to a Custody Receipt listing, the SEC doesn't care what the contract is named — it looks at the whole offering by substance. Site copy for Path C listings should be reviewed against this before publishing, same as any other legal claim on the site.

**Fits:** trading cards, and any piece where the buyer wants outright ownership rather than a fractional stake — this is the path with the cleanest legal profile and, per the market-precedent research in `BUSINESS-MODEL-OPTIONS.md`, the only piece of the comparable-platform landscape that hasn't produced a graveyard of shutdowns.

---

## Decision table

| Question | Answer | Path |
|---|---|---|
| Is it a security at all, or does the buyer just want the object? | Just the object | **C** |
| Is the audience retail, and is the piece worth $75M-cap overhead? | Yes | **A** |
| Is the audience accredited-only, moving fast? | Yes | **B** |
| Is the goal proving retail demand before committing to Tier 2 cost? | Yes | **D** |
| Deceased-person estate rights, unlicensed photo, undocumented likeness, or unresolved trademark/logo exposure? | — | **Blocked** — see [catalog](../catalog) and the [trademark/logo axis note](../README.md#structuring-paths) |

---

*Not legal advice. Every path above needs securities counsel sign-off on the specific offering before a dollar is raised. See [`BUSINESS-MODEL-OPTIONS.md`](./BUSINESS-MODEL-OPTIONS.md) for the separate, and arguably more important, question of who should be the issuer running any of this.*
