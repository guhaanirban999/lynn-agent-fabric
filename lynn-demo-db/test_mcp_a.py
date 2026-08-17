#!/usr/bin/env python
"""Smoke test for MCP-A (Reservation Context + Lodging).
Usage: test_mcp_a.py [BASE_URL]   default = CloudHub lynn-resort-systems
Covers all 7 tools incl. PII-masking contrast, 404, and a self-cleaning book_room.
Needs AIVEN_MYSQL_PASSWORD in env to clean up the booking it creates.
"""
import sys, json, os, urllib.request
BASE=(sys.argv[1] if len(sys.argv)>1 else "https://lynn-resort-systems-esulje.2tku8l.usa-e1.cloudhub.io").rstrip("/")
URL=BASE+"/mcp"; P="2025-06-18"; s={"id":None}
def post(p,b=True):
    h={"Content-Type":"application/json","Accept":"application/json, text/event-stream","MCP-Protocol-Version":P}
    if s["id"]:h["Mcp-Session-Id"]=s["id"]
    try: r=urllib.request.urlopen(urllib.request.Request(URL,data=json.dumps(p).encode(),headers=h,method="POST"),timeout=45)
    except urllib.error.HTTPError as e: return {"_e":e.code,"_b":e.read().decode()[:300]}
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
    if not isinstance(res,dict): return res
    if "error" in res: return {"_toolerror":res["error"]}
    txt=res.get("result",{}).get("content",[{}])[0].get("text","")
    try: return json.loads(txt)
    except: return txt

init=post({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":P,"capabilities":{},"clientInfo":{"name":"t","version":"1"}}})
print("server:",init.get("result",{}).get("serverInfo",{}))
post({"jsonrpc":"2.0","method":"notifications/initialized"},b=False)
tl=post({"jsonrpc":"2.0","id":2,"method":"tools/list"}); tools=[t["name"] for t in tl.get("result",{}).get("tools",[])]
print("tools:",tools)

def show(label,val):
    print(f"\n▶ {label}:")
    if isinstance(val,list):
        for r in val: print("   ",r)
    else: print("   ",json.dumps(val,ensure_ascii=False)[:700])
    return val

r1=show("getReservation confirmation_code=LYNN-ALEX01 (contact REVEALED - Alex consented)",
        call("getReservation",{"confirmation_code":"LYNN-ALEX01"}))
show("getReservation player_id=LR-100002 (dual anchor)", call("getReservation",{"player_id":"LR-100002"}))
show("getReservation LYNN-XXXXXX (expect 404/not found)", call("getReservation",{"confirmation_code":"LYNN-XXXXXX"}))
show("getPartyComposition LYNN-ALEX01 (3 members, minor, has_minors true)", call("getPartyComposition",{"confirmation_code":"LYNN-ALEX01"}))
show("getScheduleConstraints LYNN-ALEX01 (dinner + quiet window; TIME as HH:mm)", call("getScheduleConstraints",{"confirmation_code":"LYNN-ALEX01"}))
show("getGuestProfile LR-100002 (Black; contact revealed)", call("getGuestProfile",{"player_id":"LR-100002"}))
show("getGuestProfile LR-100003 (no consent -> contact MASKED)", call("getGuestProfile",{"player_id":"LR-100003"}))
show("checkConsent LR-100002 (pii:contact granted, marketing denied)", call("checkConsent",{"player_id":"LR-100002"}))
show("search_rooms 2026-09-25..27 party 2 (expect 5 types)", call("search_rooms",{"check_in":"2026-09-25","check_out":"2026-09-27","party_size":2}))
show("search_rooms 2026-09-25..27 party 4 (expect 3 types)", call("search_rooms",{"check_in":"2026-09-25","check_out":"2026-09-27","party_size":4}))

print("\n--- book_room round-trip (LR-100005, STD-ENCORE, 2026-11-05..07, party 2) ---")
bk=show("book_room", call("book_room",{"player_id":"LR-100005","room_type_code":"STD-ENCORE","check_in":"2026-11-05","check_out":"2026-11-07","party_size":2}))
conf = bk.get("confirmation_code") if isinstance(bk,dict) else None
if conf:
    show("getReservation for the new booking", call("getReservation",{"confirmation_code":conf}))
    pw=os.environ.get("AIVEN_MYSQL_PASSWORD")
    if pw:
        import ssl,pymysql
        ctx=ssl.create_default_context();ctx.check_hostname=False;ctx.verify_mode=ssl.CERT_NONE
        c=pymysql.connect(host="lynn-resorts-gaming-cognizant-demo.c.aivencloud.com",port=27206,user="avnadmin",
            password=pw,database="casino_demo",ssl=ctx,autocommit=True)
        with c.cursor() as cur:
            cur.execute("SELECT reservation_id FROM reservation WHERE confirmation_code=%s",(conf,))
            row=cur.fetchone()
            if row:
                rid=row[0]
                cur.execute("DELETE FROM room_stay WHERE reservation_id=%s",(rid,))
                cur.execute("DELETE FROM reservation WHERE reservation_id=%s",(rid,))
                print(f"\ncleanup: removed test booking {conf} ({rid}) — baseline restored")
        c.close()
    else:
        print("\ncleanup: set AIVEN_MYSQL_PASSWORD to auto-remove the test booking", conf)
