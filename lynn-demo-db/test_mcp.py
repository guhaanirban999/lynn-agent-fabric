#!/usr/bin/env python
"""Minimal MCP Streamable-HTTP client to smoke-test a Mule MCP server.
Usage: test_mcp.py [BASE_URL]  (default http://127.0.0.1:8082)
Does initialize -> notifications/initialized -> tools/list -> tools/call(*).
Parses either application/json or text/event-stream (SSE) responses.
"""
import sys, json, urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8082").rstrip("/")
URL = BASE + "/mcp"
PROTO = "2025-06-18"
session = {"id": None}

def post(payload, expect_body=True):
    data = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream",
               "MCP-Protocol-Version": PROTO}
    if session["id"]:
        headers["Mcp-Session-Id"] = session["id"]
    req = urllib.request.Request(URL, data=data, headers=headers, method="POST")
    try:
        resp = urllib.request.urlopen(req, timeout=30)
    except urllib.error.HTTPError as e:
        return {"_http_error": e.code, "_body": e.read().decode(errors="replace")[:400]}
    sid = resp.headers.get("Mcp-Session-Id")
    if sid:
        session["id"] = sid
    ctype = resp.headers.get("Content-Type", "")
    if not expect_body:
        return {"_status": resp.status}
    if "text/event-stream" in ctype:                # stream; stop at first JSON-RPC result
        buf = []
        for raw in resp:                            # iterates line-by-line as data arrives
            line = raw.decode(errors="replace").rstrip("\r\n")
            if line.startswith("data:"):
                buf.append(line[5:].strip())
            elif line == "" and buf:
                try:
                    obj = json.loads("\n".join(buf))
                except Exception:
                    obj = None
                buf = []
                if isinstance(obj, dict) and ("result" in obj or "error" in obj):
                    resp.close()
                    return obj
        return {"_raw": "stream ended without result"}
    body = resp.read().decode(errors="replace")
    if not body.strip():
        return {"_status": resp.status}
    try:
        return json.loads(body)
    except Exception:
        return {"_raw": body[:400]}

def tool_text(res):
    """Pull the text payload out of a tools/call result."""
    if not isinstance(res, dict): return res
    if "error" in res: return "ERROR: " + json.dumps(res["error"])[:300]
    r = res.get("result", res)
    if isinstance(r, dict) and "content" in r:
        parts = []
        for c in r["content"]:
            parts.append(c.get("text", json.dumps(c)))
        return "".join(parts)
    return json.dumps(r)[:800]

# 1) initialize
init = post({"jsonrpc":"2.0","id":1,"method":"initialize",
             "params":{"protocolVersion":PROTO,"capabilities":{},
                       "clientInfo":{"name":"claude-test","version":"1.0"}}})
si = init.get("result", {}).get("serverInfo", {}) if isinstance(init, dict) else {}
print(f"initialize: session={session['id']} server={si}")
# 2) initialized notification
post({"jsonrpc":"2.0","method":"notifications/initialized"}, expect_body=False)
# 3) tools/list
tl = post({"jsonrpc":"2.0","id":2,"method":"tools/list"})
tools = tl.get("result", {}).get("tools", []) if isinstance(tl, dict) else []
print(f"\ntools/list ({len(tools)}):")
for t in tools:
    props = list((t.get("inputSchema") or {}).get("properties", {}).keys())
    print(f"  - {t['name']}({', '.join(props)})")

# 4) tools/call — MCP-C smoke calls
CALLS = [
  ("getOfferings", {}),
  ("getOfferings", {"confirmation_code":"LYNN-ALEX01"}),
  ("getPartnerOfferings", {}),
  ("checkAvailability", {"offering_id":"OFR-0006","date":"2026-09-19","party_size":4}),
  ("checkAvailability", {"offering_id":"OFR-0006","date":"2026-09-20","party_size":4}),
  ("getEligibleOffers", {"player_id":"LR-100002"}),
  ("getEligibleOffers", {"player_id":"LR-100002","confirmation_code":"LYNN-ALEX01"}),
  ("reserveOffering", {"confirmation_code":"LYNN-ALEX01","offering_id":"OFR-0001",
                        "starts_at":"2026-09-19 19:00:00","party_count":3}),
  ("recordRecommendation", {"confirmation_code":"LYNN-ALEX01","offering_id":"OFR-0001",
                        "matched_category_id":8,"match_score":0.8,
                        "is_age_eligible":True,"is_tier_eligible":True,"suppressed_reason":None}),
]
have = {t["name"] for t in tools}
print("\ntools/call:")
for i,(name,args) in enumerate(CALLS, start=10):
    if name not in have:
        print(f"\n  [{name}] NOT in tools/list — skipping (check the tool name)")
        continue
    res = post({"jsonrpc":"2.0","id":i,"method":"tools/call",
                "params":{"name":name,"arguments":args}})
    txt = tool_text(res)
    if isinstance(txt, str) and len(txt) > 700: txt = txt[:700] + " …[truncated]"
    print(f"\n  ▶ {name}({json.dumps(args)})\n    {txt}")
