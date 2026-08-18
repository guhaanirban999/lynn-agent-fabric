# Lynn Itinerary Agent — A2A transport bridge (Flex Gateway)

These gateway policies let the **one** broker URL serve **both** A2A client generations:

- **classic A2A v0.3 JSON-RPC** clients (e.g. the Railway `agent-broker-ui`): `message/send`,
  `role:"user"`, parts `{kind:"text"}`, standard `result` Task shape.
- **native A2A v1.0 gRPC-transcoded** clients: `SendMessage`, `ROLE_USER`, parts `{text}`,
  `result.task` / `TASK_STATE_*` shape.

The broker (`lynn-itinerary-network`, a `mulesoft-agent-graph-module` app) only speaks the v1.0
gRPC-transcoded transport and requires the `A2A-Version: 1.0` header. Three policies on the
`lynn_itinerary_agent` API instance bridge the gap:

| # | Policy | Flow | What it does |
|---|--------|------|--------------|
| 1 | `header-injection` (system) | request | injects `A2A-Version: 1.0` so header-less clients pass the version gate |
| 2 | `dataweave-body-transformation` — `onrequest.dwl` | request | if body method is `message/send`/`message/stream` → rewrite to `SendMessage`, map `role`, whitelist proto-valid message fields (drops `kind`, `configuration`, etc.), and **tag the JSON-RPC `id`** (`jrs:`/`jrn:`) so the response side knows the caller was classic. Native `SendMessage` passes through untouched. |
| 3 | `dataweave-body-transformation` — `onresponse.dwl` | response | if the echoed `id` carries the tag → translate `result.task`→standard `result`, map `TASK_STATE_*`/`ROLE_*`, add part `kind`, strip the tag. No tag → native gRPC caller → pass through untouched. |

**Why in-band id tagging instead of a header?** The OOTB `dataweave-body-transformation` policy
exposes only `payload` — referencing `attributes.headers` throws HTTP 500 — so the response flow
cannot read request headers, and Flex pointcuts cannot match header *absence*. The broker echoes
the JSON-RPC `id`, so tagging it is the reliable cross-flow signal.

## Re-apply after a broker redeploy

Redeploying the broker via Vibes/Agent Fabric can re-sync the API instance and reset the system
`header-injection` policy (dropping the `A2A-Version` line) and/or drop the two custom transforms.
Policy IDs also change on re-registration. This script restores all three **idempotently** (matches
by assetId/`requestFlow`, updates in place, self-heals duplicates):

```bash
cd gateway-a2a-bridge
python3 apply-gateway-policies.py            # ensure the 3 customizations
python3 apply-gateway-policies.py --verify   # …and probe both protocols on the live endpoint
```

Creds come from `ANYPOINT_CLIENT_ID` / `ANYPOINT_CLIENT_SECRET` in the environment, or from
`ClaudeWS/.env` (override path with `DOTENV=…`). Instance/org/env default to the current demo;
override with `LYNN_API_INSTANCE_ID`, `ANYPOINT_ORG_ID`, `LYNN_ENV_ID` if a redeploy changes them.

Gateway propagation takes ~30–60s after the script runs before changes take effect.

## Files
- `onrequest.dwl` — request transform (DataWeave)
- `onresponse.dwl` — response transform (DataWeave)
- `apply-gateway-policies.py` — idempotent re-apply + optional `--verify`
