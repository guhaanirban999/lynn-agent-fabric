# Lynn Itinerary Agent — Flex Gateway Policy Changes

**Purpose:** enable the single broker URL to serve **both** A2A client generations — legacy
**A2A v0.3 JSON-RPC** clients (the Railway `agent-broker-ui`) and native **A2A v1.0
gRPC-transcoded** clients — without changing the broker or the UI.

**Author:** platform change, 2026-08-18
**Scope:** three policies on one API instance. No application code changed.

---

## 1. Environment / target

| Item | Value |
|---|---|
| Gateway | `lynn-demo-gw` (Flex Gateway, CloudHub 2.0, **usa-e2**, shared space) |
| API instance | `lynn_itinerary_agent` — **id `21105670`** |
| Environment | Sandbox (`57d1cceb-fe1f-4657-a155-6f2678f4388d`) |
| Organization | `0f5adde5-0f81-487e-86c2-bc6d1a967ab6` (cognizant) |
| Public endpoint | `https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/` |
| Upstream (broker) | CloudHub 2.0 app `lynn-itinerary-network` — a Python `mulesoft-agent-graph-module` (AgentScript) broker |

> **Note on IDs:** policy IDs change every time the broker is redeployed (the API instance is
> re-registered). The values in this doc are point-in-time; the re-apply script matches policies
> by **assetId + requestFlow**, not by ID.

---

## 2. The problem (why the changes were needed)

The broker only speaks **one** A2A transport: the **v1.0 gRPC service transcoded to JSON**. It
expects gRPC-style method names, enum values, and a specific request shape, and it **requires an
`A2A-Version: 1.0` HTTP header**. The Railway `agent-broker-ui`, however, is a **standard A2A v0.3
JSON-RPC** client. The two are the same protocol family but different transports, so an unmodified
UI request failed at three successive gates:

| # | Error returned by broker | Root cause |
|---|---|---|
| 1 | `-32009  Unsupported A2A version: missing. Minimum required: 1.0` | UI sends no `A2A-Version` header |
| 2 | `-32601  Method not found` | UI calls JSON-RPC `message/send`; broker only exposes gRPC `SendMessage` |
| 3 | `-32602  Invalid params` | Broker uses **strict proto3 JSON parsing** and rejects v0.3-only fields (`message.kind`, `configuration.blocking`, …) |

Additionally, the **response** shape differs: the broker returns `result.task{…}` with
`TASK_STATE_*` enums and `ROLE_*` roles, whereas a v0.3 client expects `result{…}` with
`input-required`/`completed` states, `agent`/`user` roles, and parts tagged with `kind`.

A header alone could not fix this — it required **bidirectional body translation**.

---

## 3. Policies applied (what changed)

Three policies now sit on the `lynn_itinerary_agent` instance (in addition to the system policies
`a-two-a-v1-agent-card`, `tracing`, `user-context-propagation` that the broker registration creates):

### Policy 1 — Header Injection (system policy, modified)
- **assetId:** `header-injection` (group `68ef9520-24e9-4cf2-b2f5-620025690913`)
- **Change:** appended `A2A-Version: 1.0` to `inboundHeaders` (which already contained
  `x-anypoint-api-instance-id`).
- **Effect:** every inbound request carries `A2A-Version: 1.0` before it reaches the broker, so
  header-less clients pass the version gate. **Fixes error #1.**

```json
"inboundHeaders": [
  { "key": "x-anypoint-api-instance-id", "value": "21105670" },
  { "key": "A2A-Version",                "value": "1.0" }
]
```

### Policy 2 — DataWeave Body Transformation, `onRequest` (new)
- **assetId:** `dataweave-body-transformation` v1.0.0 · **requestFlow:** `onRequest`
- **Script:** [`onrequest.dwl`](./onrequest.dwl)
- **Change / effect:** if the request is classic (`method` is `message/send`/`message/stream`):
  1. rewrite `method` → `SendMessage` (**fixes error #2**);
  2. map `role: "user"` → `"ROLE_USER"`;
  3. **rebuild the `message` from a proto whitelist** — keep only
     `messageId, contextId, taskId, role, parts, metadata, referenceTaskIds`; drop `kind`; collapse
     each part to bare `{text}`/`{data}`/`{file}`; and **drop `configuration` / params `metadata`
     entirely** (**fixes error #3**);
  4. **tag the JSON-RPC `id`** with a marker (`jrs:` for string ids, `jrn:` for numeric) so the
     response stage can recognise a classic caller.
  Native `SendMessage` requests are **passed through untouched**.

### Policy 3 — DataWeave Body Transformation, `onResponse` (new)
- **assetId:** `dataweave-body-transformation` v1.0.0 · **requestFlow:** `onResponse`
- **Script:** [`onresponse.dwl`](./onresponse.dwl)
- **Change / effect:** if the echoed `id` carries the tag (i.e. a classic caller):
  1. unwrap `result.task` → `result`;
  2. map states `TASK_STATE_INPUT_REQUIRED`→`input-required`, `_COMPLETED`→`completed`, etc.;
  3. map roles `ROLE_AGENT`→`agent`, `ROLE_USER`→`user`;
  4. add `kind:"text"` to parts, set `kind:"message"`/`"task"`;
  5. strip the tag and restore the original `id` (preserving numeric vs string type);
  6. preserve `jsonrpc`/`id`.
  If the `id` has no tag → native gRPC caller → response is **passed through untouched**.

Together, policies 2 + 3 convert **only** classic v0.3 traffic and leave v1.0 gRPC traffic byte-for-byte
unchanged, on the same endpoint.

---

## 4. Why this design (key decisions)

- **Why translate at the gateway (not patch the UI or the broker)?** The UI is a deployed third-party
  front-end and the broker is a generated AgentScript module; the gateway is the one place we control
  that sits between them. Standard MuleSoft protocol-mediation pattern.
- **Why an in-band `id` tag instead of a header to tell classic vs gRPC apart on the response?**
  The OOTB `dataweave-body-transformation` policy exposes **only `payload`** — referencing
  `attributes.headers` throws **HTTP 500** (verified), so the response stage cannot read request
  headers. Flex Gateway **pointcuts** also cannot match a header's *absence*. The broker **echoes the
  JSON-RPC `id`** on success (verified), which makes the id a reliable cross-flow signal. Hence the
  `jrs:`/`jrn:` tag written on the request and read on the response.
- **Why key the request rewrite on the body `method` rather than the version header?** The header is
  normalised to `1.0` for everyone by Policy 1, so it can't distinguish callers downstream. The JSON-RPC
  `method` (`message/send` vs `SendMessage`) is an unambiguous, reliable discriminator.
- **Why whitelist message fields / drop `configuration`?** The broker's proto3 parser rejects any
  unknown field. v0.3 clients legitimately send `message.kind` and `configuration.blocking`, which do
  not exist in `lf.a2a.v1.Message` / `lf.a2a.v1.SendMessageConfiguration`. Rebuilding from a whitelist
  and dropping `configuration` (the broker completes synchronously without it) is the safe, forward-
  compatible fix.
- **Why not lower the LLM temperature / silence the final response?** Out of scope for the gateway;
  those are broker-graph concerns and were handled separately (and the friendly final itinerary must
  be preserved).

**Reference — proto-allowed fields (captured from broker validation errors):**
- `lf.a2a.v1.Message`: `messageId, contextId, taskId, role, parts, metadata, extensions, referenceTaskIds`
- `lf.a2a.v1.SendMessageConfiguration`: `acceptedOutputModes, taskPushNotificationConfig, historyLength, returnImmediately`

---

## 5. How the policies were applied (procedure)

**Auth:** Connected App `bea02719…` (client-credentials; creds in `ClaudeWS/.env`).
Token endpoint: `POST https://anypoint.mulesoft.com/accounts/api/v2/oauth2/token`.

**API Manager REST base:**
`https://anypoint.mulesoft.com/apimanager/api/v1/organizations/{org}/environments/{env}/apis/{apiInstanceId}/policies`

| Action | Method / endpoint |
|---|---|
| List policies | `GET  …/policies` — returns id under **`policyId`**, and **omits `configurationData`** |
| Get one policy (with config) | `GET  …/policies/{policyId}` |
| Update a policy | `PATCH …/policies/{policyId}` body `{ "configurationData": { … } }` |
| Add a policy | `POST …/policies` body `{ configurationData, groupId, assetId, assetVersion, pointcutData }` |
| Add a 2nd instance of same template | `POST …/policies?allowDuplicated=true` (required — the gateway blocks duplicate templates otherwise) |
| Remove a policy | `DELETE …/policies/{policyId}` → `204` |

**What was actually done:**
1. Policy 1 updated via the MuleSoft DX MCP (`manage_api_instance_policy`, operation `update`).
2. Policy 2 (onRequest) added via DX MCP (`operation: apply`).
3. Policy 3 (onResponse) — a **second** `dataweave-body-transformation` instance — was blocked by
   the duplicate-template guard, so it was added via the REST API with `?allowDuplicated=true`.
4. The onRequest whitelist fix (error #3) was applied later via `PATCH …/policies/{id}`.

> Gateway propagation takes **~30–60 s** after any change before it takes effect.

### Idempotent re-apply (the supported way to reproduce all three)
All of the above is codified in **[`apply-gateway-policies.py`](./apply-gateway-policies.py)**, which is
idempotent and self-healing (matches by assetId/requestFlow, updates in place, removes duplicates):

```bash
cd gateway-a2a-bridge
python3 apply-gateway-policies.py            # ensure the 3 customizations
python3 apply-gateway-policies.py --verify   # …and probe both protocols on the live endpoint
```

**Run it after every broker redeploy** — a Vibes/Agent-Fabric redeploy re-syncs the API instance,
which resets Policy 1 back to header-only and drops Policies 2 & 3 (confirmed 2026-08-18: instance
dropped to 4 policies after a redeploy; the script restored all three).

---

## 6. Verification

Probed on the live endpoint after each change (see `--verify`):

- **Classic v0.3** (`message/send`, no `A2A-Version` header, full UI-style payload incl.
  `message.kind` + `configuration.blocking`): → standard A2A response, `state:"completed"`,
  original `id` preserved (string and numeric), full friendly itinerary returned.
- **Native v1.0 gRPC** (`SendMessage` + `A2A-Version: 1.0`): → raw `result.task` /
  `TASK_STATE_*` / `ROLE_AGENT`, **passed through untouched**.

Both pass on the same broker URL.

---

## 7. Rollback

To restore gRPC-only behaviour:
1. `DELETE` the two `dataweave-body-transformation` policies (onRequest + onResponse).
2. `PATCH` the `header-injection` policy to remove the `A2A-Version` entry from `inboundHeaders`.

Leaves the broker's original system policies intact.

---

## 8. Files in this folder
| File | Purpose |
|---|---|
| `onrequest.dwl` | Request transform (DataWeave) |
| `onresponse.dwl` | Response transform (DataWeave) |
| `apply-gateway-policies.py` | Idempotent re-apply + optional `--verify` |
| `README.md` | Quick operational summary |
| `POLICY-CHANGES.md` | This document |
