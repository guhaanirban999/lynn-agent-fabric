# Lynn Agent Fabric demo — CHECKPOINT (resume here)

_Last updated: 2026-08-16. Fictional "Lynn Las Vegas" resort+casino Agent Fabric demo._

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
| `lynn-resort-systems` Mule app (REST+MCP) | ✅ built, tested, GitHub, **deployed to CloudHub** |
| `lynn-casino-gaming` Mule app (REST+MCP) | ✅ built, tested 14/14, GitHub, **deployed to CloudHub** |
| Concierge broker scaffold | ✅ in `lynn-concierge-broker/` (needs agent URLs, then deploy) |
| **3 Langflow agents** | ⬜ **NEXT — build these** |
| Wire broker `exchange.json` + deploy broker | ⬜ after agent URLs |
| Point `agent-broker-ui` at broker + end-to-end demo | ⬜ last |

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
