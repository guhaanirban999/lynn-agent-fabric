#!/usr/bin/env python
"""Apply the v2 itinerary migration (04) + seed (05) to Aiven lynn_demo.

Password comes from env AIVEN_MYSQL_PASSWORD (never hard-coded / committed).
TLS is required by Aiven; we encrypt but skip CA verification (sslMode=REQUIRED).
"""
import os, ssl, sys, pymysql

HOST = os.environ.get("AIVEN_MYSQL_HOST", "lynn-resorts-gaming-cognizant-demo.c.aivencloud.com")
PORT = int(os.environ.get("AIVEN_MYSQL_PORT", "27206"))
USER = os.environ.get("AIVEN_MYSQL_USER", "avnadmin")
PWD  = os.environ.get("AIVEN_MYSQL_PASSWORD")
DB   = os.environ.get("AIVEN_MYSQL_DB", "lynn_demo")
HERE = os.path.dirname(os.path.abspath(__file__))

if not PWD:
    sys.exit("ERROR: set AIVEN_MYSQL_PASSWORD in the environment first.")

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

conn = pymysql.connect(
    host=HOST, port=PORT, user=USER, password=PWD, database=DB,
    ssl=ctx, client_flag=pymysql.constants.CLIENT.MULTI_STATEMENTS,
    autocommit=False, charset="utf8mb4",
)
print(f"connected to {USER}@{HOST}:{PORT}/{DB}")

def run_file(path):
    with open(path) as f:
        sql = f.read()
    with conn.cursor() as cur:
        cur.execute(sql)              # server parses the whole script
        while cur.nextset():          # drain all result sets
            pass
    conn.commit()
    print(f"  applied {os.path.basename(path)}")

def q(label, sql):
    with conn.cursor() as cur:
        cur.execute(sql)
        rows = cur.fetchall()
    print(f"  {label}: {rows}")

try:
    for name in ("04_itinerary_schema.sql", "05_itinerary_seed.sql"):
        print(f"applying {name} ...")
        run_file(os.path.join(HERE, name))

    print("\nverification:")
    q("taxonomy rows",   "SELECT COUNT(*) FROM taxonomy_categories")
    q("offerings rows",  "SELECT COUNT(*) FROM offerings")
    q("v_offerings rows","SELECT COUNT(*) FROM v_offerings")
    q("promotions rows", "SELECT COUNT(*) FROM promotions")
    q("hero interests",  "SELECT category_code, affinity, source FROM guest_interests gi "
                         "JOIN guests g ON g.guest_id=gi.guest_id WHERE g.lynn_rewards_id='LR-100002' ORDER BY affinity DESC")
    q("hero party",      "SELECT full_name, age, age_band, is_primary FROM party_members pm "
                         "JOIN room_reservations r ON r.reservation_id=pm.reservation_id "
                         "WHERE r.confirmation_code='LYNN-ALEX01'")
    q("has_minors?",     "SELECT SUM(age_band='minor')>0 AS has_minors FROM party_members pm "
                         "JOIN room_reservations r ON r.reservation_id=pm.reservation_id "
                         "WHERE r.confirmation_code='LYNN-ALEX01'")
    q("21+ offerings suppressed for minors (sample)",
      "SELECT name, min_age FROM v_offerings WHERE min_age >= 21 LIMIT 5")
    print("\nDONE.")
finally:
    conn.close()
