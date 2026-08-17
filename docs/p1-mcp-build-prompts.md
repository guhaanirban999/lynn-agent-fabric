# P1 — Build the 3 MCP apps (MuleSoft Vibes) — casino_demo (v3)

Reference for building the three MCPs against the **`casino_demo`** database (full-parity
model — `06_casino_demo_schema.sql`). Supersedes the earlier `lynn_demo` version. Build
order: **MCP-B (new) → MCP-A → MCP-C**.

> Reminder: uninstall the **Salesforce DX** VS Code extensions before using ACB/Vibes.

## Conventions (all three apps)
- **DB:** Aiven MySQL, database **`casino_demo`**, TLS required:
  `jdbc:mysql://<host>:27206/casino_demo?sslMode=REQUIRED`. Host/user/password from
  `secure.yaml` (AES/CBC), `secure.key=<runtime value, not in repo>` at runtime. Add MySQL JDBC driver to `pom.xml`.
- **Transport:** MCP = Streamable HTTP at `POST /mcp` (protocol `2025-06-18`); also expose REST (APIkit).
- **IDs:** STRING PKs (`GST-000x`, `RES-000x`, `OFR-000x`, …). Write tools that INSERT must
  **generate a new id** — use Mule DataWeave `uuid()` (prefix as you like, e.g. `GI-<uuid>`).
- **Types:** `affinity_score` is INT **0..100**; booleans are 0/1; datetimes `YYYY-MM-DD HH:MM:SS`.
- **JSON:** exact field names; pass `NULL` for absent optional args so `(:x IS NULL OR …)` guards work.
- **Governance hooks:** MCP-A resolves PII masking from **`guest_consent`** and writes
  **`reservation_access_audit`**; MCP-C enforces age gating in SQL and can persist
  **`reservation_offer_recommendation`**.

### MCP → table ownership
- **MCP-A** `comp_tier, guest, reservation, reservation_guest, room_stay, pre_booked_event, stay_schedule_constraint, guest_consent, reservation_access_audit`
- **MCP-B** `interest_category, guest_interest`
- **MCP-C** `offer_provider, venue, offering, promotion, reservation_offer_recommendation`

---

# MCP-B — Entertainment Interests  (build first)

New app `casino-interests`. Owns `interest_category`, `guest_interest`.

### `getTaxonomy`  (US-2.4)
- `GET /taxonomy`, no args.
- ```sql
  SELECT category_id, category_code, category_name, parent_category_id, is_age_restricted, description
  FROM interest_category ORDER BY COALESCE(parent_category_id, category_id), category_id;
  ```
- Response: hierarchy list incl. `is_age_restricted`.

### `getInterests`  (US-2.1)
- `GET /interests?player_id=` and `GET /interests/group?player_ids=`
- **Single:**
  ```sql
  SELECT ic.category_code, ic.category_name, gi.affinity_score, gi.is_explicit, gi.source, gi.captured_at
  FROM guest_interest gi
  JOIN guest g            ON g.guest_id = gi.guest_id
  JOIN interest_category ic ON ic.category_id = gi.category_id
  WHERE g.player_id = :player_id
  ORDER BY gi.affinity_score DESC;
  ```
- **Group (mean affinity):**
  ```sql
  SELECT ic.category_code, ROUND(AVG(gi.affinity_score)) AS affinity_score,
         COUNT(DISTINCT g.guest_id) AS members
  FROM guest_interest gi
  JOIN guest g ON g.guest_id = gi.guest_id
  JOIN interest_category ic ON ic.category_id = gi.category_id
  WHERE FIND_IN_SET(g.player_id, :player_ids)
  GROUP BY ic.category_code ORDER BY affinity_score DESC;
  ```

### `getInferredInterests`  (US-2.2)
- `GET /interests/inferred?player_id=` — as `getInterests` single **+ `AND gi.is_explicit = 0`**. `is_explicit=0` clearly flags inferred.

### `updateInterests`  (US-2.3)
- `POST /interests` body `{player_id, interests:[{category_code, affinity_score}]}`
- Validate: `category_code` exists; `0 ≤ affinity_score ≤ 100` (else 400). Resolve id:
  `SELECT category_id FROM interest_category WHERE category_code=:category_code;`
- Upsert the explicit row (v3 has no version/history table — freshness tracked via `captured_at`):
  ```sql
  -- update existing explicit row
  UPDATE guest_interest gi JOIN guest g ON g.guest_id = gi.guest_id
  SET gi.affinity_score=:affinity_score, gi.source='stated', gi.captured_at=NOW()
  WHERE g.player_id=:player_id AND gi.category_id=:category_id AND gi.is_explicit=1;
  -- if 0 rows updated, insert a new one (generate uuid for the PK)
  INSERT INTO guest_interest (guest_interest_id, guest_id, reservation_id, category_id, affinity_score, is_explicit, source, captured_at)
  SELECT :new_id, g.guest_id, NULL, :category_id, :affinity_score, 1, 'stated', NOW()
  FROM guest g WHERE g.player_id=:player_id;
  ```
- Response: `{player_id, updated:[{category_code, affinity_score, captured_at}]}`

### Self-contained Vibes prompt (MCP-B)
> Create a Mule 4 app `casino-interests` with an APIkit REST API and an MCP server
> (Streamable HTTP at `POST /mcp`). Connect to Aiven MySQL `casino_demo` over TLS with
> credentials from secure properties; add the MySQL JDBC driver. Expose four MCP tools
> returning JSON with exact field names — `getTaxonomy`, `getInterests` (+ group variant),
> `getInferredInterests`, `updateInterests` — using the SQL above. For `updateInterests`,
> validate the category exists and affinity_score is 0–100, generate a `uuid()` for new
> `guest_interest_id`, and update-else-insert the explicit row.

**Sanity checks (seeded):** `getTaxonomy`→9 rows (gaming/nightlife/table_games age-restricted);
`getInterests player_id=LR-100002`→5 rows, gaming **90** first, 2 rows `is_explicit=0`;
`getInferredInterests LR-100002`→nightlife 40, wellness 30; group `LR-100002,LR-100003`→dining tops.

---

# MCP-A — Reservation Context  (reshape `lynn-resort-systems`)

Re-point JDBC to `casino_demo`. Owns the reservation/guest/party/schedule/consent/audit tables.
Add a **consent-driven PII mask** and an **audit** insert on every tool.

**Consent check (returns 1 if contact PII may be revealed):**
```sql
SELECT COALESCE(MAX(granted),0) FROM guest_consent
WHERE guest_id=:guest_id AND scope='pii:contact' AND granted=1
  AND (expires_at IS NULL OR expires_at > NOW());
```
Mask `email`, `phone`, and last name → `A**** C****` when this is 0.

**Audit (every tool):**
```sql
INSERT INTO reservation_access_audit (reservation_id, accessed_by, mcp_tool, action, fields_returned, request_context)
VALUES (:reservation_id, :accessed_by, :mcp_tool, :action, CAST(:fields AS JSON), CAST(:ctx AS JSON));
```

### `getReservation`  (US-1.1, 404)
- `GET /reservations/{confirmation_code}` and `GET /reservations?player_id=`
- ```sql
  SELECT r.reservation_id, r.confirmation_code, r.property_code, r.status,
         r.check_in_date, r.check_out_date, DATEDIFF(r.check_out_date, r.check_in_date) AS nights,
         r.arrival_time, r.departure_time, r.party_size, r.has_minors,
         r.booking_channel, r.special_requests,
         g.guest_id, g.player_id, g.first_name, g.last_name, g.email, g.phone,
         ct.tier_code, ct.tier_name
  FROM reservation r
  JOIN guest g          ON g.guest_id = r.primary_guest_id
  LEFT JOIN comp_tier ct ON ct.comp_tier_id = r.comp_tier_id
  WHERE (:confirmation_code IS NOT NULL AND r.confirmation_code = :confirmation_code)
     OR (:player_id        IS NOT NULL AND g.player_id          = :player_id)
  LIMIT 1;
  ```
- Empty → **404** `{error:"reservation not found"}`. Apply PII mask; write audit.

### `getPartyComposition`  (US-1.2)
- `GET /reservations/{confirmation_code}/party`
- ```sql
  SELECT rg.display_name, rg.age, rg.age_band, rg.is_primary, rg.relationship
  FROM reservation_guest rg JOIN reservation r ON r.reservation_id = rg.reservation_id
  WHERE r.confirmation_code = :confirmation_code;
  ```
- Response `{party_size, has_minors, members:[{age, age_band, relationship}]}` (`has_minors` = any `age_band='minor'`; names masked unless consent).

### `getScheduleConstraints`  (US-1.3)
- `GET /reservations/{confirmation_code}/schedule`
- **Events:**
  ```sql
  SELECT e.title, e.segment, e.venue_name, e.starts_at, e.ends_at, e.is_locked
  FROM pre_booked_event e JOIN reservation r ON r.reservation_id = e.reservation_id
  WHERE r.confirmation_code = :confirmation_code ORDER BY e.starts_at;
  ```
- **Constraints:**
  ```sql
  SELECT c.constraint_date, c.earliest_start, c.latest_end, c.quiet_window, c.note
  FROM stay_schedule_constraint c JOIN reservation r ON r.reservation_id = c.reservation_id
  WHERE r.confirmation_code = :confirmation_code ORDER BY c.constraint_date;
  ```
- Response `{arrival_time, departure_time, prebooked:[…], constraints:[…]}` (add arrival/departure from `reservation`).

### `getGuestProfile`
- `GET /guests/{player_id}/profile`
- ```sql
  SELECT g.guest_id, g.player_id, g.first_name, g.last_name, g.email, g.phone,
         g.home_city, g.home_region, g.country_code,
         ct.tier_code, ct.tier_name, ct.rank_order, ct.daily_comp_limit
  FROM guest g LEFT JOIN comp_tier ct ON ct.comp_tier_id = g.comp_tier_id
  WHERE g.player_id = :player_id;
  ```
- Mask contact per consent; write audit.

### `checkConsent`  (US-1.4 helper)
- `GET /guests/{player_id}/consent?scope=`
- ```sql
  SELECT gc.scope, gc.granted, gc.expires_at
  FROM guest_consent gc JOIN guest g ON g.guest_id = gc.guest_id
  WHERE g.player_id = :player_id AND (:scope IS NULL OR gc.scope = :scope);
  ```

### `search_rooms`  (lodging availability)
- `GET /rooms/availability?check_in=&check_out=&party_size=&property_code=`
- Availability = `total_inventory − overlapping active room_stays` for each room type:
  ```sql
  SELECT rt.room_type_code, rt.room_type_name, rt.property_code, rt.base_nightly_rate, rt.max_occupancy,
         rt.total_inventory - COALESCE((
           SELECT COUNT(*) FROM room_stay rs
           JOIN reservation r ON r.reservation_id = rs.reservation_id
           WHERE rs.room_type_code = rt.room_type_code
             AND r.status IN ('held','confirmed')
             AND r.check_in_date  < :check_out
             AND r.check_out_date > :check_in), 0) AS available
  FROM room_type rt
  WHERE rt.max_occupancy >= :party_size
    AND (:property_code IS NULL OR rt.property_code = :property_code)
  HAVING available > 0
  ORDER BY rt.base_nightly_rate;
  ```
- Response: `[{room_type_code, room_type_name, property_code, base_nightly_rate, max_occupancy, available}]`

### `book_room`  (creates a reservation + room_stay)
- `POST /rooms/reservations` body `{player_id, room_type_code, check_in, check_out, party_size, has_minors?}`
- Generate `:reservation_id`=`uuid()`, `:room_stay_id`=`uuid()`, `:confirmation_code`=`CONCAT('LYNN-', UPPER(SUBSTRING(REPLACE(UUID(),'-',''),1,6)))`:
  ```sql
  INSERT INTO reservation (reservation_id, confirmation_code, primary_guest_id, property_code, status,
    check_in_date, check_out_date, party_size, comp_tier_id, has_minors, booking_channel)
  SELECT :reservation_id, :confirmation_code, g.guest_id, rt.property_code, 'confirmed',
         :check_in, :check_out, :party_size, g.comp_tier_id, COALESCE(:has_minors, FALSE), 'itinerary-agent'
  FROM guest g, room_type rt
  WHERE g.player_id = :player_id AND rt.room_type_code = :room_type_code;

  INSERT INTO room_stay (room_stay_id, reservation_id, room_type_code, rate_plan_code, nightly_rate,
    is_comped, occupancy_adults, occupancy_minors)
  SELECT :room_stay_id, :reservation_id, rt.room_type_code, 'BAR', rt.base_nightly_rate, FALSE,
         :party_size, 0
  FROM room_type rt WHERE rt.room_type_code = :room_type_code;
  ```
- Response: `{confirmation_code, room_type_code, check_in, check_out, nights, nightly_rate, total, status}`
  (compute `nights = DATEDIFF(check_out, check_in)`, `total = nights * nightly_rate`).

> MCP-A now also owns the **`room_type`** inventory table (migration `08_casino_demo_rooms.sql`).

---

# MCP-C — Casino & Partner Offers  (reshape `lynn-casino-gaming`)

Re-point JDBC to `casino_demo`. Owns providers/venues/offerings/promotions/recommendations.
Age gating compares `offering.min_age` to the youngest party member.

**Youngest-age subquery** (used by suppression):
```sql
(SELECT MIN(rg.age) FROM reservation_guest rg
 JOIN reservation r ON r.reservation_id = rg.reservation_id
 WHERE r.confirmation_code = :confirmation_code)
```

### `getOfferings`  (US-3.1 + US-3.4)
- `GET /offerings?category_code=&time_from=&time_to=&confirmation_code=`
- ```sql
  SELECT o.offering_id, o.title, o.segment, ic.category_code, o.typical_start, o.duration_min,
         o.base_price, o.currency, o.is_age_restricted, o.min_age, o.availability_status,
         v.venue_name, v.opens_time, v.closes_time, v.capacity,
         p.provider_name, p.provider_type
  FROM offering o
  JOIN interest_category ic ON ic.category_id = o.category_id
  LEFT JOIN venue v          ON v.venue_id     = o.venue_id
  LEFT JOIN offer_provider p ON p.provider_id  = o.provider_id
  WHERE o.is_bookable = 1
    AND (:category_code IS NULL OR ic.category_code = :category_code)
    AND (:time_from IS NULL OR v.closes_time >= :time_from)
    AND (:time_to   IS NULL OR v.opens_time  <= :time_to)
    AND (:confirmation_code IS NULL OR o.min_age IS NULL OR o.min_age <=
         (SELECT MIN(rg.age) FROM reservation_guest rg
          JOIN reservation r ON r.reservation_id = rg.reservation_id
          WHERE r.confirmation_code = :confirmation_code))
  ORDER BY ic.category_code, o.typical_start;
  ```

### `getPartnerOfferings`  (US-3.2)
- `GET /offerings/partners?category_code=`
- Same joins **`WHERE p.provider_type='partner'`**; return `provider_name`, `partner_category`, `provider_code`.

### `getEligibleOffers`  (US-3.3 + US-3.4)
- `GET /offers/eligible?player_id=&confirmation_code=`
- ```sql
  SELECT pr.promo_id, pr.promo_code, pr.title, pr.discount_type, pr.discount_value,
         pr.redemption_rules, pr.valid_to, o.title AS offering_title, o.min_age,
         reqct.tier_code AS required_tier
  FROM promotion pr
  JOIN offering  o     ON o.offering_id       = pr.offering_id
  JOIN comp_tier reqct ON reqct.comp_tier_id  = pr.comp_tier_required
  JOIN guest g         ON g.player_id         = :player_id
  JOIN comp_tier gct   ON gct.comp_tier_id    = g.comp_tier_id
  WHERE pr.is_active = 1
    AND gct.rank_order >= reqct.rank_order
    AND (pr.valid_from IS NULL OR pr.valid_from <= CURDATE())
    AND (pr.valid_to   IS NULL OR pr.valid_to   >= CURDATE())
    AND (:confirmation_code IS NULL OR o.min_age IS NULL OR o.min_age <=
         (SELECT MIN(rg.age) FROM reservation_guest rg
          JOIN reservation r ON r.reservation_id = rg.reservation_id
          WHERE r.confirmation_code = :confirmation_code));
  ```

### `checkAvailability`  (US — dining/table/show/spa availability)
- `GET /offerings/{offering_id}/availability?date=&party_size=`
- Unified replacement for the old `check_dining_availability`/`check_table_availability`:
  seats left = venue capacity − sum of that day's booked party counts at the venue.
  ```sql
  SELECT v.venue_id, v.venue_name, v.capacity,
         v.capacity - COALESCE((
           SELECT SUM(e.party_count) FROM pre_booked_event e
           WHERE e.venue_id = v.venue_id AND DATE(e.starts_at) = :date), 0) AS seats_available
  FROM offering o JOIN venue v ON v.venue_id = o.venue_id
  WHERE o.offering_id = :offering_id;
  ```
- Response: `{offering_id, venue_id, venue_name, capacity, seats_available, can_seat: seats_available >= party_size}`

### `reserveOffering`  (assembly — writes a pre-booked event)
- `POST /offerings/reservations` body `{confirmation_code, offering_id, starts_at, party_count}`
- No generic bookings table — insert into **`pre_booked_event`** (now with `venue_id`/`offering_id` so it feeds both conflict detection and `checkAvailability`):
  ```sql
  INSERT INTO pre_booked_event (event_id, reservation_id, venue_id, offering_id, title, segment, venue_name, starts_at, ends_at, party_count, is_locked, source_system)
  SELECT :event_id, r.reservation_id, o.venue_id, o.offering_id, o.title, o.segment, v.venue_name,
         :starts_at, DATE_ADD(:starts_at, INTERVAL o.duration_min MINUTE), :party_count, 0, 'itinerary-agent'
  FROM reservation r
  JOIN offering o          ON o.offering_id = :offering_id
  LEFT JOIN venue v        ON v.venue_id    = o.venue_id
  WHERE r.confirmation_code = :confirmation_code;
  ```
  (`:event_id` = `uuid()`.) Response `{event_id, title, starts_at, ends_at, party_count}`.
  Tip: call `checkAvailability` first and only reserve when `can_seat` is true.

### `recordRecommendation`  (US-4.4 trace / US-3.4 evidence)
- `POST /offers/recommendations` body `{confirmation_code, offering_id, matched_category_id, match_score, is_age_eligible, is_tier_eligible, suppressed_reason}`
- ```sql
  INSERT INTO reservation_offer_recommendation (rec_id, reservation_id, offering_id, matched_category_id, match_score, is_age_eligible, is_tier_eligible, suppressed_reason)
  SELECT :rec_id, r.reservation_id, :offering_id, :matched_category_id, :match_score, :is_age_eligible, :is_tier_eligible, :suppressed_reason
  FROM reservation r WHERE r.confirmation_code = :confirmation_code;
  ```
  Lets the agent persist *why* each offering was chosen or suppressed (seed already has samples).

---

## After P1
Unit-test each tool (REST + MCP), deploy all three to CloudHub 2.0 (JDBC → `casino_demo`),
record the three `/mcp` URLs. Then P2 (Flex/Omni Gateway OAuth2 + consent/PII + age policies +
Exchange/Registry) and P3 (single Langflow itinerary agent wiring all three).
