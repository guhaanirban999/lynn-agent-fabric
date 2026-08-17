# Lynn Las Vegas — Agent Fabric demo (MCP + Agents)

A fictional **"Lynn Las Vegas"** integrated resort + casino concierge, built as a
MuleSoft **Agent Fabric** demo. A guest chats in a web UI; an Agent Fabric **broker**
orchestrates **3 low-code A2A agents** (Langflow) that call **2 MuleSoft MCP servers**
exposing tools over REST APIs backed by an **Aiven Cloud MySQL** database.

> "Lynn" is a fictional stand-in — no affiliation with any real resort.

## Architecture

```
User → agent-broker-ui (Railway) → Lynn Concierge broker (CloudHub, Agent Fabric)
                                          │ orchestrates 3 A2A agents
        ┌─────────────────────────────────┼───────────────────────────────┐
   Rooms&Suites (Langflow)          Dining (Langflow)          Casino Host (Langflow)
        │ MCP client                  │ MCP client                 │ MCP client
        └────────► MCP-1 Resort Systems ◄┘                        ►MCP-2 Casino/Gaming
                        │ REST                                         │ REST
                   Resort APIs (Mule/CloudHub) ─── Aiven MySQL ─── Gaming APIs (Mule/CloudHub)
```

**Hero prompt:** *"I'm a Black Card member — anniversary weekend Sep 19–21: an Encore
Tower Suite, dinner at SW Steakhouse Saturday, and a high-limit baccarat table after."*
→ broker routes to all 3 agents → each calls its MCP tools → one composed itinerary.

## Contents
| Path | What |
|---|---|
| `lynn-demo-db/` | Aiven MySQL `01_schema.sql`, `02_seed.sql`, README |
| `lynn-concierge-broker/` | Agent Fabric broker (clone of `travel-agent-broker`), re-themed |
| `docs/lynn-mcp-contracts.md` | MCP tool + REST endpoint contracts for the 2 Mule apps |
| `docs/lynn-langflow-agents.md` | Build recipes for the 3 Langflow A2A agents |
| `docs/DEPLOY.md` | End-to-end deployment order + verification |

## Who builds what
- **DB scripts, broker scaffold, all docs:** in this repo (done).
- **2 MCP servers + backing APIs:** you, in **MuleSoft Vibes** (VS Code) → CloudHub 2.0,
  from `docs/lynn-mcp-contracts.md`.
- **3 Langflow agents:** you, in the Langflow UI on Railway, from
  `docs/lynn-langflow-agents.md`.
- **Broker deploy + front-end wiring:** you, per `docs/DEPLOY.md`.

## Key decisions
- **Langflow** (not Flowise) for the agents — Flowise has no native A2A (issue #4283
  open; repo archived Aug 2026); Langflow serves A2A natively
  (`/api/v1/a2a/{flow_id}/.well-known/agent-card.json` + JSON-RPC).
- **3 agents** (Rooms & Suites, Dining, Casino/Gaming Host); each owns its domain MCP
  tools; the broker orchestrates.
- **2 MCP servers** = 2 System APIs over Aiven MySQL (Resort; Casino/Gaming w/ comps).
- Front door = existing `agent-broker-ui` Railway app (paste broker URL). No Slack.

See `../.claude/plans/mellow-wondering-teapot.md` for the full approved plan.
