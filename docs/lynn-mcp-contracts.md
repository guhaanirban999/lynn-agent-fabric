# Lynn MCP + API contracts (build in MuleSoft Vibes)

Build **two Mule apps**, each deployed to CloudHub 2.0 and each exposing an **MCP
server** whose tools are backed by REST resources over the Aiven `lynn_demo` MySQL
database. Use MuleSoft Vibes (DX MCP) in VS Code to generate them from these contracts.

- **MCP-1 "Resort Systems"** — rooms + dining
- **MCP-2 "Casino / Gaming"** — Lynn Rewards + tables + comps

Each Langflow agent connects to one MCP server (see `lynn-langflow-agents.md`); the
Agent Fabric broker orchestrates the agents.

---

## Database connection (both apps)

Mule **Database connector → MySQL**:
- Add the **MySQL JDBC driver** dependency to the Mule app `pom.xml`.
- Aiven requires **TLS**. Set the JDBC URL to
  `jdbc:mysql://<service>.aivencloud.com:<port>/lynn_demo?sslMode=REQUIRED`
  and add the Aiven **CA cert** to a truststore (or `sslMode=VERIFY_CA` with the CA).
- Externalize host/port/user/password/db as secure properties (do not hardcode).

Prompt hint for MuleSoft Vibes: *"Create a Mule 4 app with an APIkit REST API and an
MCP server. Connect to an Aiven MySQL database over TLS using the Database connector.
Expose the following tools/operations…"*

---

## MCP-1 — Resort Systems

### Tool: `search_rooms`
Find available room types for a date range and party size.
- **Args:** `check_in` (date), `check_out` (date), `guests` (int), `room_type` (string, optional)
- **REST:** `GET /rooms/availability?check_in=&check_out=&guests=&room_type=`
- **SQL logic:**
  ```sql
  SELECT rt.room_type_id, rt.name, rt.tower, rt.base_nightly_rate, rt.max_occupancy,
         rt.total_inventory
           - COALESCE((SELECT COUNT(*) FROM room_reservations r
                       WHERE r.room_type_id = rt.room_type_id
                         AND r.status IN ('held','confirmed')
                         AND r.check_in < :check_out
                         AND r.check_out > :check_in), 0) AS available
  FROM room_types rt
  WHERE rt.max_occupancy >= :guests
    AND (:room_type IS NULL OR rt.name LIKE CONCAT('%', :room_type, '%'))
  HAVING available > 0;
  ```
- **Response:** array of `{room_type_id, name, tower, base_nightly_rate, max_occupancy, available}`

### Tool: `book_room`
Create a room reservation.
- **Args:** `guest_id` (int), `room_type_id` (int), `check_in` (date), `check_out` (date), `guests` (int)
- **REST:** `POST /rooms/reservations`  body `{guest_id, room_type_id, check_in, check_out, guests}`
- **SQL logic:** insert with `rate_quoted = (SELECT base_nightly_rate FROM room_types WHERE room_type_id=:room_type_id)`, `status='confirmed'`; return the new `reservation_id`.
- **Response:** `{reservation_id, room_type_id, check_in, check_out, nights, rate_quoted, total, status}`

### Tool: `list_restaurants`
- **Args:** `cuisine` (string, optional), `venue` (string, optional: Lynn|Encore)
- **REST:** `GET /dining/restaurants?cuisine=&venue=`
- **SQL:** `SELECT restaurant_id,name,cuisine,venue,price_tier,opens,closes FROM restaurants WHERE (:cuisine IS NULL OR cuisine LIKE CONCAT('%',:cuisine,'%')) AND (:venue IS NULL OR venue=:venue);`
- **Response:** array of restaurant rows.

### Tool: `check_dining_availability`
- **Args:** `restaurant_id` (int), `date` (date), `party_size` (int)
- **REST:** `GET /dining/availability?restaurant_id=&date=&party_size=`
- **SQL logic:** seats left = `daily_capacity − SUM(party_size)` of that day's confirmed/held reservations:
  ```sql
  SELECT r.daily_capacity
         - COALESCE((SELECT SUM(d.party_size) FROM dining_reservations d
                     WHERE d.restaurant_id = r.restaurant_id
                       AND DATE(d.reservation_datetime) = :date
                       AND d.status IN ('held','confirmed')), 0) AS seats_available
  FROM restaurants r WHERE r.restaurant_id = :restaurant_id;
  ```
- **Response:** `{restaurant_id, date, seats_available, can_seat: seats_available >= party_size}`

### Tool: `book_dining`
- **Args:** `guest_id` (int), `restaurant_id` (int), `datetime` (datetime), `party_size` (int)
- **REST:** `POST /dining/reservations`  body `{guest_id, restaurant_id, datetime, party_size}`
- **SQL:** insert `dining_reservations` (`status='confirmed'`); return `reservation_id`.
- **Response:** `{reservation_id, restaurant_id, reservation_datetime, party_size, status}`

---

## MCP-2 — Casino / Gaming

### Tool: `lookup_guest`
Resolve a guest and their Lynn Rewards profile.
- **Args:** `query` (string — a Lynn Rewards ID like `LR-100002`, or a name)
- **REST:** `GET /guests/lookup?query=`
- **SQL:** `SELECT guest_id,first_name,last_name,lynn_rewards_id,tier,points_balance,credit_line FROM guests WHERE lynn_rewards_id=:query OR CONCAT(first_name,' ',last_name) LIKE CONCAT('%',:query,'%') LIMIT 5;`
- **Response:** array of `{guest_id, name, lynn_rewards_id, tier, points_balance, credit_line}`

### Tool: `search_tables`
- **Args:** `game_type` (string, optional), `min_bet` (decimal, optional — max the guest wants as minimum)
- **REST:** `GET /gaming/tables?game_type=&min_bet=`
- **SQL:** `SELECT table_id,game_type,location,min_bet,max_bet,seats FROM gaming_tables WHERE (:game_type IS NULL OR game_type=:game_type) AND (:min_bet IS NULL OR min_bet<=:min_bet);`
- **Response:** array of table rows.

### Tool: `check_table_availability`
- **Args:** `table_id` (int), `datetime` (datetime)
- **REST:** `GET /gaming/tables/availability?table_id=&datetime=`
- **SQL logic:** seats left = `seats − SUM(party_size)` booked at that slot:
  ```sql
  SELECT g.seats
         - COALESCE((SELECT SUM(t.party_size) FROM table_reservations t
                     WHERE t.table_id = g.table_id
                       AND t.reservation_datetime = :datetime
                       AND t.status IN ('held','confirmed')), 0) AS seats_available
  FROM gaming_tables g WHERE g.table_id = :table_id;
  ```
- **Response:** `{table_id, datetime, seats_available}`

### Tool: `reserve_table`
- **Args:** `guest_id` (int), `table_id` (int), `datetime` (datetime), `party_size` (int)
- **REST:** `POST /gaming/tables/reservations`  body `{guest_id, table_id, datetime, party_size}`
- **SQL:** insert `table_reservations` (`status='confirmed'`); return `reservation_id`.
- **Response:** `{reservation_id, table_id, reservation_datetime, party_size, status}`

### Tool: `evaluate_comp`
Decide comp eligibility from the guest's tier (simple demo rules).
- **Args:** `guest_id` (int), `comp_type` (string: dining|room|show|spa)
- **REST:** `POST /gaming/comps/evaluate`  body `{guest_id, comp_type}`
- **Logic (demo rules):** look up `tier`; then
  - `Red` → eligible = false
  - `Black` → eligible for `dining` and `show`; suggested value 500 (dining) / 300 (show)
  - `Chairman` → eligible for all types; suggested value 1000 (room), 750 (dining), 500 (show/spa)
- **Response:** `{guest_id, comp_type, eligible, suggested_value, tier, reason}`

### Tool: `issue_comp`
- **Args:** `guest_id` (int), `comp_type` (string), `value` (decimal)
- **REST:** `POST /gaming/comps/issue`  body `{guest_id, comp_type, value}`
- **SQL:** insert `comps` with `status='issued'`; return `comp_id`.
- **Response:** `{comp_id, guest_id, comp_type, value, status}`

---

## Notes for the build
- Return JSON from every operation; keep field names exactly as above so the Langflow
  MCP tool schemas match.
- Dates as `YYYY-MM-DD`, datetimes as `YYYY-MM-DD HH:MM:SS`.
- For a demo, `confirmed` status is fine on create (no separate hold/confirm step).
- Record the deployed **MCP server URL** for each app — you'll paste them into the
  Langflow MCP client nodes.
