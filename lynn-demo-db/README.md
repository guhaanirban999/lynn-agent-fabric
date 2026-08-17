# Lynn demo database (Aiven Cloud MySQL 8)

Backing data store for the Lynn Las Vegas Agent Fabric demo. The two MuleSoft MCP
servers' REST APIs read/write these tables.

## Tables
- `guests` — guest profile + Lynn Rewards `tier` (Red/Black/Chairman), `points_balance`, `credit_line`
- `room_types` — room/suite catalog + `total_inventory`
- `room_reservations` — room bookings (availability = inventory − overlapping)
- `restaurants` — dining catalog + `daily_capacity`
- `dining_reservations` — dining bookings
- `gaming_tables` — table catalog (game type, location, bet limits)
- `table_reservations` — table bookings
- `comps` — comp evaluation / issuance

Hero VIP for the demo: **Alex Carter — Black tier — `LR-100002`** (guest_id 1).

## Load into Aiven

Grab the service host/port and CA cert from the Aiven console, then:

```bash
mysql --host <service>.aivencloud.com --port <port> \
      -u avnadmin -p --ssl-mode=REQUIRED --ssl-ca=ca.pem \
      < 01_schema.sql
mysql --host <service>.aivencloud.com --port <port> \
      -u avnadmin -p --ssl-mode=REQUIRED --ssl-ca=ca.pem \
      < 02_seed.sql
```

Or from a `mysql>` prompt: `SOURCE 01_schema.sql;` then `SOURCE 02_seed.sql;`

> If your Aiven user can't `CREATE DATABASE`, delete the `CREATE DATABASE`/`USE`
> lines at the top of `01_schema.sql` and run everything inside `defaultdb`.

## Quick checks
```sql
SELECT tier, points_balance, credit_line FROM guests WHERE lynn_rewards_id='LR-100002';
SELECT name, tower, base_nightly_rate, total_inventory FROM room_types;
SELECT game_type, location, min_bet, max_bet FROM gaming_tables WHERE location='High-Limit';
```
