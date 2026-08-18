# Lynn Agent Fabric demo — CHECKPOINT (resume here)

_Last updated: 2026-08-18. Fictional "Lynn Las Vegas" resort+casino Agent Fabric demo._

## ✅ COMPLETE — DEMO-READY (2026-08-18)
The native Agent Fabric itinerary agent is **built, deployed, tested, fixed, and demo-ready.**
End-to-end verified: **happy path 100%, confirmation code 100%, no `-32602`, no graph crashes,
age-gate fail-closed, 0 governance leaks.** Full write-up: **`docs/LYNN-ITINERARY-AGENT-TEST-REPORT.md`**.

- **Broker URL (paste into `agent-broker-ui`):** `https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/`
  (agent card at `…/.well-known/agent-card.json`; A2A needs header `A2A-Version: 1.0` + method `SendMessage`).
- **Demo prompt:** "Create a personalized resort itinerary for my stay. My reservation confirmation is
  LYNN-ALEX01. Include dining, entertainment, and any offers I'm eligible for." (or player id `LR-100002`).
- **What it shows:** Alex Carter (Black tier) · family-aware (minor in party) · $500 BLKDINE + 2-for-1 Le Rêve
  offers · pre-booked SW Steakhouse respected · **21+ gaming suppressed** (fail-closed governance).
- **Three fixes applied & deployed** (see report §10–§13):
  1. Graph (`lynn-itinerary-agent/brokers/lynn-itinerary-agent.agent`, deployed ver `ed424534`) — front-loaded
     `resolveGuest` (getReservation first → resolves confirmation codes) + `identityRouter`→`fallbackResponse`
     + loop caps 5→8.
  2. `lynn-casino-gaming` — nullable tool-param schemas (`["string","null"]`) + `""→null` normalization → kills
     the `-32602` "null found, string expected" errors.
  3. `lynn-casino-gaming` — age-gate hardened **fail-closed** (suppress age-restricted offers when party
     composition unknown).
- **All pushed to GitHub** (`guhaanirban999`): `lynn-casino-gaming` (`95315b2`), `lynn-agent-fabric`
  (report + `lynn-itinerary-agent/` broker code, `f1e2eb6`), `lynn-resort-systems` & `lynn-interests` in sync.
- **Remaining (optional):** P2 governance polish (Flex/Omni Gateway OAuth2, Exchange/Agent Registry, Agent
  Visualizer). Known infra note: `lynn-demo-gw` is a **shared-space managed Flex Gateway** — its raw logs are
  NOT API-accessible; use API Manager Analytics / Anypoint Monitoring (UI) if needed.

_(Everything below is earlier-phase history, kept for context.)_

## ⚠️ REDESIGN (v2, 2026-08-16) — Casino Itinerary backlog
The demo was re-scoped to the **Casino Itinerary** backlog: **3 governed MCPs**
(Reservation Context / Entertainment Interests / Casino & Partner Offers) + **1 single
itinerary orchestrator agent** (Langflow A2A) + **full governance** (Flex/Omni Gateway
OAuth2, PII masking, age rules, Exchange/Agent Registry, monitoring). Authoritative spec:
**`docs/casino-itinerary-redesign.md`** (contracts + 16-story traceability + phased plan).
Phases: **P0 data ✅ DONE** (ran `lynn-demo-db/04_itinerary_schema.sql` + `05_itinerary_seed.sql`
on Aiven `lynn_demo` — taxonomy/offerings/promotions/interests + hero party w/ minor@12,
`v_offerings`=25). NEXT = **P1 reshape apps** (resort→MCP-A, casino→MCP-C, +new MCP-B),
then P2 governance, P3 single Langflow agent (HF Space), P4 broker+monitoring.
Langflow now hosts ONE agent, not 3. Railway trial OOMs Langflow → use **HF Spaces**
(files in `langflow-space/`). The section below is the SUPERSEDED v1 plan.

## 👉 START HERE (resume 2026-08-17)

**Backend is DONE.** All 3 MCPs built + deployed to CloudHub + smoke-tested + on GitHub;
`casino_demo` (v3, 17 tables) live on Aiven and verified healthy (baseline = only LYNN-ALEX01).

**Decision (2026-08-16): drop Langflow.** The itinerary agent will be a **native Agent
Fabric / MuleSoft agent** (AI-Inference connector LLM loop + MCP client over the 3 MCP
servers, exposed via A2A), NOT Langflow — to showcase Agent Fabric's own agentic
capability. HF Space / Langflow no longer needed.

**NEXT = P3:** build+deploy the native itinerary agent in MuleSoft Vibes. The paste-ready
Vibes prompt was provided in chat (app name `lynn-itinerary-agent`, model claude-sonnet-4-6,
3 MCP tool clients, A2A exposure, orchestrator system prompt). When deployed, grab the
**A2A agent-card URL** + `POST /chat` URL → Claude runs the hero-prompt smoke test.

**Then P4:** set `lynn-concierge-broker/exchange.json` (`itineraryAgent.url` = agent card,
`ingressgw.url`, anthropic/openai) → deploy broker → point `agent-broker-ui` at it → e2e.
**P2 governance** (Flex/Omni Gateway OAuth2 + Exchange/Agent Registry + Agent Visualizer)
layers on after.

### MCP server URLs (CloudHub, all on casino_demo, POST /mcp)
- MCP-A `https://lynn-resort-systems-esulje.2tku8l.usa-e1.cloudhub.io/mcp`
- MCP-B `https://lynn-interests-esulje.2tku8l.usa-e1.cloudhub.io/mcp`
- MCP-C `https://lynn-casino-gaming-esulje.2tku8l.usa-e1.cloudhub.io/mcp`

### Known non-blocking nits
- MCP-A `getReservation` 404 returns generic `{"status":"error"}` not clean not-found.
- MCP-C TIME fields still serialize with a `1970-01-01` prefix.

_(The Langflow-based plan below is SUPERSEDED — kept for history.)_

## Architecture
```
User → agent-broker-ui (Railway) → Lynn Concierge broker (CloudHub, Agent Fabric)
        → orchestrates 3 A2A agents (Langflow) → each calls a MuleSoft MCP server (CloudHub) → Aiven MySQL
```

## Status
| Piece | State |
|---|---|
| Aiven MySQL `lynn_demo` (8 tables + seed) | ✅ live; reset to baseline (`lynn-demo-db/03_reset_demo.sql`) |
| 3 MCP servers (resort / interests / casino) | ✅ built, tested, GitHub, deployed to CloudHub (casino_demo) |
| `lynn-casino-gaming` null-param + fail-closed fixes | ✅ deployed + pushed (`95315b2`) |
| **Native Agent Fabric itinerary agent** (`lynn-itinerary-network`) | ✅ **built, deployed (ver `ed424534`), fixed, verified 100%** |
| A2A broker endpoint + demo | ✅ **live & demo-ready** (URL above; report §13) |
| Broker code + test report on GitHub | ✅ pushed to `lynn-agent-fabric` (`f1e2eb6`) |
| P2 governance polish (Gateway OAuth2, Exchange/Registry, Visualizer) | ⬜ optional follow-up |

## Key URLs
- Resort MCP: `https://lynn-resort-systems-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
- Gaming MCP: `https://lynn-casino-gaming-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
  (health/REST at same host minus `/mcp`; MCP transport = Streamable HTTP, `2025-06-18`)
- GitHub: `github.com/guhaanirban999/lynn-resort-systems`, `…/lynn-casino-gaming` (private)
- Front-end (existing): `https://agent-broker-ui-production.up.railway.app/`

## Langflow agent → MCP mapping (what to build)
| Flow | MCP server | Tools |
|---|---|---|
| Rooms & Suites | resort | search_rooms, book_room |
| Dining | resort | list_restaurants, check_dining_availability, book_dining |
| Casino / Gaming Host | gaming | lookup_guest, search_tables, check_table_availability, reserve_table, evaluate_comp, issue_comp |
System prompts for each are in `docs/langflow-build-guide.md` (Steps 3, 5, 6).

## Things you'll need tomorrow
- **Anthropic API key** for the Langflow Agent components (Claude `claude-sonnet-4-6`).
- A **Railway** account for the Langflow host (→ `LANGFLOW_URL`).
- Aiven DB password + `secure.key` (value kept out of repo — set at runtime) already set on CloudHub; the
  encrypted `db.password` lives in each app's `secure.yaml`. Aiven plaintext password is
  NOT stored in any repo — it's in the earlier chat/`.env`. (Consider rotating post-demo.)

## After Langflow (for Claude to do)
1. Put the 3 agent-card URLs into `lynn-concierge-broker/exchange.json`
   (`roomsAgent.url`, `diningAgent.url`, `gamingHostAgent.url`) + `ingressgw.url`, `openai`.
2. Publish/deploy the broker to CloudHub; get its A2A URL.
3. Paste broker URL into `agent-broker-ui`; run the hero prompt end-to-end.

## Doc map (in this folder)
- `docs/langflow-build-guide.md` — **tomorrow's steps**
- `docs/lynn-langflow-agents.md` — agent specs (prompts, tools, MCP URLs)
- `docs/lynn-mcp-contracts.md` — MCP tool/API contracts
- `docs/vibes-prompts.md` — how the Mule apps were built
- `docs/DEPLOY.md` — overall deploy order
- `lynn-demo-db/` — schema, seed, reset SQL
- `lynn-concierge-broker/` — broker (agent-network.yaml, .agent, exchange.json)
