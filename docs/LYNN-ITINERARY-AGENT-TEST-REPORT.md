# Lynn Itinerary Agent — Test Report (curl / A2A)

**Date:** 2026-08-17
**Target:** `https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/`
**Method:** direct A2A calls via `curl` (no MCP client, no Langflow UI)
**Env:** Anypoint **Sandbox** (`57d1cceb-…`), org `0f5adde5…` (cognizant), CloudHub 2.0 **usa-e2**

---

## 1. Verdict

| Layer | Status |
|---|---|
| A2A endpoint + Flex Gateway routing | ✅ Working |
| Agent LLM reasoning (OpenAI via gateway `:8082`) | ✅ Working |
| Multi-turn context (`contextId` preserved) | ✅ Working |
| Clarification UX (asks for id when missing) | ✅ Working |
| Consent-driven PII masking | ✅ Working |
| Age / tier governance (data layer) | ✅ Working |
| **Agent → MCP tool calls (reservation/interests/offers)** | ⚠️ **INTERMITTENT** — the primary issue |
| Confirmation-code input resolution | ❌ Not supported (expects `player_id`) |

**Headline finding:** the stack is functionally complete and correct, but the **agent's downstream MCP tool calls fail intermittently**. The *same* request for the hero guest produced three different outcomes on three consecutive runs (COMPLETED / FAILED / INPUT_REQUIRED). When tool calls fail the agent degrades to a partial itinerary, asks for input, or exhausts its `reasoning_iterations` budget and fails.

---

## 2. A2A call recipe (reverse-engineered)

This build speaks **A2A 1.0 with gRPC-style method names** (not the classic JSON-RPC `message/send`).

- **Endpoint:** `POST …/lynn_itinerary_agent/`
- **Required header:** `A2A-Version: 1.0`  *(without it → error `-32009 Unsupported A2A version`)*
- **Method:** `SendMessage`  *(`message/send` → `-32601 Method not found`)*
- **Message shape:** proto `lf.a2a.v1.Message` — fields `messageId`, `role` (enum **`ROLE_USER`**), **`parts`** (`[{"text": "..."}]`), optional `contextId`, `taskId`, `metadata`.

```bash
curl -s https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/ \
  -H "Content-Type: application/json" -H "A2A-Version: 1.0" \
  -d '{"jsonrpc":"2.0","id":"1","method":"SendMessage","params":{"message":{
        "messageId":"m1","role":"ROLE_USER",
        "parts":[{"text":"Create a personalized resort itinerary for guest with player ID LR-100002."}]}}}'
```

Response is an A2A **Task** — `result.task.status.state` ∈ `TASK_STATE_COMPLETED` / `TASK_STATE_INPUT_REQUIRED` / `TASK_STATE_FAILED`; the agent text is in `result.task.status.message.parts[].text`, the itinerary (on success) in `result.task.artifacts[].parts[].text`. `result.task.contextId` carries the conversation id for follow-ups.

> ⚠️ The agent card at `…/.well-known/agent-card.json` is minimal — it does **not** advertise the `SendMessage`/`ROLE_USER`/`parts` requirements. The recipe above was found empirically.

---

## 3. Test data (guest roster)

Discovered via `getGuestProfile` on the resort MCP (note PII masking — only the consented hero shows a full surname):

| player_id | Guest | Tier | Comp/day | Notes |
|---|---|---|---|---|
| LR-100001 | Priya N**** | Chairman | 20 000 | top tier, masked |
| **LR-100002** | **Alex Carter** | **Black** | 5 000 | **hero**, conf `LYNN-ALEX01`, party of 3 **incl. a minor** |
| LR-100003 | Marcus L**** | Red | 0 | low tier, masked |
| LR-100004 | Sofia R**** | Black | 5 000 | masked |
| LR-100005 | David K**** | Red | 0 | masked |
| LR-100006 | Elena P**** | Chairman | 20 000 | masked |

Hero reservation (`getReservation(confirmation_code=LYNN-ALEX01)`): `RES-0001`, 2026-09-19 → 09-21, party 3, `has_minors=true`, "High floor, connecting rooms; travelling with a child".

---

## 4. Use-case results

| # | Use case | Input | State | Outcome |
|---|---|---|---|---|
| UC-1 | Happy path (Black) | `LR-100002` | ⚠️ varies | COMPLETED on some runs; partial/INPUT_REQUIRED on others |
| UC-2 | Top tier (Chairman) | `LR-100001` | ❌ FAILED | "system limit exceeded: **reasoning_iterations**" (retried failing tools until budget blown) |
| UC-3 | Low tier (Red) | `LR-100003` | ⚠️ INPUT_REQUIRED | Got interests + 1 offer; reservation/offering fetch failed |
| UC-4 | Confirmation code | `LYNN-ALEX01` | ❌ INPUT_REQUIRED | Agent treats it as `player_id`; "all requests failed or returned no data" |
| UC-5 | Unknown guest | `LR-999999` | ❌ FAILED | Graceful — empty structured result, no crash |
| UC-6 | Vague, no id | "help me plan my trip" | ✅ INPUT_REQUIRED | Correctly asks for player ID / confirmation code (2s, no wasted calls) |
| UC-7 | Multi-turn follow-up | reuse `contextId` | ⚠️ INPUT_REQUIRED | Context preserved (same ctx id); tools failed again ("temporary service issue") |

### Representative agent messages (verbatim)
- **UC-1 (partial):** *"The necessary data was partially unavailable due to schedule constraints and offering details failing to retrieve. I based the itinerary on confirmed reservation details and promotions available to the guest's Black tier status…"*
- **UC-2 (fail):** *"The task could not be completed because a system limit was exceeded: reasoning_iterations."*
- **UC-3 (partial):** *"…Access to reservation and activity details failed… Marcus is eligible for a 50% discount on show tickets for 'Le Rêve — The Dream'."*
- **UC-4 (conf-code):** *"…using the player's reservation confirmation code LYNN-ALEX01. Unfortunately, all requests failed or returned no data."*
- **UC-6 (clarify):** *"I need the player ID or confirmation code to gather the necessary context… Please provide your player loyalty ID or confirmation code."*
- **UC-7 (follow-up):** *"The tools failed to retrieve reservation details, schedule constraints, eligible offers, and available offerings… This could be due to a temporary service issue…"*

### Sample successful itinerary (UC-1, a good run)
```
## Welcome, Alex Carter!
### Stay Details:  Reservation LYNN-ALEX01 · Check-in 2026-09-19 16:00 · Check-out 2026-09-21 11:00
### Personalized Itinerary
  Day 1  16:00 Arrival & check-in · 20:00 SW Steakhouse dinner ($500 dining credit)
  Day 2  08:00 Grand Canyon Helicopter Tour · 15:00 Leisure · 19:00 2-for-1 show
  Day 3  Morning at leisure before check-out
### Offers:  $500 SW Steakhouse Chef's Table (BLKDINE) · 2-for-1 show (SHOW2)
```

---

## 5. Reliability sample (intermittency)

Identical request (`LR-100002`) three times, back-to-back:

| Run | Time | State |
|---|---|---|
| 1 | 26s | ✅ TASK_STATE_COMPLETED |
| 2 | 23s | ❌ TASK_STATE_FAILED |
| 3 | 18s | ⚠️ TASK_STATE_INPUT_REQUIRED |

→ ~1-in-3 success at time of test. Non-deterministic, consistent with **intermittent connectivity on the agent → MCP-proxy hop** (`http://lynn-demo-gw:8082/{org}/{mcp}/{label}/`).

---

## 6. Governance evidence (works at the data layer)

**Age suppression (21+):** the interests taxonomy marks `gaming` and `table_games` as `is_age_restricted: true (21+)`. Alex's party includes a minor (`has_minors=true`), and `getEligibleOffers(LR-100002 / LYNN-ALEX01)` returns **only family-safe offers** (`min_age: null`):
- `BLKDINE` — $500 Black Dining Credit → SW Steakhouse Chef's Table
- `SHOW2` — Show Ticket 2-for-1 → Le Rêve

No 21+ gaming offers appear → age rule enforced. (Matches the documented 9→6 suppression.)

**Consent-driven PII masking:** roster lookups return masked surnames (`Priya N****`, `Marcus L****`) for non-consented guests while the consented hero (`Alex Carter`) is fully revealed.

**Tier awareness:** offers/comp limits differ by tier (Chairman 20 000 / Black 5 000 / Red 0), and the agent references Black-tier promotions in UC-1.

---

## 7. Direct MCP verification (all healthy)

All three MCP servers respond directly (`initialize` → 200) and return correct data:
- `lynn-resort-systems` — `getReservation(LYNN-ALEX01)` → RES-0001 / Alex Carter / LR-100002 / BLACK ✅
- `lynn-interests` — `getTaxonomy` → categories with age flags ✅
- `lynn-casino-partner-offers` — `getEligibleOffers` → age/tier-filtered offers ✅

So the MCP apps + DB are **not** the failure — the break is specifically the **agent's calls to them via the gateway**.

---

## 8. Root cause & recommendations

**Two distinct issues:**

1. **Intermittent agent→MCP tool failures (primary).** The MCP apps are up and correct when called directly, but the agent (running behind `lynn-demo-gw`) intermittently fails to reach them via the internal proxy `lynn-demo-gw:8082/{org}/{mcp}/{label}/`. Same class as the earlier `:8082` LLM-connectivity failure that crash-looped the broker. When it fails, the agent burns `reasoning_iterations` retrying → FAILED, or degrades to INPUT_REQUIRED.
   - **Action:** stabilise the gateway `:8082` cluster listener / upstream to the usa-e1 MCP hosts (check gateway logs for `:8082` upstream timeouts/resets; confirm the 4 API instances stay *applied*; consider a gateway restart/redeploy). Re-run the reliability sample until 3/3 pass.
   - **Mitigation in agent:** raise/relax `reasoning_iterations`, and add retry/backoff so a transient MCP blip doesn't fail the whole task.

2. **Confirmation-code not resolved (secondary).** The agent maps the given identifier straight into `player_id`; it never calls `getReservation(confirmation_code=…)` to derive the `player_id`.
   - **Action:** update the AgentScript/prompt so a confirmation-code input (e.g. `LYNN-*`) triggers a `getReservation` lookup first. **Workaround for demos: use the player_id (`LR-100002`).**

**Demo guidance until fixed:** drive with **`LR-100002`**, and re-run if a call returns FAILED/INPUT_REQUIRED (intermittent).

---

## 8b. Intermittency root-cause investigation — measured (2026-08-17)

Goal: pin down *where* the intermittency lives. Gateway logs were **not accessible** (the `bea02719…` Connected App gets **403** on all Flex-Gateway management endpoints — needs a *Flex Gateway Viewer* scope), and the agent's per-request traces go to **OTLP (`localhost:4317`) → Anypoint Monitoring**, not the CloudHub log stream (the agent's CloudHub log has only 10 startup lines). So the cause was isolated by **black-box measurement** instead.

### Evidence 1 — the MCP apps are NOT the problem (100% reliable, fast)
Direct calls to each MCP host, 10× each (30 calls total):

| MCP host / tool | Success | True latency* |
|---|---|---|
| resort / `getReservation` | **10/10** | ~0.12–0.20s |
| interests / `getTaxonomy` | **10/10** | ~0.12–0.22s |
| casino / `getEligibleOffers` | **10/10** | ~0.12–0.22s |

\* The 30-call run reported ~30s per call — that is an **SSE-stream-hold artifact** (the MuleSoft MCP servers answer immediately but keep the `text/event-stream` connection open until the client times out). A corrected run with `Accept: application/json` shows the servers actually respond in **~150 ms**. **30/30 returned valid results.**

### Evidence 2 — the agent → gateway(`:8082`) → MCP path IS the problem, and it degrades
Identical request (`LR-100002`) run 8× back-to-back:

| Run | State | Notes |
|---|---|---|
| 1 | ✅ COMPLETED | |
| 2 | ⚠️ INPUT_REQUIRED | |
| 3 | ⚠️ INPUT_REQUIRED | agent reports reservation/schedule/offer/offering fetch failed |
| 4 | ✅ COMPLETED | |
| 5 | ❌ FAILED | `reasoning_iterations` exceeded |
| 6 | ❌ FAILED | `reasoning_iterations` exceeded |
| 7 | ❌ FAILED | `reasoning_iterations` exceeded |
| 8 | ❌ FAILED | `reasoning_iterations` exceeded |

Success rate **2/8 (25%)**, and — critically — **monotonic degradation**: the first 4 runs contain both successes; the last 4 **all** fail with the iteration limit. Every run's wall-time sat in a tight 18–30 s band regardless of outcome (i.e., failures aren't one slow call — they're the agent looping/retrying failed tool calls until its budget is spent).

### Evidence 3 — controlled exhaust→idle→recover test (refutes clean pool exhaustion)
To test whether the failures are progressive **connection-pool exhaustion** (would degrade over runs and recover after idle) vs. **random per-call failure**:

```
PHASE A rapid-fire x5:  A1 COMPLETED · A2 FAILED · A3 COMPLETED · A4 FAILED · A5 FAILED
PHASE B idle 120s
PHASE C after cooldown: C1 INPUT_REQUIRED · C2 FAILED
```

- Phase A is **not monotonic** (A3 succeeds *after* A2 fails) — exhaustion would stay failed once saturated.
- The 120s idle did **not** restore success (C1 partial, C2 failed) — exhaustion would recover after drain.

→ The "first-4-ok / last-4-fail" pattern in Evidence 2 was **largely coincidental**, not a reliable trend.

### Evidence 4 — application logs (DEFINITIVE, supersedes the `:8082` theory)
A 4-hour app-log export (`c34c61_f436ff_2026-08-18T01-50-09Z.log`, 286 lines) shows the **actual** errors. There are **zero** connectivity/timeout/reset/httpx/httpcore errors. The only errors are:

| Count | Logger | Error |
|---|---|---|
| **12** | `runner.graph_runner` | **"Graph completed without triggering any response node — this is a graph authoring error"** |
| 3 | `mcp_tools.tool_executor` | `getEligibleOffers (-32602): Invalid tool parameters: /confirmation_code: null found, string expected` |
| 1 | `mcp_tools.tool_executor` | `getOfferings (-32602): Invalid tool parameters: /category_code: null found, string expected` |
| 7 | `a2a.server.routes.jsonrpc_dispatcher` | "Failed to parse request params" — *test-harness noise (malformed probe requests), ignore* |

So the intermittency is **application-level, not infrastructure**:
1. **The agent passes an explicit `null` for optional string params.** `getOfferings.category_code` and `getEligibleOffers.confirmation_code` are *not* in the tool's `required` list — but their schema type is plain `string`, and the agent sends `null` (instead of **omitting** the field). `null` ≠ `string` → `-32602`. (Direct MCP tests passed only because valid params were supplied.)
2. **The graph has no failure path to a response node.** When that tool error makes a subagent fail / hit `max_number_of_loops`, its `on_exit` never fires and the linear graph ends **without reaching the sole response node** (`itineraryResponse`) → the `graph_runner` error → the caller sees `FAILED`/`INPUT_REQUIRED`. See §10.

This also explains why the earlier exhaust→idle test refuted pool exhaustion: it was never infrastructure — it's **LLM tool-arg variance** (sometimes valid args → success, sometimes `null` → error).

### Conclusion (corrected)
- ✅ MCP servers + DB healthy (30/30 direct, ~150ms) — confirmed.
- ❌ **`:8082` connectivity / pool exhaustion — RULED OUT** (no connection/timeout errors in 4h of logs).
- ✅ **Real cause = two application bugs:** (a) agent sends `null` for optional `string` tool params → `-32602`; (b) the graph has no error/fallback transition to a response node, so any tool error becomes a response-less hard failure (12× in 4h).
- 🔒 Note: raw gateway `:8082` logs remain API-inaccessible (shared-space managed gateway) — but they're no longer needed; the app logs are conclusive.

### To finish pinning the mechanism (UI-only)
- **API Manager → each MCP-proxy API (e.g. `resortSystemsMcp`) → Analytics** — look for 5xx / upstream-timeout spikes on the `:8082` proxies during a failing run.
- **Runtime Manager → `lynn-itinerary-network` → Monitoring** (Anypoint Monitoring) — the agent's OTLP tool-call spans show the exact per-call error (timeout vs reset vs status) the agent saw.

### Recommended fixes (priority order — corrected)
1. **Make the null-param calls not fail (root fix).** Either (a) MCP side: make `getOfferings.category_code` and `getEligibleOffers.confirmation_code` **nullable** (type `["string","null"]`) and treat null as "not provided" (full catalogue / player_id-only lookup); or (b) agent side: instruct the graph to **omit** optional params instead of sending `null`. (a) is more robust — LLMs routinely emit `null`.
2. **Fix the graph so failures still respond.** Add error/timeout/fallback transitions from `guestContext` / `itineraryBuilder` / `createItinerary` to a response node (e.g. a `needInfoResponse` returning `TASK_STATE_INPUT_REQUIRED`, or a partial-itinerary echo), so the graph **never** ends without a response node. See §10.
3. **Resolve the id first.** Call `getReservation` (by `confirmation_code` *or* `player_id`) at the start to derive `player_id` + `confirmation_code`, then thread both through — fixes both the confirmation-code case and the `getEligibleOffers.confirmation_code=null` case.
4. **Loosen loop caps** (`max_number_of_loops` 5→8–10) as a secondary safety net.

**Not a fix:** hardening `:8082` / restarting the gateway — the logs show no connectivity errors, so this won't help the intermittency.

---

## 9. Reproduction

- Agent suite runner: `/tmp/run_uc.sh` (SendMessage per use case)
- Agent intermittency characterization: `/tmp/agent_char.sh` (LR-100002 ×8, tabulates state/latency/failed-tools)
- Direct-MCP stability loop: `initialize` → `notifications/initialized` → N× `tools/call`, count `"result"` vs `"isError"`
- **SSE-hold caveat:** with `Accept: …text/event-stream`, `tools/call` connections stay open ~30s (client-timeout); use `Accept: application/json` to measure true (~150ms) latency
- MCP recipe: `initialize` (capture `mcp-session-id`) → `notifications/initialized` → `tools/call`; header `Accept: application/json, text/event-stream`
- Roster: `getGuestProfile(player_id=LR-10000N)` on the resort MCP
- Governance: `getEligibleOffers(player_id, confirmation_code)` on the casino MCP; `getTaxonomy()` on the interests MCP

MCP base URLs (usa-e1, host id `2tku8l`):
- resort  `https://lynn-resort-systems-esulje.2tku8l.usa-e1.cloudhub.io/mcp`
- interests `https://lynn-interests-esulje.2tku8l.usa-e1.cloudhub.io/mcp`
- casino  `https://lynn-casino-gaming-esulje.2tku8l.usa-e1.cloudhub.io/mcp`

---

## 10. Graph structure & the "no response node" bug
Deployed graph (`lynn-itinerary-agent/brokers/lynn-itinerary-agent.agent`) is a **linear chain with one response node and no error paths**:
```
itineraryTrigger → guestContext → itineraryBuilder → createItinerary → itineraryResponse (ONLY response node)
```
Each hop uses `on_exit -> transition`. When a subagent errors / hits `max_number_of_loops` (5), `on_exit` never fires → the graph ends **without reaching `itineraryResponse`** → `runner.graph_runner`: *"Graph completed without triggering any response node."* Trigger = the `-32602` null-param tool errors (§8b, Evidence 4).

---

## 11. Use-case pass/fail summary & remediation prompts

### 11.0 Input prompts used (the A2A message text per use case)
All sent with method `SendMessage`, `role: ROLE_USER`, header `A2A-Version: 1.0`.

| # | Use case | Prompt (message text) | Result |
|---|---|---|---|
| 1 | Happy path (Black) | `Create a personalized resort itinerary for guest with player ID LR-100002. Include dining, entertainment, and any casino offers.` | COMPLETED* (~30%) |
| 2 | Top-tier Chairman | `Create a personalized resort itinerary for guest with player ID LR-100001.` | FAILED |
| 3 | Low-tier Red | `Create a personalized resort itinerary for guest with player ID LR-100003.` | INPUT_REQUIRED |
| 4 | Confirmation code | `Create a personalized resort itinerary. My reservation confirmation is LYNN-ALEX01.` | FAILED / INPUT_REQUIRED |
| 5 | Unknown guest | `Create a personalized resort itinerary for guest with player ID LR-999999.` | FAILED |
| 6 | Vague, no id | `Hi, can you help me plan my trip?` | INPUT_REQUIRED ✅ |
| 7 | Multi-turn follow-up† | `Great. Please add a relaxing spa morning on day 2 and confirm dinner is family-friendly since we have a child.` | INPUT_REQUIRED |

Additional variants:
| Use case | Prompt | Result |
|---|---|---|
| Happy path (short form — reliability ×20) | `Create a personalized resort itinerary for guest with player ID LR-100002.` | 6 COMPLETED / 14 fail |
| Confirmation-code (first, fuller wording) | `Create a personalized resort itinerary for my upcoming stay. My reservation confirmation is LYNN-ALEX01. Include dining, entertainment, and any casino offers I'm eligible for.` | FAILED |
| Smoke test | `ping` | INPUT_REQUIRED |

\* UC-1 completes ~30% of runs (null-param + graph bugs). † UC-7 reused the `contextId` from UC-1 (multi-turn).

### 11.1 Distinct functional use cases — 2 passed / 5 failed
| # | Use case | Input | Result | Verdict | Failure detail | Fixed by |
|---|---|---|---|---|---|---|
| 1 | Happy path (full itinerary) | `LR-100002` | COMPLETED* | ✅ Pass | *only ~30% of runs (§11.2) | Prompt 1 + 2 |
| 2 | Top-tier Chairman | `LR-100001` | FAILED | ❌ Fail | `reasoning_iterations` → graph ended with no response node | Prompt 1 + 2 |
| 3 | Low-tier Red | `LR-100003` | INPUT_REQUIRED | ❌ Fail | interests + 1 offer only; reservation/offering calls errored → partial | Prompt 1 + 2 |
| 4 | Confirmation code | `LYNN-ALEX01` | FAILED / INPUT_REQUIRED | ❌ Fail | mis-slotted as `player_id`; phase-1 tools need `player_id`; no `getReservation` first | Prompt 2 |
| 5 | Unknown guest | `LR-999999` | FAILED | ❌ Fail | empty result, hard fail (no clean "not found") | Prompt 2 |
| 6 | Vague, no id | "help me plan my trip" | INPUT_REQUIRED | ✅ Pass | correct — asked for player ID / confirmation code | — |
| 7 | Multi-turn follow-up | reuse `contextId` | INPUT_REQUIRED | ❌ Fail | context preserved, tool calls errored again | Prompt 1 + 2 |

### 11.2 Happy-path reliability (`LR-100002`, 20 runs) — 6 pass / 14 fail (30%)
| Outcome | Count | % |
|---|---|---|
| ✅ COMPLETED | 6 | 30% |
| ⚠️ INPUT_REQUIRED (partial, no itinerary) | 5 | 25% |
| ❌ FAILED | 9 | 45% |

### 11.3 Failure causes (4-hour app log) → remediation
| Cause | Count | Fixed by |
|---|---|---|
| `getEligibleOffers` `-32602 /confirmation_code: null found, string expected` | 3 | **Prompt 1** |
| `getOfferings` `-32602 /category_code: null found, string expected` | 1 | **Prompt 1** |
| `runner.graph_runner` "Graph completed without triggering any response node" | 12 | **Prompt 2** |
| `jsonrpc_dispatcher` "Failed to parse request params" | 7 | test-harness noise — ignore |

### 11.4 Remediation prompts (MuleSoft Vibes / Agent Fabric)

**Prompt 1 → app `lynn-casino-gaming`** (`~/ClaudeWS/lynn-casino-gaming`; tools `getOfferings` + `getEligibleOffers`):
```
In this MCP server, two tools reject calls when the AI agent passes an explicit null for
optional parameters. Live errors from the agent:
  - getOfferings  → -32602 "Invalid tool parameters: /category_code: null found, string expected"
  - getEligibleOffers → -32602 "Invalid tool parameters: /confirmation_code: null found, string expected"
Both params ARE optional (not in the required list) but their MCP tool input schema types them
as plain "string", so a literal null fails validation. Fix both tools so null/omitted optional
params are accepted and handled gracefully:
1) getOfferings: make category_code (and time_from, time_to, confirmation_code) nullable in the
   tool input schema (type ["string","null"], not required). When category_code is null/empty,
   return the FULL offerings catalogue (no category filter) instead of erroring.
2) getEligibleOffers: keep player_id required, make confirmation_code nullable
   (type ["string","null"], not required). When confirmation_code is null/empty, run the
   eligibility lookup using player_id alone.
Apply the same null-tolerant pattern to any other optional string params in this MCP's tools.
Keep existing behavior for valid inputs. Point the DB config at casino_demo. Show the updated
tool schemas and DataWeave/flow changes.
```

**Prompt 2 → project `lynn-itinerary-agent`** (Agent Fabric broker; edits `brokers/lynn-itinerary-agent.agent`):
```
Fix this Agent Fabric graph (brokers/lynn-itinerary-agent.agent). Two problems seen in production:
A) "Graph completed without triggering any response node — graph authoring error" (12x/4h).
   The graph is a linear chain guestContext → itineraryBuilder → createItinerary →
   itineraryResponse, with itineraryResponse as the ONLY response node and NO error/timeout path.
   When a subagent fails or hits max_number_of_loops, on_exit never fires and the graph ends
   without emitting any A2A response.
   FIX: add a fallback response node (an echo emitting TASK_STATE_INPUT_REQUIRED with a helpful
   "I couldn't retrieve X, please provide Y" message), and add error/timeout transitions from
   guestContext, itineraryBuilder and createItinerary to it, so the agent ALWAYS returns a response.
B) Confirmation-code inputs fail because phase 1 (guestContext) calls checkConsent/getGuestProfile/
   getInterests (all need player_id), but the only tool that resolves confirmation_code → player_id
   (getReservation) is in phase 2.
   FIX: add a first step that calls getReservation with confirmation_code OR player_id to resolve
   BOTH player_id and confirmation_code up front, then pass both to all later steps (so
   getEligibleOffers always gets a real player_id/confirmation_code and never null).
Also raise max_number_of_loops from 5 to 8 on guestContext and itineraryBuilder. Show the updated graph.
```

**Expected after both:** null-param `-32602` eliminated (Prompt 1), and any remaining tool error degrades to a graceful response instead of a `graph_runner` failure (Prompt 2) → happy-path success should go from ~30% toward ~100%, and confirmation-code inputs start working.

---

## 12. Post-fix verification (2026-08-18, graph fix deployed as version `ed424534`)

**Prompt 2 (graph) was applied + deployed; Prompt 1 (MCP nulls) NOT yet.** Re-ran the suite:

| Use case | Before | After graph fix | Verdict |
|---|---|---|---|
| Happy path `LR-100002` (×6) | 30% (6/20) | **5/6 COMPLETED (83%)** | ✅ big improvement |
| Confirmation code `LYNN-ALEX01` (×2) | 0/2 (always failed) | **2/2 COMPLETED** | ✅ fixed |
| Unknown guest `LR-999999` | hard FAILED, empty output | **graceful INPUT_REQUIRED in 4.8s** ("tool returned an error… cannot proceed") | ✅ fixed |
| `reasoning_iterations` / "no response node" hard crashes | 12 / 4h | **0 in this run** | ✅ fixed |

**What the fixes delivered:**
- Fix B (front-loaded `resolveGuest`) → confirmation codes resolve → `LYNN-ALEX01` completes.
- Fix A (fallback + loop caps 5→8) → failures degrade to a graceful `INPUT_REQUIRED` instead of a response-less `graph_runner` crash.

**Still open — needs Prompt 1:** the one non-complete (hp4, `INPUT_REQUIRED`) reported *"no additional available offerings were provided in the offering catalogue"* — i.e. `getOfferings` still returns empty because `category_code: null` trips `-32602` on the MCP. It no longer crashes the graph, but costs the occasional itinerary. **Applying Prompt 1 to `lynn-casino-gaming` (return full catalogue when `category_code` is null) should push happy-path ~83% → ~100%.**

### 12.1 Final verification — BOTH fixes deployed (2026-08-18)
Prompt 1 applied to `lynn-casino-gaming` (union `["string","null"]` schemas + `""→null` normalization; SQL already null-safe). Re-ran the suite:

| Use case | Original | Graph fix only | + MCP fix |
|---|---|---|---|
| Happy path `LR-100002` (×6) | 30% | 83% | **6/6 = 100%** ✅ |
| Confirmation code `LYNN-ALEX01` (×2) | 0/2 | 2/2 | **2/2 = 100%** ✅ |
| 21+ offers leaked into itineraries | — | — | **0/8** ✅ |
| `-32602` null-param errors | 4/4h | present | **eliminated** ✅ |
| "no response node" crashes | 12/4h | 0 | **0** ✅ |

Direct MCP confirmation: `getOfferings{category_code:null}` → **9 items** (was `-32602`); `{category_code:"dining"}` → 1 (filter intact); `getEligibleOffers{confirmation_code:null}` → 3 items (was `-32602`).

**Governance caveat (fail-open) — RESOLVED 2026-08-18:** the age-gate was **fail-open** on null (`getEligibleOffers{confirmation_code:null}` → 3 offers incl. `HLMATCH → High-Limit Baccarat (min_age 21)`). Hardened to **fail-closed** in `common-flows.xml` (both age-gate clauses, lines 58 & 199): `AND (o.min_age IS NULL OR (:confirmation_code IS NOT NULL AND o.min_age <= MIN(party.age)))` — age-restricted offers are suppressed when party composition is unknown, and (bonus) when the confirmation_code is invalid. Algebraically identical when `confirmation_code` IS provided → no demo regression.

### 12.2 Fail-closed verification (2026-08-18, deployed)
- Direct MCP: `getEligibleOffers{cc:null}` → **2** (was 3, `HLMATCH` gone); `{cc:LYNN-ALEX01}` → 2 (unchanged). `getOfferings{category:null, cc:null}` → **6, 0 age-restricted** (was 9).
- Agent suite: happy path `LR-100002` **5/5 COMPLETED**, confirmation code `LYNN-ALEX01` **2/2 COMPLETED**, **0/7 runs leaked 21+**. No regression.

**FINAL STATE: all three fixes deployed & verified — happy path 100%, confirmation code 100%, `-32602` gone, 0 "no response node" crashes, age-gate fail-closed, 0 governance leaks.**

---

## 13. Demo-ready confirmation (2026-08-18)

Final single-shot demo run against the live broker, exactly as it would be driven from the Railway agent-broker-ui.

**Broker URL (paste into the Railway front-end):**
`https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/`

**Request:**
```bash
curl -s https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/ \
  -H "Content-Type: application/json" -H "A2A-Version: 1.0" \
  -d '{"jsonrpc":"2.0","id":"demo","method":"SendMessage","params":{"message":{
        "messageId":"demo1","role":"ROLE_USER",
        "parts":[{"text":"Create a personalized resort itinerary for my stay. My reservation confirmation is LYNN-ALEX01. Include dining, entertainment, and any offers I'\''m eligible for."}]}}}'
```

**Response:** `state = TASK_STATE_COMPLETED` (task `e551cf8e…`, context `52570cd4…`)
```
Welcome to Your Luxurious Escape, Alex Carter!  (Black tier)
Sep 19: 16:00 Arrival (high-floor connecting rooms, traveling with child) ·
        19:00 Le Rêve — The Dream (2-for-1) · 20:00 SW Steakhouse Dinner
Sep 20: 10:00–18:00 Encore Beach Club Daybed · 14:00 Esplanade Shopping
Sep 21: 07:00 Grand Canyon Helicopter Tour · 11:00 Bottega Luxe Personal Shopping
Offers: $500 Black Dining Credit (BLKDINE) · Show Ticket 2-for-1 (SHOW2)
```

Confirms end-to-end: confirmation-code input resolves (`LYNN-ALEX01` → Alex Carter), Black-tier personalization + real offers, family-aware, and **0 age-restricted (21+) offers** for the minor-present party (governance fail-closed holds).
