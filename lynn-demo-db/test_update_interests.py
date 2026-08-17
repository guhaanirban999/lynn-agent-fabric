#!/usr/bin/env python
"""Focused test for MCP-B updateInterests — both the UPDATE path (existing explicit
row) and the INSERT-else path (category with no explicit row yet).
Usage: test_update_interests.py [BASE_URL]   (default = CloudHub lynn-interests)
Self-cleans: reverts dining, and (needs AIVEN_MYSQL_PASSWORD) deletes any explicit
wellness row it inserted so the baseline is restored.
"""
import sys, json, urllib.request, os
BASE=(sys.argv[1] if len(sys.argv)>1 else "https://lynn-interests-esulje.2tku8l.usa-e1.cloudhub.io").rstrip("/")
URL=BASE+"/mcp"; P="2025-06-18"; s={"id":None}
PLAYER="LR-100002"

def post(p,b=True):
    h={"Content-Type":"application/json","Accept":"application/json, text/event-stream","MCP-Protocol-Version":P}
    if s["id"]:h["Mcp-Session-Id"]=s["id"]
    r=urllib.request.urlopen(urllib.request.Request(URL,data=json.dumps(p).encode(),headers=h,method="POST"),timeout=40)
    if r.headers.get("Mcp-Session-Id"):s["id"]=r.headers.get("Mcp-Session-Id")
    if not b:return
    if "text/event-stream" in r.headers.get("Content-Type",""):
        buf=[]
        for raw in r:
            ln=raw.decode(errors="replace").rstrip("\r\n")
            if ln.startswith("data:"):buf.append(ln[5:].strip())
            elif ln=="" and buf:
                try:o=json.loads("\n".join(buf))
                except:o=None
                buf=[]
                if isinstance(o,dict)and("result"in o or"error"in o):r.close();return o
    return json.loads(r.read())
def call(name,args):
    res=post({"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":name,"arguments":args}})
    if "error" in res: raise RuntimeError(res["error"])
    return json.loads(res["result"]["content"][0]["text"])
def rows(cat):
    return [r for r in call("getInterests",{"player_id":PLAYER}) if r["category_code"]==cat]
def upd(cat,score):
    return call("updateInterests",{"player_id":PLAYER,"interests":[{"category_code":cat,"affinity_score":score}]})

post({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":P,"capabilities":{},"clientInfo":{"name":"t","version":"1"}}})
post({"jsonrpc":"2.0","method":"notifications/initialized"},b=False)

results=[]
# --- Test 1: UPDATE path (dining has an explicit row) ---
upd("dining",85)
after=rows("dining")
ok1 = any(r["affinity_score"]==85 and r["is_explicit"] for r in after)
results.append(("UPDATE path: dining 80->85", ok1, after))
upd("dining",80)  # revert

# --- Test 2: INSERT-else path (wellness has ONLY an inferred row) ---
before=rows("wellness")
had_explicit_before = any(r["is_explicit"] for r in before)
upd("wellness",75)
after=rows("wellness")
ok2 = any(r["affinity_score"]==75 and r["is_explicit"] for r in after)
results.append(("INSERT path: new explicit wellness=75 appears", ok2, after))

print(f"target: {BASE}\n")
allok=True
for name,ok,detail in results:
    allok = allok and ok
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}")
    for d in detail: print(f"           {d}")
print(f"\n{'ALL GREEN' if allok else 'FAILURES PRESENT (expected pre-fix: INSERT path fails)'}")

# --- cleanup: remove any explicit wellness row we created ---
pw=os.environ.get("AIVEN_MYSQL_PASSWORD")
if pw and ok2:
    import ssl, pymysql
    ctx=ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
    c=pymysql.connect(host="lynn-resorts-gaming-cognizant-demo.c.aivencloud.com",port=27206,
        user="avnadmin",password=pw,database="casino_demo",ssl=ctx,autocommit=True)
    with c.cursor() as cur:
        n=cur.execute("""DELETE gi FROM guest_interest gi JOIN guest g ON g.guest_id=gi.guest_id
            WHERE g.player_id=%s AND gi.category_id=(SELECT category_id FROM interest_category WHERE category_code='wellness')
              AND gi.is_explicit=1""",(PLAYER,))
    c.close()
    print(f"cleanup: removed {n} inserted explicit wellness row(s) — baseline restored")
elif ok2:
    print("cleanup: set AIVEN_MYSQL_PASSWORD to auto-remove the inserted wellness row")
