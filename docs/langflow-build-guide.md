# Building the 3 Lynn agents in Langflow (step-by-step)

Requires **Langflow ≥ 1.11** (A2A support; Streamable-HTTP MCP client since 1.7).

## The 3 agents (recap)
| Flow | MCP server | Tools |
|---|---|---|
| Rooms & Suites | resort | `search_rooms`, `book_room` |
| Dining | resort | `list_restaurants`, `check_dining_availability`, `book_dining` |
| Casino / Gaming Host | gaming | `lookup_guest`, `search_tables`, `check_table_availability`, `reserve_table`, `evaluate_comp`, `issue_comp` |

MCP URLs:
- resort: `https://lynn-resort-systems-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
- gaming: `https://lynn-casino-gaming-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`

---

## Step 0 — Run Langflow on Railway (public, so the CloudHub broker can reach it)
Easiest: Railway → **New Project → Deploy a Template →** search **"Langflow"**. Or Docker:
- New Project → **Deploy from Docker Image** → `langflowai/langflow:latest`
- **Variables:**
  - `LANGFLOW_HOST=0.0.0.0`
  - `LANGFLOW_PORT=7860`
  - `LANGFLOW_AUTO_LOGIN=false`, `LANGFLOW_SUPERUSER=admin`, `LANGFLOW_SUPERUSER_PASSWORD=<pick>`  (so flows are owned & persist)
  - `LANGFLOW_CONFIG_DIR=/app/langflow-data`
- **Networking:** set the service **Target Port = 7860**, generate a public domain → this is your `LANGFLOW_URL` (e.g. `https://lynn-langflow-production.up.railway.app`).
- **Storage:** add a **Volume** mounted at `/app/langflow-data` so your flows survive redeploys. (For extra durability you can add a Railway Postgres and set `LANGFLOW_DATABASE_URL`.)
- Open `LANGFLOW_URL`, log in.

## Step 1 — Add your LLM key (the agents' brain)
Each Agent component needs a model. Use Claude: get an Anthropic API key, and either paste it into the Agent component's API-key field per flow, or add it once under **Settings → Global Variables** (type: Credential, name e.g. `ANTHROPIC_API_KEY`) so you can reuse it.

## Step 2 — Register the 2 MCP servers (once)
**Settings → MCP Servers → Add MCP Server** (or the **MCP** section in the flow sidebar):
- Server 1: Name `lynn-resort`, Mode **HTTP** (Streamable), URL = resort `/mcp` URL above.
- Server 2: Name `lynn-gaming`, Mode **HTTP** (Streamable), URL = gaming `/mcp` URL above.
- No auth headers needed (open endpoints for the demo).
Langflow will connect and fetch each server's tool list.

## Step 3 — Build Agent 1: Rooms & Suites
1. **New Flow → Simple Agent** template (this makes it `flow_type=agent`). Rename the flow **"Rooms & Suites"**.
2. Click the **Agent** component:
   - Model provider: **Anthropic**, model e.g. `claude-sonnet-4-6`; set the API key (or pick the global variable).
   - **Agent Instructions / System prompt** → paste:
     > You are the Rooms & Suites concierge for Lynn Las Vegas. Help guests find and book
     > rooms and suites across the Lynn and Encore towers. Use search_rooms for availability
     > by dates and party size; present options with nightly rate and tower; use book_room to
     > confirm. Always identify the guest (Lynn Rewards ID like LR-100002, or full name) before
     > booking. Return the reservation id, room type, dates, nightly rate, and total.
3. Drag in an **MCP Tools** component. In its **MCP Server** field pick **lynn-resort**. It lists the resort tools — enable **search_rooms** and **book_room**.
4. Connect the **MCP Tools** output → the Agent's **Tools** input.
5. **Playground** (top-right) → test: *"Find me a suite for Sep 19–21 for 2 guests."* You should see it call `search_rooms` and return the suites.

## Step 4 — Enable A2A on the flow
1. Open the flow's **Settings / Share → A2A** (Langflow 1.11). Toggle **A2A enabled** on.
2. Set the **A2A Base URL** to your public `LANGFLOW_URL` (e.g. `https://lynn-langflow-production.up.railway.app`) — this makes the agent card advertise the correct public endpoint for the broker.
3. Save. Your agent-card URL is:
   `{LANGFLOW_URL}/api/v1/a2a/{flow_id}/.well-known/agent-card.json`
   (the `flow_id` is in the flow's URL / settings). Copy it.

## Step 5 — Build Agent 2: Dining (repeat 3–4)
- Simple Agent template → rename **"Dining"**.
- System prompt:
  > You are the Dining concierge for Lynn Las Vegas. Help guests find restaurants and book
  > tables across Lynn and Encore venues. Use list_restaurants to suggest by cuisine,
  > check_dining_availability to confirm seats for the date/party size, and book_dining to
  > reserve. Identify the guest before booking. Return the reservation id, restaurant,
  > date/time, and party size.
- MCP Tools → server **lynn-resort** → enable **list_restaurants, check_dining_availability, book_dining**.
- Test: *"Book dinner at SW Steakhouse Sep 19 at 8pm for 2."* Then enable A2A, copy the card URL.

## Step 6 — Build Agent 3: Casino / Gaming Host
- Simple Agent template → rename **"Casino Gaming Host"**.
- System prompt:
  > You are a Casino Host for Lynn Las Vegas. First use lookup_guest to resolve the guest's
  > Lynn Rewards tier, points, and credit. Use search_tables and check_table_availability to
  > find and confirm a gaming table (respect bet limits and location such as High-Limit or
  > Salon Prive), and reserve_table to book it. When appropriate for the tier, use
  > evaluate_comp and, if eligible, issue_comp. Be discreet and professional. Return the
  > table reservation id, game, date/time, and any comp issued. Never bypass eligibility rules.
- MCP Tools → server **lynn-gaming** → enable all 6 gaming tools.
- Test: *"I'm LR-100002 — reserve a high-limit baccarat table Sat 10pm and check my dining comp."* Then enable A2A, copy the card URL.

## Step 7 — Verify each agent over A2A (from a terminal)
```bash
LF=https://<your-langflow>.up.railway.app
curl -s "$LF/api/v1/a2a/<flow_id>/.well-known/agent-card.json" | head
curl -s -X POST "$LF/api/v1/a2a/<flow_id>/jsonrpc" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"messageId":"m1","role":"user","parts":[{"kind":"text","text":"Find me a suite for Sep 19-21 for 2"}]}}}'
```

## Step 8 — Hand the 3 agent-card URLs back
Give the Rooms, Dining, and Gaming-Host agent-card URLs to wire into the broker's
`exchange.json` (`roomsAgent.url`, `diningAgent.url`, `gamingHostAgent.url`).

### Gotchas
- If the MCP server won't connect: confirm **HTTP/Streamable** mode (not legacy SSE) and that the URL ends in `/mcp`.
- A2A card 404 → the flow isn't agent-typed or A2A isn't enabled/saved.
- Card shows `localhost` instead of the public host → set the **A2A Base URL** (Step 4.2).
