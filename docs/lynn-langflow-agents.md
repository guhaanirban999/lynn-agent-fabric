# Lynn Langflow agents (3, A2A-enabled)

Build **3 agent flows** in Langflow (self-hosted on Railway). Each is an
**agent-typed, `a2a_enabled`** flow so the Agent Fabric broker can call it over A2A,
and each uses Langflow's **MCP client** node to reach one MuleSoft MCP server.

## Deployed MCP server URLs (CloudHub)
- **Resort Systems** (rooms + dining): `https://lynn-resort-systems-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
- **Casino / Gaming** (rewards + tables + comps): `https://lynn-casino-gaming-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`

Transport is **Streamable HTTP** (MCP `2025-06-18`). Point the Langflow MCP client at
these URLs.

## Common flow shape (per agent)

```
Chat Input ─▶ Agent (LLM + tools) ─▶ Chat Output
                     │
                     └─ MCP Tools node  ──▶ MuleSoft MCP server (from lynn-mcp-contracts.md)
```

Steps that repeat for all three:
1. **New Flow → Agent** (start from the "Simple Agent" template so `flow_type=agent`).
2. Add an **MCP Tools** (MCP client) component; set the server URL to the deployed
   MuleSoft MCP server; select the tools listed below; connect it to the Agent's
   *Tools* input.
3. Set the **model** on the Agent component (e.g. `claude-sonnet-4-6` or your provider);
   put the persona in the Agent's *system/instructions*.
4. **Enable A2A** on the flow: open flow **Settings** and turn on **A2A** (the
   `a2a_enabled` flag). Save.
5. Note the flow's A2A URLs:
   - Card: `GET {LANGFLOW_URL}/api/v1/a2a/{flow_id}/.well-known/agent-card.json`
   - RPC:  `POST {LANGFLOW_URL}/api/v1/a2a/{flow_id}/jsonrpc` (`message/send`)
6. Give the broker the **card URL** for each flow (→ `roomsAgent.url`, `diningAgent.url`,
   `gamingHostAgent.url` in the broker's `exchange.json` variables).

Shared guidance to add to every system prompt:
> "Always identify the guest (Lynn Rewards ID like LR-100002, or full name) before
> booking. Use `lookup_guest` when you need the guest_id. Return a concise confirmation
> with the reservation id, date/time, and price or comp. If a detail is missing, ask
> for it briefly."

---

## Agent 1 — Rooms & Suites
- **MCP server:** MCP-1 Resort Systems — `https://lynn-resort-systems-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
- **Tools:** `search_rooms`, `book_room` (and `lookup_guest` if reachable, else the
  broker passes guest_id)
- **System prompt:**
  > You are the Rooms & Suites concierge for Lynn Las Vegas. You help guests find and
  > book rooms and suites across the Lynn and Encore towers. Use `search_rooms` to find
  > availability for the requested dates and party size, present the best options with
  > nightly rate and tower, and use `book_room` to confirm. Always return the
  > reservation id, room type, dates, nightly rate, and total.

## Agent 2 — Dining
- **MCP server:** MCP-1 Resort Systems — `https://lynn-resort-systems-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
- **Tools:** `list_restaurants`, `check_dining_availability`, `book_dining`
- **System prompt:**
  > You are the Dining concierge for Lynn Las Vegas. You help guests find restaurants
  > and book tables across Lynn and Encore venues (Mizumi, SW Steakhouse, Lakeside,
  > Wing Lei, Sinatra, and more). Use `list_restaurants` to suggest venues by cuisine,
  > `check_dining_availability` to confirm seats for the date/party size, and
  > `book_dining` to reserve. Return the reservation id, restaurant, date/time, and
  > party size.

## Agent 3 — Casino / Gaming Host
- **MCP server:** MCP-2 Casino / Gaming — `https://lynn-casino-gaming-esulje.rajrd4-1.usa-e1.cloudhub.io/mcp`
- **Tools:** `lookup_guest`, `search_tables`, `check_table_availability`,
  `reserve_table`, `evaluate_comp`, `issue_comp`
- **System prompt:**
  > You are a Casino Host for Lynn Las Vegas. First use `lookup_guest` to resolve the
  > guest's Lynn Rewards tier, points, and credit line. Use `search_tables` and
  > `check_table_availability` to find and confirm a gaming table (respect bet limits
  > and location such as High-Limit or Salon Prive), and `reserve_table` to book it.
  > When appropriate for the guest's tier, use `evaluate_comp` and, if eligible,
  > `issue_comp`. Be discreet and professional. Return the table reservation id,
  > game, date/time, and any comp issued. Never bypass eligibility rules.

---

## Verify a Langflow agent standalone
```bash
# Agent card
curl {LANGFLOW_URL}/api/v1/a2a/{flow_id}/.well-known/agent-card.json

# message/send (A2A JSON-RPC)
curl -X POST {LANGFLOW_URL}/api/v1/a2a/{flow_id}/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"message/send",
       "params":{"message":{"messageId":"m1","role":"user",
         "parts":[{"kind":"text","text":"Find me a suite for Sep 19-21 for 2 guests"}]}}}'
```
