# Casino Itinerary Agent Fabric — Redesign (v2)

Supersedes the original "3 flat domain agents (rooms/dining/gaming)" design. This
build delivers the **Casino Itinerary** backlog: 3 governed MCPs + one itinerary
orchestrator agent, on top of the existing `lynn_demo` DB and CloudHub apps.

**Locked decisions:** extend `lynn_demo` + reshape the 2 apps · **full governance**
(Flex/Omni Gateway OAuth2, PII masking, age policies, Agent Registry, monitoring) ·
**single itinerary agent** over 3 MCPs.

---

## 1. Target architecture

```
Guest → agent-broker-ui (HF/Railway)
      → Agent Fabric Broker (CloudHub)                 ── plans & routes ──►
        └─ Itinerary Orchestrator Agent (Langflow A2A, on HF Space)
             ├─ MCP-A Reservation Context   (CloudHub)  ─┐
             ├─ MCP-B Entertainment Interests(CloudHub)  ─┤─ all fronted by
             └─ MCP-C Casino & Partner Offers(CloudHub)  ─┘  Flex/Omni Gateway
                                     │
                              Aiven MySQL  (lynn_demo, v2 schema)
```

- **One** Langflow agent connects to all **3** MCP servers and runs the plan
  `reservation → interests → offers → assemble`. The broker routes intent to it.
- Every MCP + the A2A endpoint sits behind **Flex/Omni Gateway** (OAuth2, rate
  limits, PII/age policies, token metrics). MCPs published to **Anypoint Exchange /
  Agent Registry**. End-to-end trace in **Agent Visualizer / Anypoint Monitoring**.

### App reshape (from today's 2 apps → 3 MCPs)
| Today | Becomes | Notes |
|---|---|---|
| `lynn-resort-systems` | **MCP-A Reservation Context** | keep DB conn; swap tools to read-only reservation/party/schedule/profile. Room search/book move under Offers assembly. |
| `lynn-casino-gaming` | **MCP-C Casino & Partner Offers** | extend to unified `v_offerings`, partners, promotions, age suppression, `reserveOffering`. |
| *(new app)* | **MCP-B Entertainment Interests** | new: interests (explicit+inferred), updateInterests, taxonomy. |

---

## 2. Data model (v2)

Migration in `lynn-demo-db/04_itinerary_schema.sql`; seed in `05_itinerary_seed.sql`.
New/changed objects:

- `room_reservations` **+** `confirmation_code`, `arrival_time`, `departure_time`, `comp_tier`
- `party_members` — per-guest `age` + generated `age_band` (adult ≥ 21, else minor), `is_primary`
- `taxonomy_categories` — canonical: **gaming, dining, shopping, entertainment, wellness, nightlife**
- `guest_interests` (+ `guest_interests_history`) — `affinity` 0..1, `source` explicit|inferred, `version`
- `partners`, `offerings`, `offering_reservations`, `promotions`
- `v_offerings` — one catalog surface unioning restaurants (dining) + gaming_tables (gaming) + offerings (rest)
- `audit_log` — governed-access audit trail

**Nevada rule baked in:** age band and `min_age` use **21** for gaming/alcohol/nightlife;
the hero party seeds a **minor (age 12)** to prove suppression.

---

## 3. MCP tool contracts

Field names are the tool schema the Langflow MCP client will see. JSON everywhere;
dates `YYYY-MM-DD`, datetimes `YYYY-MM-DD HH:MM:SS`.

### MCP-A — Reservation Context  (OAuth2 + PII masking + audit)
| Tool | Args | Returns | Story |
|---|---|---|---|
| `getReservation` | `confirmation_code` \| `player_id` (LR-…) | `{confirmation_code, guest{...masked}, check_in, check_out, nights, room_type, comp_tier, status}`; **404** if unknown | 1.1 |
| `getPartyComposition` | `confirmation_code` | `{party_size, members:[{age, age_band}], has_minors:bool}` (names masked unless consented) | 1.2 |
| `getScheduleConstraints` | `confirmation_code` | `{arrival_time, departure_time, nights, prebooked:[{type, name, datetime}]}` (from dining/table/offering reservations) | 1.3 |
| `getGuestProfile` | `player_id` | `{name(masked), tier, points_balance, credit_line}` | supports 3.3 |

- **PII masking:** `email`/`phone`/full name masked by default; unmasked only with a
  `consent=true` context claim from the gateway. Every call writes `audit_log`. (1.4)

### MCP-B — Entertainment Interests
| Tool | Args | Returns | Story |
|---|---|---|---|
| `getInterests` | `player_id` \| `player_ids[]` (group) | ranked `[{category_code, affinity, source}]`; group call aggregates (mean affinity) | 2.1 |
| `getInferredInterests` | `player_id` | inferred rows only, derived from play/visit history; `source='inferred'` clearly flagged | 2.2 |
| `updateInterests` | `player_id`, `interests:[{category_code, affinity}]` | writes `explicit`, bumps `version`, snapshots to history; returns new version | 2.3 |
| `getTaxonomy` | — | canonical category list (shared with Offers) | 2.4 |

### MCP-C — Casino & Partner Offers  (age/jurisdiction enforcement)
| Tool | Args | Returns | Story |
|---|---|---|---|
| `getOfferings` | `category_code?`, `date?`, `time_from?`, `time_to?` | from `v_offerings`: `[{offering_ref, name, source, category_code, subcategory, location, opens, closes, capacity, min_age}]` | 3.1 |
| `getPartnerOfferings` | `category_code?` | partner-source rows w/ `partner_id`, `terms`, availability; distinguishes owned vs partner | 3.2 |
| `getEligibleOffers` | `player_id`, `confirmation_code?` | promotions/comps filtered by `tier` (+ reservation); each w/ `redemption_rules`, `valid_to` | 3.3 |
| `reserveOffering` | `player_id`, `offering_ref`, `datetime`, `party_size` | inserts `offering_reservations`; returns reservation id | assembly |

- **Age/jurisdiction (3.4):** if `getPartyComposition.has_minors` is true, `getOfferings`/
  `getEligibleOffers` **suppress** any row with `min_age ≥ 21` (gaming, nightlife, 21+
  promos). Enforced in MCP SQL/logic, not just prompt.

---

## 4. Itinerary Orchestrator agent (Langflow, single)

One "Simple Agent" flow, **3 MCP Tools components** (one per server), A2A enabled.
System-prompt plan:

> You are the Casino Itinerary Orchestrator for Lynn Las Vegas. Given a confirmation
> code or player ID: (1) `getReservation` to anchor dates/tier and `getPartyComposition`
> to learn party size, ages, and whether **minors** are present; (2) `getInterests`
> (group-aggregate if multiple players) to weight categories; (3) `getOfferings` +
> `getEligibleOffers` within the stay window — **never propose an offering or promo whose
> min_age exceeds any party member's age**; (4) assemble a conflict-free, time-boxed
> itinerary across the nights, and `reserveOffering` for chosen items. Return a per-day
> plan with times, category, owned/partner source, and any comps applied. If a step fails,
> continue with partial context and note the gap.

Broker (`lynn-concierge-broker`, re-themed) routes itinerary intents to this agent and
synthesizes the final reply. (4.2)

---

## 5. Full governance plan (Epic 4)

| Control | How | Story |
|---|---|---|
| **OAuth2** on every MCP + A2A | Flex/Omni Gateway **OAuth 2.0 Access Token Enforcement** policy; client-credentials app in Anypoint (or external IdP). Broker/agent present bearer token. | 1.4, 4.3 |
| **Rate limiting / SLA** | Gateway rate-limit-SLA policy per client. | 4.3 |
| **PII masking** | MCP-A masks by default; gateway injects `consent` claim; masked fields never logged. | 1.4 |
| **Age/jurisdiction** | Enforced in MCP-C logic (min_age vs party) + gateway header check. | 3.4 |
| **Token spend tracking** | Agent Fabric token metrics per agent/MCP call. | 4.3 |
| **Agent Registry / Exchange** | Publish each MCP as an Exchange asset (schema + version); register the agent in Agent Registry so the broker reuses them as governed tools. | 4.1 |
| **Monitoring / trace** | Anypoint Monitoring + Agent Visualizer: full trace agent→each MCP→response, demo-ready view. | 4.4 |

DX MCP tools that help build this: `manage_flex_gateway_policy_project`,
`get_flex_gateway_policy_example`, `manage_api_instance_policy`,
`create_and_manage_api_instances`, `create_mcp_server`, `create_and_manage_assets`,
`get_platform_insights`, `get_reuse_metrics`.

---

## 6. Backlog traceability (16 stories)

| Story | Delivered by |
|---|---|
| 1.1 | MCP-A `getReservation` (404 handling) |
| 1.2 | MCP-A `getPartyComposition` (ages, age_band, has_minors) |
| 1.3 | MCP-A `getScheduleConstraints` (window + prebooked events) |
| 1.4 | Gateway OAuth2 + MCP-A PII masking + `audit_log` |
| 2.1 | MCP-B `getInterests` (ranked + group aggregate) |
| 2.2 | MCP-B `getInferredInterests` (explicit vs inferred flag) |
| 2.3 | MCP-B `updateInterests` (validated, versioned + history) |
| 2.4 | `taxonomy_categories` shared by B & C; `getTaxonomy` |
| 3.1 | MCP-C `getOfferings` over `v_offerings` (hours/capacity/tags) |
| 3.2 | MCP-C `getPartnerOfferings` (owned vs partner) |
| 3.3 | MCP-C `getEligibleOffers` (tier-filtered comps/promos + rules/expiry) |
| 3.4 | MCP-C age/jurisdiction suppression (min_age vs party) |
| 4.1 | Publish MCPs to Exchange / Agent Registry |
| 4.2 | Broker plans/routes reservation→interests→offers→assemble; partial-failure handling |
| 4.3 | Gateway OAuth2 + rate limits + PII/age policies + token tracking |
| 4.4 | Agent Visualizer / Anypoint Monitoring end-to-end trace |

---

## 7. Phased build plan

- **P0 — Data:** run `04_itinerary_schema.sql` + `05_itinerary_seed.sql` on Aiven `lynn_demo`; verify `v_offerings` + hero party (minor present).
- **P1 — MCPs:** reshape `lynn-resort-systems`→MCP-A, `lynn-casino-gaming`→MCP-C (Vibes), build new MCP-B; unit-test tools; redeploy to CloudHub.
- **P2 — Governance:** Flex/Omni Gateway in front of each MCP; OAuth2 + rate limit + PII/age policies; publish to Exchange/Agent Registry.
- **P3 — Agent:** build the single Itinerary Orchestrator flow in Langflow (HF Space), wire 3 MCP clients (with OAuth), enable A2A, get card URL.
- **P4 — Broker + demo:** point broker at the agent card, deploy to CloudHub, wire monitoring/Agent Visualizer, run the hero prompt end-to-end.

### Hero demo prompt
> "I'm **Alex Carter, confirmation LYNN-ALEX01**. Plan our two nights — we've got a
> **12-year-old** with us. Mix in what we like, keep it family-appropriate where it
> has to be, and apply any comps I qualify for."

Expected: itinerary spans dining/entertainment/shopping/wellness for the group;
**gaming, Encore Beach Club, and 21+ promos are suppressed for group activities**
because a minor is present; Black-tier dining credit applied. Demonstrates every epic.
