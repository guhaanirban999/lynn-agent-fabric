# Lynn Agent Fabric demo — deployment

End-to-end order. Each step produces a URL/value used by the next.

## 0. Prereqs
- Aiven Cloud MySQL service (host, port, `avnadmin` password, CA cert).
- Anypoint Platform org + CloudHub 2.0 + Agent Fabric enabled; the gateway/org from
  `travel-agent-broker/deploy.env` can be reused.
- OpenAI (or chosen LLM) API key for the broker.
- Railway account (for self-hosted Langflow).
- The existing front-end: `https://agent-broker-ui-production.up.railway.app/`.

## 1. Database (Aiven MySQL)
```bash
cd lynn-demo-db
mysql --host <svc>.aivencloud.com --port <port> -u avnadmin -p \
      --ssl-mode=REQUIRED --ssl-ca=ca.pem < 01_schema.sql
mysql --host <svc>.aivencloud.com --port <port> -u avnadmin -p \
      --ssl-mode=REQUIRED --ssl-ca=ca.pem < 02_seed.sql
```
Verify: `SELECT tier FROM guests WHERE lynn_rewards_id='LR-100002';` → `Black`.

## 2. MCP servers + APIs (MuleSoft Vibes → CloudHub 2.0)
Build the two Mule apps from `docs/lynn-mcp-contracts.md` using MuleSoft Vibes in VS Code:
- **MCP-1 Resort Systems** (rooms + dining)
- **MCP-2 Casino / Gaming** (rewards + tables + comps)

For each: configure the Database connector to Aiven (MySQL JDBC driver + CA cert, TLS),
implement the REST resources, expose the MCP server, deploy to CloudHub 2.0.
**Record each deployed MCP server URL.**

Verify a tool (via the MCP inspector / Vibes): `lookup_guest("LR-100002")` → Black tier.

## 3. Langflow agents (Railway)
- Deploy Langflow on Railway (Docker image / template). Set `LANGFLOW_URL`.
- Build the 3 flows per `docs/lynn-langflow-agents.md`; point each MCP client node at
  the MCP URLs from step 2; **enable A2A** on each flow.
- **Record each flow's agent-card URL:**
  `{LANGFLOW_URL}/api/v1/a2a/{flow_id}/.well-known/agent-card.json`
  → `roomsAgent`, `diningAgent`, `gamingHostAgent`.

Verify: `curl` each card URL; run one `message/send` (see agents doc).

## 4. Concierge broker (Agent Fabric → CloudHub 2.0)
- In `lynn-concierge-broker/exchange.json`, set `organizationId`/`groupId` to your
  Anypoint org (or keep if reusing the travel org).
- Publish to Exchange and deploy the agent network. Provide the runtime variables:
  - `ingressgw.url`, `openai.url` + `openai.apiKey`
  - `roomsAgent.url`, `diningAgent.url`, `gamingHostAgent.url` (from step 3)
- **Record the broker A2A URL:** `${ingressgw.url}/lynn-concierge-broker`.

Verify (A2A `message/send` to the broker):
```bash
curl -X POST <broker-a2a-url> -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":
      {"messageId":"m1","role":"user","parts":[{"kind":"text",
      "text":"I am LR-100002. Anniversary weekend Sep 19-21: an Encore Tower Suite, dinner at SW Steakhouse Saturday, and a high-limit baccarat table after."}]}}}'
```
Expect a composed itinerary touching rooms + dining + gaming.

## 5. Front-end
Open `https://agent-broker-ui-production.up.railway.app/`, paste the broker A2A URL
(step 4) into its broker-URL config, and start the conversation.

## 6. End-to-end demo check
Type the hero prompt in the UI. Confirm the itinerary renders and rows appear:
```sql
SELECT * FROM room_reservations   ORDER BY reservation_id DESC LIMIT 3;
SELECT * FROM dining_reservations ORDER BY reservation_id DESC LIMIT 3;
SELECT * FROM table_reservations  ORDER BY reservation_id DESC LIMIT 3;
```

## Demo-day tips
- Keep Langflow (Railway) and the CloudHub apps warm before the demo.
- Have the hero prompt and a single-domain prompt ("book me a suite for Sep 19-21")
  ready to show routing to one agent vs. all three.
