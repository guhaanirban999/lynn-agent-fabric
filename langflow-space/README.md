---
title: Lynn Langflow
emoji: 🎰
colorFrom: purple
colorTo: indigo
sdk: docker
app_port: 7860
pinned: false
license: mit
short_description: Langflow host for the Lynn Las Vegas Agent Fabric concierge demo
---

# Lynn Las Vegas — Agent Fabric Concierge (demo)

**What it is:** An AI concierge for the (fictional) **Lynn Las Vegas** integrated resort +
casino. A guest chats in plain language; a **MuleSoft Agent Fabric broker** interprets the
request and routes it to the right **specialist agent**. Each agent is an A2A agent built in
**Langflow** (hosted by this Space), and each calls a **MuleSoft MCP server** that fronts
real REST APIs over a live **MySQL** database. Natural-language requests turn into real
availability checks, bookings, and casino comps — orchestration handled by Agent Fabric,
not hard-coded.

**Architecture (one line):**
`Guest → Broker (Agent Fabric / CloudHub) → 1 of 3 Langflow agents → MuleSoft MCP server → REST API → MySQL (lynn_demo)`

## The three agents

| Agent | Domain | Tools it can call |
|---|---|---|
| **Rooms & Suites** | Lodging across the Lynn & Encore towers | `search_rooms`, `book_room` |
| **Dining** | Restaurants & reservations | `list_restaurants`, `check_dining_availability`, `book_dining` |
| **Casino / Gaming Host** | Lynn Rewards, gaming tables, comps | `lookup_guest`, `search_tables`, `check_table_availability`, `reserve_table`, `evaluate_comp`, `issue_comp` |

## Hero guest (seeded in the DB)

**Alex Carter** — Lynn Rewards **Black tier**, member ID **LR-100002**. Use this ID in demos
to trigger tier-based logic (high-limit table access, comp eligibility).

## Sample prompts — per agent

**Rooms & Suites**
- "Find me a suite for **Sep 19–21** for **2 guests**."
- "What's available in the **Encore tower** this weekend under $900/night?"
- "Book the Panoramic Suite for **LR-100002**, Sep 19–21."

**Dining**
- "What steakhouses do you have?"
- "Can I get a table for **2 at SW Steakhouse, Sep 19 at 8 pm**?"
- "Book dinner for **Alex Carter** at SW Steakhouse, Sep 19, 8 pm, party of 2."

**Casino / Gaming Host**
- "I'm **LR-100002** — what's my tier and available credit?"
- "Reserve a **high-limit baccarat** table **Saturday 10 pm**."
- "I'm playing baccarat tonight — am I eligible for a **dining comp**?"

## End-to-end "hero" prompt (broker orchestrating multiple agents)

> "I'm **Alex Carter, LR-100002**, arriving **Sep 19 for two nights**. Book me a suite, get me
> a table at **SW Steakhouse at 8 pm that night** for two, reserve a **high-limit baccarat**
> table at **10 pm**, and comp my dinner if I qualify."

**Under the hood:**
1. Broker routes lodging → **Rooms & Suites** agent → `search_rooms` → `book_room`
   (returns reservation id, room type, dates, nightly rate, total).
2. Broker routes dining → **Dining** agent → `check_dining_availability` → `book_dining`
   (returns reservation id, restaurant, time, party size).
3. Broker routes gaming → **Casino / Gaming Host** agent → `lookup_guest` (Black tier) →
   `search_tables`/`check_table_availability` → `reserve_table`, then `evaluate_comp` →
   `issue_comp` (dinner comped because Black tier qualifies).
4. Broker synthesizes one confirmation summarizing all three bookings + the comp.

**Why it matters:** a single guest request can span lodging, dining, and gaming systems.
Agent Fabric composes independent, single-domain agents into one coherent concierge — each
agent stays simple and owns its tools, while the broker handles intent, routing, and synthesis.

---

## About this Space

This Space hosts **Langflow** (Docker), which serves the three agents above over **A2A** at
`/(api/v1/a2a)/{flow_id}/.well-known/agent-card.json`. It connects to two MuleSoft MCP
servers (resort + casino/gaming) running on CloudHub. See the project repo for the broker,
MCP contracts, and database seed.
