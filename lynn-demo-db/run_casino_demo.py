#!/usr/bin/env python
"""Create + seed the casino_demo (v3) schema on Aiven. Runs 06 then 07.
Password from env AIVEN_MYSQL_PASSWORD. Connects with no default DB (06 creates it)."""
import os, ssl, sys, pymysql

HOST = os.environ.get("AIVEN_MYSQL_HOST", "lynn-resorts-gaming-cognizant-demo.c.aivencloud.com")
PORT = int(os.environ.get("AIVEN_MYSQL_PORT", "27206"))
USER = os.environ.get("AIVEN_MYSQL_USER", "avnadmin")
PWD  = os.environ.get("AIVEN_MYSQL_PASSWORD")
HERE = os.path.dirname(os.path.abspath(__file__))
if not PWD: sys.exit("ERROR: set AIVEN_MYSQL_PASSWORD")

ctx = ssl.create_default_context(); ctx.check_hostname=False; ctx.verify_mode=ssl.CERT_NONE
conn = pymysql.connect(host=HOST, port=PORT, user=USER, password=PWD, ssl=ctx,
    client_flag=pymysql.constants.CLIENT.MULTI_STATEMENTS, autocommit=False, charset="utf8mb4")
print(f"connected to {USER}@{HOST}:{PORT}")

def run_file(path):
    sql = open(path).read()
    with conn.cursor() as cur:
        cur.execute(sql)
        while cur.nextset(): pass
    conn.commit(); print("  applied", os.path.basename(path))

def q(label, sql):
    with conn.cursor() as cur:
        cur.execute(sql); rows = cur.fetchall()
    print(f"  {label}: {rows}")

try:
    for name in ("06_casino_demo_schema.sql","07_casino_demo_seed.sql"):
        print("applying", name, "..."); run_file(os.path.join(HERE, name))
    with conn.cursor() as cur: cur.execute("USE casino_demo")
    print("\nverification:")
    q("table count", "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='casino_demo'")
    q("guests", "SELECT COUNT(*) FROM guest")
    q("offerings", "SELECT COUNT(*) FROM offering")
    q("venues/providers", "SELECT (SELECT COUNT(*) FROM venue),(SELECT COUNT(*) FROM offer_provider)")
    q("hero party", "SELECT display_name, age, age_band, relationship FROM reservation_guest WHERE reservation_id='RES-0001'")
    q("hero interests (0-100)", "SELECT ic.category_code, gi.affinity_score, gi.is_explicit FROM guest_interest gi JOIN interest_category ic ON ic.category_id=gi.category_id WHERE gi.guest_id='GST-0002' ORDER BY gi.affinity_score DESC")
    q("SUPPRESSED recs (why)", "SELECT o.title, r.suppressed_reason FROM reservation_offer_recommendation r JOIN offering o ON o.offering_id=r.offering_id WHERE r.reservation_id='RES-0001' AND r.suppressed_reason IS NOT NULL")
    q("consent scopes", "SELECT scope, granted FROM guest_consent WHERE guest_id='GST-0002'")
    q("age-restricted categories", "SELECT category_code FROM interest_category WHERE is_age_restricted=TRUE")
    print("\nDONE.")
finally:
    conn.close()
