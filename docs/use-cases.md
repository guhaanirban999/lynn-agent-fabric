# Casino Itinerary Agent Fabric — Demo Use Cases

Demo script for the v2 design (`casino-itinerary-redesign.md`). Each use case gives the
guest prompt, the tool sequence the **single itinerary orchestrator agent** runs across
the 3 MCPs (Reservation Context / Entertainment Interests / Casino & Partner Offers), and
the expected outcome against the seeded data (`04_itinerary_schema.sql` + `05_itinerary_seed.sql`).

## Seed facts referenced
- **Hero:** Alex Carter, `LR-100002`, **Black** tier, confirmation **`LYNN-ALEX01`**, Sep 19–21 2026.
- **Party:** Alex 44 (adult/primary) · Jordan 41 (adult) · **Sam 12 (minor)** → `has_minors=true`, youngest=12.
- **Interests:** explicit gaming 0.90, dining 0.80, entertainment 0.60; inferred nightlife 0.40, wellness 0.30.
- **Offerings:** Le Rêve show, The Spa at Lynn (18+), Encore Beach Club (nightlife, 21+),
  Lynn Esplanade Shops; partners: Cirque Aqua Show, Grand Canyon Helicopter Tour, Bottega Luxe.
- **Promotions:** Black Dining Credit ($500), Chairman Spa Comp ($750, 18+),
  High-Limit Match Play ($1000, Black, 21+), Show Ticket 2-for-1 (all tiers).
- **Nevada rule:** gaming/alcohol/nightlife = 21+; `age_band` adult ≥ 21.

---

## UC-1 — Family stay with a minor (hero flow)
**Prompt:** "I'm Alex Carter, confirmation LYNN-ALEX01. Plan our two nights — we've got a
12-year-old with us. Mix in what we like and apply any comps I qualify for."
**Flow:** `getReservation` (anchor Sep 19–21, Black) → `getPartyComposition`
(**has_minors=true**, youngest=12) → `getInterests` → `getOfferings`/`getEligibleOffers`
**with `confirmation_code`** → assemble → `reserveOffering`.
**Expected:** Le Rêve show, SW Steakhouse dinner, Esplanade shopping, Grand Canyon tour.
**Gaming, Encore Beach Club (21+), and High-Limit Match Play are suppressed** (minor present).
**Black Dining Credit ($500)** applied.
**Covers:** US-1.1, 1.2, 1.3, 2.1, 3.1, 3.3, **3.4**, 4.2.

## UC-2 — Solo high-roller, no minors
**Prompt:** "It's just me this trip (LR-100002) — I want a big gaming night with the works."
**Flow:** `getReservation`/`getPartyComposition` (no minors) → `getInterests` →
`getOfferings`/`getEligibleOffers` **without minor suppression** → `reserveOffering`.
**Expected:** High-Limit Baccarat table, **High-Limit Match Play ($1000)** comp, Encore
Beach Club, SW Steakhouse — nothing suppressed. Same guest, very different itinerary
because party context changed.
**Covers:** contrast to UC-1 (age gating on/off), 3.1, 3.3.

## UC-3 — Update interests, then re-plan
**Prompt:** "Actually we're really into wellness and shopping this trip — less gaming."
**Flow:** `updateInterests` (wellness↑, shopping↑, gaming↓ → **version bumps**, history row
written) → re-run `getInterests` → re-assemble.
**Expected:** Plan re-weights toward The Spa at Lynn + Bottega Luxe. Chairman Spa Comp
does **not** appear (Alex is Black, not Chairman) — clean tier-filter demo. Shows the
write path + versioning.
**Covers:** US-2.3, 2.1, 3.3 (tier filtering).

## UC-4 — Partner experiences beyond the property
**Prompt:** "What can we do off-property or with your partners?"
**Flow:** `getPartnerOfferings`.
**Expected:** Cirque Aqua Show, Grand Canyon Helicopter Tour, Bottega Luxe — each flagged
**`source=partner`** with `partner_name` + `terms`, distinct from owned assets.
**Covers:** US-3.2.

## UC-5 — Reservation lookup + error handling
**Prompt A:** "Look up confirmation LYNN-ALEX01." → returns the stay.
**Prompt B:** "Look up confirmation LYNN-XXXXXX." → **HTTP 404** `{error:"reservation not found"}`.
**Also:** lookup by `player_id=LR-100002` returns the same stay (dual anchor).
**Covers:** US-1.1 (incl. 404 handling).

## UC-6 — Governance / compliance (P2 payoff)
**Prompt:** "Show the guest's contact details."
**Flow:** `getReservation`/`getGuestProfile` **without consent** → name masked
(`A**** C****`), email/phone `null`; **`audit_log` row written**. A call **without a valid
OAuth token** → gateway **401**. With `consent=true` → unmasked + audited.
**Expected:** masking + audit demonstrable now (MCP-A logic); OAuth 401 + policy lights up
fully after P2 gateway wiring.
**Covers:** US-1.4, 4.3.

## UC-7 — Group interests (aggregation)
**Prompt:** "Plan something the whole group of players will enjoy — that's Alex Carter
(LR-100002) and Marcus Lee (LR-100003)."
**Flow:** `getInterests` with `player_ids=LR-100002,LR-100003` → **mean affinity per
category** across members (`ROUND(AVG(affinity),2)`, `members` count) → assemble to the
aggregate profile.
**Expected (from seed):** dining **0.85** (2 members) → shopping 0.60 (1) → entertainment
**0.55** (2) → gaming 0.55 (2) → wellness 0.50 (2) → nightlife 0.40 (1). Note the ranking
is **dining-led**, not gaming-led as it is for Alex alone (UC-1) — the group blend surfaces
Marcus's dining/wellness/shopping tastes. Itinerary balances both guests.
**Covers:** US-2.1 (group-level aggregation).

## UC-8 — Schedule-conflict avoidance
**Prompt:** "Add a show on the 19th — but don't clash with anything we've already booked."
**Flow:** `getScheduleConstraints` (arrival/departure + `prebooked[]` from dining/table/
offering reservations) → agent time-boxes the new item into a free slot → `reserveOffering`.
**Expected:** If SW Steakhouse is booked 8 pm on the 19th, the agent slots Le Rêve at 7 pm
or a later show, never overlapping the prebooked dinner or the arrival/departure window.
**Covers:** US-1.3, 4.2 (deterministic, conflict-free assembly).

---

## Coverage matrix (use case → stories)
| UC | Stories exercised |
|---|---|
| UC-1 | 1.1, 1.2, 1.3, 2.1, 3.1, 3.3, 3.4, 4.2 |
| UC-2 | 3.1, 3.3 (age-gating contrast) |
| UC-3 | 2.3, 2.1, 3.3 |
| UC-4 | 3.2 |
| UC-5 | 1.1 |
| UC-6 | 1.4, 4.3 |
| UC-7 | 2.1 |
| UC-8 | 1.3, 4.2 |
| P2/P4 platform | 4.1 (Exchange/Registry), 4.4 (Agent Visualizer trace) — shown live, not prompt-driven |

Stories 4.1 and 4.4 are platform capabilities demonstrated via Anypoint Exchange/Agent
Registry (discoverability) and Agent Visualizer/Monitoring (end-to-end trace) rather than
a guest prompt.
