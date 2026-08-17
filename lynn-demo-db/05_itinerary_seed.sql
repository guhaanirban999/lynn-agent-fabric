-- ============================================================
-- Casino Itinerary Agent Fabric Demo — Seed for v2 tables
-- 05_itinerary_seed.sql  (run after 04_itinerary_schema.sql)
-- Hero: Alex Carter (LR-100002, Black). Party includes a MINOR (age 12)
-- to demonstrate age/jurisdiction suppression (Epic 3.4).
-- All guest refs use subqueries on lynn_rewards_id so ids stay portable.
-- ============================================================
USE lynn_demo;

-- ---------- Taxonomy (Epic 2.4) ----------
INSERT INTO taxonomy_categories (category_code, display_name, description) VALUES
  ('gaming',       'Gaming',        'Tables, slots, poker, sportsbook (21+)'),
  ('dining',       'Dining',        'Restaurants and culinary experiences'),
  ('shopping',     'Shopping',      'Retail boutiques and the Esplanade'),
  ('entertainment','Entertainment', 'Shows, concerts, tours, attractions'),
  ('wellness',     'Wellness',      'Spa, salon, fitness'),
  ('nightlife',    'Nightlife',     'Clubs, lounges, pools (21+)')
AS new ON DUPLICATE KEY UPDATE display_name = new.display_name;

-- ---------- Partners (Epic 3.2) ----------
INSERT INTO partners (name, type, terms) VALUES
  ('Cirque Aqua Productions', 'show',   'Net 30; 15% commission'),
  ('Skyline Air Tours',       'tour',   'Prepaid; weather-cancellable'),
  ('Bottega Luxe',            'retail', 'Consignment; loyalty points eligible');

-- ---------- Offerings (Epic 3.1/3.2) ----------
-- Owned
INSERT INTO offerings (name, source, partner_id, category_code, subcategory, location, opens, closes, capacity, min_age, price_from, description) VALUES
  ('Le Rêve — The Dream',   'owned', NULL, 'entertainment', 'show',     'Lynn Theater',        '19:00','22:30', 200, NULL, 150.00, 'Aquatic theatrical spectacular'),
  ('The Spa at Lynn',       'owned', NULL, 'wellness',      'spa',      'Lynn Tower L2',       '08:00','20:00',  40, 18,   180.00, 'Full-service spa & salon'),
  ('Encore Beach Club',     'owned', NULL, 'nightlife',     'nightclub','Encore Pool',         '11:00','19:00', 300, 21,   75.00,  'Day club & pool (21+)'),
  ('Lynn Esplanade Shops',  'owned', NULL, 'shopping',      'retail',   'Lynn Esplanade',      '10:00','23:00', 999, NULL, 0.00,   'Luxury retail promenade');
-- Partner
INSERT INTO offerings (name, source, partner_id, category_code, subcategory, location, opens, closes, capacity, min_age, price_from, description) VALUES
  ('Cirque Aqua Show',            'partner', (SELECT partner_id FROM partners WHERE name='Cirque Aqua Productions'), 'entertainment','show',  'Encore Theater',  '20:00','22:00', 180, NULL, 129.00, 'Partner acrobatic water show'),
  ('Grand Canyon Helicopter Tour','partner', (SELECT partner_id FROM partners WHERE name='Skyline Air Tours'),       'entertainment','tour',  'Lynn Helipad',    '07:00','16:00',  12, NULL, 499.00, 'Half-day aerial tour'),
  ('Bottega Luxe Boutique',       'partner', (SELECT partner_id FROM partners WHERE name='Bottega Luxe'),            'shopping',     'retail','Lynn Esplanade',  '10:00','22:00',  50, NULL, 0.00,   'Partner luxury boutique');

-- ---------- Promotions / comps by tier (Epic 3.3) ----------
INSERT INTO promotions (name, category_code, min_tier, value, redemption_rules, valid_from, valid_to, min_age) VALUES
  ('Black Dining Credit',   'dining',        'Black',    500.00, 'One per stay; excludes tax/gratuity', '2026-01-01','2026-12-31', NULL),
  ('Chairman Spa Comp',     'wellness',      'Chairman', 750.00, 'One per stay',                        '2026-01-01','2026-12-31', 18),
  ('High-Limit Match Play', 'gaming',        'Black',   1000.00, 'Match on first buy-in; 21+',          '2026-01-01','2026-12-31', 21),
  ('Show Ticket 2-for-1',   'entertainment', 'Red',        0.00, 'Buy one get one; select shows',       '2026-01-01','2026-12-31', NULL);

-- ---------- Interests for the hero (Epic 2.1/2.2) ----------
-- explicit (stated) + inferred (from play/visit history)
INSERT INTO guest_interests (guest_id, category_code, affinity, source, version) VALUES
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100002'), 'gaming',        0.90, 'explicit', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100002'), 'dining',        0.80, 'explicit', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100002'), 'entertainment', 0.60, 'explicit', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100002'), 'nightlife',     0.40, 'inferred', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100002'), 'wellness',      0.30, 'inferred', 1)
AS new ON DUPLICATE KEY UPDATE affinity = new.affinity;

-- Second player (Marcus Lee, LR-100003, Red) — different tastes, so UC-7 group
-- aggregation produces a genuinely blended ranking with the hero.
INSERT INTO guest_interests (guest_id, category_code, affinity, source, version) VALUES
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100003'), 'dining',        0.90, 'explicit', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100003'), 'wellness',      0.70, 'explicit', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100003'), 'shopping',      0.60, 'explicit', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100003'), 'entertainment', 0.50, 'inferred', 1),
  ((SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100003'), 'gaming',        0.20, 'inferred', 1)
AS new ON DUPLICATE KEY UPDATE affinity = new.affinity;

-- ---------- Hero reservation + party with a MINOR (Epic 1.2/1.3, 3.4) ----------
INSERT INTO room_reservations
  (confirmation_code, guest_id, room_type_id, check_in, check_out, num_guests,
   rate_quoted, status, arrival_time, departure_time, comp_tier)
VALUES
  ('LYNN-ALEX01',
   (SELECT guest_id FROM guests WHERE lynn_rewards_id='LR-100002'),
   (SELECT room_type_id FROM room_types WHERE max_occupancy >= 3 ORDER BY base_nightly_rate DESC LIMIT 1),
   '2026-09-19','2026-09-21', 3, NULL, 'confirmed', '16:00','11:00', 'Black');

INSERT INTO party_members (reservation_id, full_name, age, is_primary) VALUES
  ((SELECT reservation_id FROM room_reservations WHERE confirmation_code='LYNN-ALEX01'), 'Alex Carter',  44, TRUE),
  ((SELECT reservation_id FROM room_reservations WHERE confirmation_code='LYNN-ALEX01'), 'Jordan Carter',41, FALSE),
  ((SELECT reservation_id FROM room_reservations WHERE confirmation_code='LYNN-ALEX01'), 'Sam Carter',   12, FALSE);
