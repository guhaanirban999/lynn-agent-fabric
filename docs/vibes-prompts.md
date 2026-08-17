# MuleSoft Vibes prompts — build the 2 Mule apps in ACB

Paste each prompt into the MuleSoft Vibes agent in Anypoint Code Builder **in order**,
letting it finish and reviewing the diff before the next. Two apps:
`lynn-resort-systems` (rooms + dining) and `lynn-casino-gaming` (rewards + tables + comps).
Each is a **REST API + MCP server** over the same Aiven MySQL `lynn_demo` database.

**Aiven connection (both apps):**
`host=lynn-resorts-gaming-cognizant-demo.c.aivencloud.com  port=27206
 database=lynn_demo  user=avnadmin  TLS=REQUIRED`
Set the password as a **secure property `db.password`** (do not hardcode it).

---

# APP 1 — lynn-resort-systems (rooms + dining)

## Prompt 1.1 — scaffold + DB connection
```
Create a new Mule 4.9 application named "lynn-resort-systems". It will expose a REST API
and an MCP server, both backed by a MySQL database. Add the MySQL JDBC driver to the
pom and configure a Database Config connecting over TLS with:
  jdbc:mysql://lynn-resorts-gaming-cognizant-demo.c.aivencloud.com:27206/lynn_demo?sslMode=REQUIRED
  user avnadmin, password from a secure property db.password.
Externalize host, port, database, user, and db.password as configuration/secure
properties. Add a health flow: GET /health that runs "SELECT 1" and returns {"status":"ok"}.
Implement each capability below as a reusable flow so it can be shared by both the REST
API and the MCP server.
```

## Prompt 1.2 — rooms operations
```
Add two ROOMS operations backed by the database.

1) searchRooms  -> GET /rooms/availability?check_in&check_out&guests&room_type
   SQL:
   SELECT rt.room_type_id, rt.name, rt.tower, rt.base_nightly_rate, rt.max_occupancy,
          rt.total_inventory
            - COALESCE((SELECT COUNT(*) FROM room_reservations r
                        WHERE r.room_type_id = rt.room_type_id
                          AND r.status IN ('held','confirmed')
                          AND r.check_in < :check_out AND r.check_out > :check_in),0) AS available
   FROM room_types rt
   WHERE rt.max_occupancy >= :guests
     AND (:room_type IS NULL OR rt.name LIKE CONCAT('%', :room_type, '%'))
   HAVING available > 0;
   Return a JSON array of {room_type_id,name,tower,base_nightly_rate,max_occupancy,available}.

2) bookRoom -> POST /rooms/reservations  body {guest_id,room_type_id,check_in,check_out,guests}
   Insert into room_reservations with status 'confirmed' and rate_quoted =
   (SELECT base_nightly_rate FROM room_types WHERE room_type_id=:room_type_id).
   Return {reservation_id, room_type_id, check_in, check_out, nights, rate_quoted, total, status}
   where nights = DATEDIFF(check_out,check_in) and total = nights*rate_quoted.
```

## Prompt 1.3 — dining operations
```
Add three DINING operations backed by the database.

3) listRestaurants -> GET /dining/restaurants?cuisine&venue
   SELECT restaurant_id,name,cuisine,venue,price_tier,opens,closes FROM restaurants
   WHERE (:cuisine IS NULL OR cuisine LIKE CONCAT('%',:cuisine,'%'))
     AND (:venue IS NULL OR venue=:venue);

4) checkDiningAvailability -> GET /dining/availability?restaurant_id&date&party_size
   SELECT r.daily_capacity
          - COALESCE((SELECT SUM(d.party_size) FROM dining_reservations d
                      WHERE d.restaurant_id=r.restaurant_id
                        AND DATE(d.reservation_datetime)=:date
                        AND d.status IN ('held','confirmed')),0) AS seats_available
   FROM restaurants r WHERE r.restaurant_id=:restaurant_id;
   Return {restaurant_id, date, seats_available, can_seat: seats_available >= party_size}.

5) bookDining -> POST /dining/reservations body {guest_id,restaurant_id,datetime,party_size}
   Insert into dining_reservations with status 'confirmed'.
   Return {reservation_id, restaurant_id, reservation_datetime, party_size, status}.
```

## Prompt 1.4 — expose as MCP server
```
Add an MCP server to this app using the MuleSoft MCP Connector. Register one tool per
flow, each routing to the reusable flow and returning the same JSON. Use these tool
names, descriptions, and input schemas:

- search_rooms(check_in: date, check_out: date, guests: integer, room_type?: string)
  "Find available Lynn room types for a date range and party size."
- book_room(guest_id: integer, room_type_id: integer, check_in: date, check_out: date, guests: integer)
  "Book a Lynn room/suite; returns the reservation with total price."
- list_restaurants(cuisine?: string, venue?: string)
  "List Lynn/Encore restaurants, optionally by cuisine or venue."
- check_dining_availability(restaurant_id: integer, date: date, party_size: integer)
  "Check seats available at a restaurant for a date and party size."
- book_dining(guest_id: integer, restaurant_id: integer, datetime: datetime, party_size: integer)
  "Book a dining reservation."

Expose the MCP server over HTTP (SSE) and tell me its endpoint path.
```

## Prompt 1.5 — run + test locally
```
Run the app locally on Mule 4.9. Test:
- GET /rooms/availability?check_in=2026-09-19&check_out=2026-09-21&guests=2  (expect suites with available>0)
- POST /dining/reservations {guest_id:1, restaurant_id:2, datetime:"2026-09-19 20:00:00", party_size:2}
  then confirm a new row exists in dining_reservations.
Also call the MCP tool search_rooms with the same params and confirm identical output.
```

## Prompt 1.6 — deploy to CloudHub 2.0
```
Deploy lynn-resort-systems to CloudHub 2.0 (US East 2). Set db.password as a secure
property at deploy time. After deploy, give me the public app base URL and the MCP
server endpoint URL.
```

---

# APP 2 — lynn-casino-gaming (rewards + tables + comps)

## Prompt 2.1 — scaffold + DB connection
```
Create a new Mule 4.9 application named "lynn-casino-gaming". Same setup as
lynn-resort-systems: REST API + MCP server backed by the Aiven MySQL lynn_demo database
over TLS (jdbc:mysql://lynn-resorts-gaming-cognizant-demo.c.aivencloud.com:27206/lynn_demo?sslMode=REQUIRED,
user avnadmin, password from secure property db.password). Externalize the same config
properties and add GET /health -> SELECT 1. Implement each capability as a reusable flow.
```

## Prompt 2.2 — guest lookup + tables
```
Add these operations backed by the database.

1) lookupGuest -> GET /guests/lookup?query
   SELECT guest_id,first_name,last_name,lynn_rewards_id,tier,points_balance,credit_line
   FROM guests
   WHERE lynn_rewards_id=:query
      OR CONCAT(first_name,' ',last_name) LIKE CONCAT('%',:query,'%')
   LIMIT 5;
   Return an array of {guest_id,name,lynn_rewards_id,tier,points_balance,credit_line}.

2) searchTables -> GET /gaming/tables?game_type&min_bet
   SELECT table_id,game_type,location,min_bet,max_bet,seats FROM gaming_tables
   WHERE (:game_type IS NULL OR game_type=:game_type)
     AND (:min_bet IS NULL OR min_bet<=:min_bet);

3) checkTableAvailability -> GET /gaming/tables/availability?table_id&datetime
   SELECT g.seats
          - COALESCE((SELECT SUM(t.party_size) FROM table_reservations t
                      WHERE t.table_id=g.table_id AND t.reservation_datetime=:datetime
                        AND t.status IN ('held','confirmed')),0) AS seats_available
   FROM gaming_tables g WHERE g.table_id=:table_id;
   Return {table_id, datetime, seats_available}.

4) reserveTable -> POST /gaming/tables/reservations body {guest_id,table_id,datetime,party_size}
   Insert into table_reservations with status 'confirmed'.
   Return {reservation_id, table_id, reservation_datetime, party_size, status}.
```

## Prompt 2.3 — comps
```
Add two COMP operations.

5) evaluateComp -> POST /gaming/comps/evaluate body {guest_id, comp_type}
   Look up the guest's tier, then apply demo rules:
     - Red      -> eligible=false, suggested_value=0
     - Black    -> eligible for comp_type in ('dining','show'); suggested_value 500 dining, 300 show; else eligible=false
     - Chairman -> eligible for all; suggested_value 1000 room, 750 dining, 500 show/spa
   Return {guest_id, comp_type, eligible, suggested_value, tier, reason}.

6) issueComp -> POST /gaming/comps/issue body {guest_id, comp_type, value}
   Insert into comps with status 'issued'.
   Return {comp_id, guest_id, comp_type, value, status}.
```

## Prompt 2.4 — expose as MCP server
```
Add an MCP server (MuleSoft MCP Connector) with one tool per flow:

- lookup_guest(query: string)  "Resolve a guest by Lynn Rewards ID (e.g. LR-100002) or name; returns tier, points, credit."
- search_tables(game_type?: string, min_bet?: number)  "Find gaming tables, optionally by game and max acceptable minimum bet."
- check_table_availability(table_id: integer, datetime: datetime)  "Seats available at a table for a time."
- reserve_table(guest_id: integer, table_id: integer, datetime: datetime, party_size: integer)  "Reserve a gaming table."
- evaluate_comp(guest_id: integer, comp_type: string)  "Evaluate comp eligibility by tier (dining/room/show/spa)."
- issue_comp(guest_id: integer, comp_type: string, value: number)  "Issue a comp."

Expose the MCP server over HTTP (SSE) and tell me its endpoint path.
```

## Prompt 2.5 — run + test locally
```
Run locally on Mule 4.9 and test:
- GET /guests/lookup?query=LR-100002  (expect Alex Carter, tier Black)
- GET /gaming/tables?game_type=Baccarat  (expect High-Limit and Salon Prive)
- POST /gaming/tables/reservations {guest_id:1, table_id:1, datetime:"2026-09-19 22:30:00", party_size:1}
- POST /gaming/comps/evaluate {guest_id:1, comp_type:"dining"}  (expect eligible=true, suggested_value=500)
Also verify the matching MCP tools return the same output.
```

## Prompt 2.6 — deploy to CloudHub 2.0
```
Deploy lynn-casino-gaming to CloudHub 2.0 (US East 2), db.password as a secure property.
Give me the public app base URL and the MCP server endpoint URL.
```

---

## After both are deployed
Send me the **two MCP server endpoint URLs** — they go into the Langflow MCP client nodes
(`docs/lynn-langflow-agents.md`). The Langflow agents' A2A card URLs then go into the
broker's `exchange.json` (`docs/DEPLOY.md`).

## Tips
- If Vibes proposes different flow/field names, keep the **JSON field names above**
  unchanged so the MCP tool schemas match what the Langflow agents expect.
- Dates `YYYY-MM-DD`; datetimes `YYYY-MM-DD HH:MM:SS`.
- If the DB connector fails TLS, try `sslMode=VERIFY_CA` with the Aiven CA cert in a
  truststore, or confirm the MySQL JDBC driver version supports `sslMode`.
```
