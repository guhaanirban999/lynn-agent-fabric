#!/usr/bin/env python3
"""
Re-apply the A2A transport-bridge gateway customizations on the `lynn_itinerary_agent`
Flex Gateway API instance. Idempotent: safe to run repeatedly, and specifically after a
Vibes/Agent-Fabric redeploy of the broker (which can re-sync the system policies and reset
these). Looks policies up dynamically by assetId/requestFlow, so it survives changing policy IDs.

Ensures three things on the instance:
  1. header-injection system policy  -> inboundHeaders contains `A2A-Version: 1.0`
  2. dataweave-body-transformation (onRequest)  -> script = onrequest.dwl
  3. dataweave-body-transformation (onResponse) -> script = onresponse.dwl

Creds: reads ANYPOINT_CLIENT_ID / ANYPOINT_CLIENT_SECRET from the environment, or from
ClaudeWS/.env (default ../../.env relative to this file, override with DOTENV=/path).

Optional env overrides:
  ANYPOINT_ORG_ID, LYNN_ENV_ID, LYNN_API_INSTANCE_ID
Run `--verify` to also probe the live endpoint for both protocols after applying.

Usage:
  python3 apply-gateway-policies.py            # apply/ensure
  python3 apply-gateway-policies.py --verify   # apply/ensure, then probe both protocols
"""
import os, sys, json, pathlib, urllib.request, urllib.error

BASE  = "https://anypoint.mulesoft.com"
HERE  = pathlib.Path(__file__).resolve().parent
GROUP = "68ef9520-24e9-4cf2-b2f5-620025690913"      # MuleSoft policy group
DW_ASSET, DW_VER = "dataweave-body-transformation", "1.0.0"

ORG   = os.environ.get("ANYPOINT_ORG_ID",       "0f5adde5-0f81-487e-86c2-bc6d1a967ab6")
ENVID = os.environ.get("LYNN_ENV_ID",           "57d1cceb-fe1f-4657-a155-6f2678f4388d")
API   = os.environ.get("LYNN_API_INSTANCE_ID",  "21105670")
GW_URL = "https://lynn-demo-gw-0m6hw6.5sc6y6-1.usa-e2.cloudhub.io/lynn_itinerary_agent/"


def load_dotenv():
    if os.environ.get("ANYPOINT_CLIENT_ID") and os.environ.get("ANYPOINT_CLIENT_SECRET"):
        return
    path = pathlib.Path(os.environ.get("DOTENV", HERE.parent.parent / ".env"))
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


def http(method, url, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def get_token():
    st, resp = http("POST", BASE + "/accounts/api/v2/oauth2/token", body={
        "grant_type": "client_credentials",
        "client_id": os.environ["ANYPOINT_CLIENT_ID"],
        "client_secret": os.environ["ANYPOINT_CLIENT_SECRET"],
    })
    if st != 200 or "access_token" not in resp:
        sys.exit(f"[FATAL] token request failed: {st} {resp}")
    return resp["access_token"]


def asset_of(p):
    return (p.get("template") or {}).get("assetId") or p.get("assetId")


def pid_of(p):
    return p.get("policyId") or p.get("id")


def pol_url(pid=None):
    u = f"{BASE}/apimanager/api/v1/organizations/{ORG}/environments/{ENVID}/apis/{API}/policies"
    return u + (f"/{pid}" if pid else "")


def list_policies(token):
    """List policies and enrich each with its full detail. The list endpoint omits
    configurationData and returns the id under 'policyId', so fetch each one individually."""
    st, d = http("GET", pol_url(), token)
    if st != 200:
        sys.exit(f"[FATAL] list policies failed: {st} {d}")
    pols = d if isinstance(d, list) else d.get("policies", [])
    out = []
    for p in pols:
        pid = pid_of(p)
        st2, det = http("GET", pol_url(pid), token)
        det = det if (st2 == 200 and isinstance(det, dict)) else p
        det["policyId"] = pid
        out.append(det)
    return out


def ensure_header(token, pols):
    hp = next((p for p in pols if asset_of(p) == "header-injection"), None)
    if not hp:
        print("[WARN] no header-injection policy found — the broker registration usually creates it. "
              "Redeploy first, then re-run.")
        return
    cfg = dict(hp.get("configurationData") or {})
    inbound = list(cfg.get("inboundHeaders") or [])
    if any((h.get("key") or "").lower() == "a2a-version" for h in inbound):
        print("[OK ] header-injection already has A2A-Version:1.0")
        return
    inbound.append({"key": "A2A-Version", "value": "1.0"})
    cfg["inboundHeaders"] = inbound
    cfg.setdefault("outboundHeaders", cfg.get("outboundHeaders") or [])
    st, d = http("PATCH", pol_url(pid_of(hp)), token, {"configurationData": cfg})
    print(f"[{'OK ' if st==200 else 'ERR'}] header-injection += A2A-Version:1.0  (HTTP {st})")


def ensure_dw(token, pols, flow, script):
    matches = [p for p in pols if asset_of(p) == DW_ASSET
               and (p.get("configurationData") or {}).get("requestFlow") == flow]
    cfg = {"requestFlow": flow, "script": script}
    if matches:
        st, d = http("PATCH", pol_url(pid_of(matches[0])), token, {"configurationData": cfg})
        print(f"[{'OK ' if st==200 else 'ERR'}] DW {flow}: updated existing "
              f"(policyId={pid_of(matches[0])}, HTTP {st})")
        for dup in matches[1:]:                       # self-heal accidental duplicates
            st3, _ = http("DELETE", pol_url(pid_of(dup)), token)
            print(f"[{'OK ' if st3 in (200,204) else 'ERR'}] DW {flow}: removed duplicate "
                  f"(policyId={pid_of(dup)}, HTTP {st3})")
    else:
        body = {"configurationData": cfg, "groupId": GROUP, "assetId": DW_ASSET,
                "assetVersion": DW_VER, "pointcutData": None}
        st, d = http("POST", pol_url() + "?allowDuplicated=true", token, body)
        print(f"[{'OK ' if st in (200,201) else 'ERR'}] DW {flow}: applied new (HTTP {st})")


def verify():
    def call(headers, payload):
        st, d = http("POST", GW_URL, None, None) if False else (None, None)
        req = urllib.request.Request(GW_URL, data=json.dumps(payload).encode(), method="POST")
        req.add_header("Content-Type", "application/json")
        for k, v in headers.items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode())
        except Exception as e:
            return {"_error": str(e)}

    print("\n--- verify (probing live endpoint) ---")
    classic = call({}, {"jsonrpc": "2.0", "id": "verify-classic", "method": "message/send",
                        "params": {"message": {"role": "user", "messageId": "vc",
                                               "parts": [{"kind": "text", "text": "hi"}]}}})
    r = classic.get("result", {})
    ok1 = ("result" in classic) and ("task" not in r) and classic.get("id") == "verify-classic"
    print(f"[{'PASS' if ok1 else 'FAIL'}] classic v0.3 -> standard shape "
          f"(state={r.get('status',{}).get('state')})  {classic.get('_error','')}")

    grpc = call({"A2A-Version": "1.0"}, {"jsonrpc": "2.0", "id": "verify-grpc", "method": "SendMessage",
                "params": {"message": {"role": "ROLE_USER", "messageId": "vg",
                                       "parts": [{"text": "hi"}]}}})
    rg = grpc.get("result", {})
    ok2 = "task" in rg
    print(f"[{'PASS' if ok2 else 'FAIL'}] native gRPC   -> raw passthrough "
          f"(task.state={rg.get('task',{}).get('status',{}).get('state')})  {grpc.get('_error','')}")


def main():
    load_dotenv()
    token = get_token()
    onreq  = (HERE / "onrequest.dwl").read_text()
    onresp = (HERE / "onresponse.dwl").read_text()
    pols = list_policies(token)
    print(f"instance {API}: {len(pols)} policies currently applied")
    ensure_header(token, pols)
    ensure_dw(token, pols, "onRequest", onreq)
    ensure_dw(token, pols, "onResponse", onresp)
    if "--verify" in sys.argv:
        verify()
    print("\nDone. (Gateway policy propagation takes ~30-60s before it takes effect.)")


if __name__ == "__main__":
    main()
