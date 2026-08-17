-- ============================================================
-- casino_demo — seed (v3)  07_casino_demo_seed.sql
-- Ports the hero scenario into the richer model. Hero: Alex Carter
-- (player LR-100002, Black), conf LYNN-ALEX01, party incl. a MINOR (age 12).
-- Interests use 0..100 affinity. Recommendations persist suppression reasons.
-- Nevada 21+ for gaming/nightlife; spa 18+.
-- ============================================================
USE casino_demo;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE reservation_offer_recommendation; TRUNCATE promotion; TRUNCATE guest_interest;
TRUNCATE offering; TRUNCATE venue; TRUNCATE reservation_access_audit; TRUNCATE guest_consent;
TRUNCATE stay_schedule_constraint; TRUNCATE pre_booked_event; TRUNCATE room_stay;
TRUNCATE reservation_guest; TRUNCATE reservation; TRUNCATE guest; TRUNCATE offer_provider;
TRUNCATE interest_category; TRUNCATE comp_tier;
SET FOREIGN_KEY_CHECKS = 1;

-- comp tiers
INSERT INTO comp_tier (comp_tier_id, tier_code, tier_name, rank_order, daily_comp_limit) VALUES
  (1,'RED','Red',1,0.00),
  (2,'BLACK','Black',2,5000.00),
  (3,'CHAIRMAN','Chairman',3,20000.00);

-- interest taxonomy (hierarchy; age-restricted flags on gaming/nightlife/table_games)
INSERT INTO interest_category (category_id, category_code, category_name, parent_category_id, is_age_restricted, description) VALUES
  (1,'gaming','Gaming',NULL,TRUE,'Tables, slots, poker, sportsbook (21+)'),
  (2,'dining','Dining',NULL,FALSE,'Restaurants and culinary experiences'),
  (3,'shopping','Shopping',NULL,FALSE,'Retail boutiques and the Esplanade'),
  (4,'entertainment','Entertainment',NULL,FALSE,'Shows, concerts, tours'),
  (5,'wellness','Wellness',NULL,FALSE,'Spa, salon, fitness'),
  (6,'nightlife','Nightlife',NULL,TRUE,'Clubs, lounges, pools (21+)'),
  (7,'table_games','Table Games',1,TRUE,'Baccarat, blackjack, roulette'),
  (8,'shows','Shows',4,FALSE,'Theatrical productions'),
  (9,'spa','Spa & Salon',5,FALSE,'Spa treatments (18+)');

-- providers (owned + partner)
INSERT INTO offer_provider (provider_id, provider_code, provider_name, provider_type, property_code, partner_category, is_active) VALUES
  ('PRV-LYNN','LYNN','Lynn Resort & Casino','owned','LYNN',NULL,TRUE),
  ('PRV-CIRQ','CIRQ','Cirque Aqua Productions','partner','LYNN','show',TRUE),
  ('PRV-SKY','SKY','Skyline Air Tours','partner','LYNN','tour',TRUE),
  ('PRV-BOTT','BOTT','Bottega Luxe','partner','LYNN','retail',TRUE);

-- guests (8) — DOBs consistent w/ demo ages; comp_tier_id maps Red=1/Black=2/Chairman=3
INSERT INTO guest (guest_id, player_id, first_name, last_name, email, phone, date_of_birth, comp_tier_id, home_city, home_region, country_code) VALUES
  ('GST-0001','LR-100001','Priya','Nair','priya.nair@example.com','+1-702-555-0101','1979-03-14',3,'San Jose','CA','US'),
  ('GST-0002','LR-100002','Alex','Carter','alex.carter@example.com','+1-702-555-0102','1982-06-09',2,'Dallas','TX','US'),
  ('GST-0003','LR-100003','Marcus','Lee','marcus.lee@example.com','+1-702-555-0103','1990-11-22',1,'Seattle','WA','US'),
  ('GST-0004','LR-100004','Sofia','Rossi','sofia.rossi@example.com','+1-702-555-0104','1985-01-30',2,'Miami','FL','US'),
  ('GST-0005','LR-100005','David','Kim','david.kim@example.com','+1-702-555-0105','1993-08-05',1,'Chicago','IL','US'),
  ('GST-0006','LR-100006','Elena','Petrova','elena.petrova@example.com','+1-702-555-0106','1976-12-11',3,'New York','NY','US'),
  ('GST-0007','LR-100007','James','O''Brien','james.obrien@example.com','+1-702-555-0107','1988-04-18',2,'Boston','MA','US'),
  ('GST-0008','LR-100008','Aisha','Khan','aisha.khan@example.com','+1-702-555-0108','1995-09-27',1,'Houston','TX','US');

-- hero reservation (Black, has_minors)
INSERT INTO reservation (reservation_id, confirmation_code, primary_guest_id, property_code, status, check_in_date, check_out_date, arrival_time, departure_time, party_size, comp_tier_id, has_minors, booking_channel, special_requests) VALUES
  ('RES-0001','LYNN-ALEX01','GST-0002','LYNN','confirmed','2026-09-19','2026-09-21','16:00','11:00',3,2,TRUE,'web','High floor, connecting rooms; travelling with a child');

-- party members (Alex adult/primary, Jordan adult, Sam minor)
INSERT INTO reservation_guest (reservation_guest_id, reservation_id, guest_id, display_name, age, age_band, is_primary, relationship) VALUES
  ('RG-0001','RES-0001','GST-0002','Alex Carter',44,'adult',TRUE,'self'),
  ('RG-0002','RES-0001',NULL,'Jordan Carter',41,'adult',FALSE,'spouse'),
  ('RG-0003','RES-0001',NULL,'Sam Carter',12,'minor',FALSE,'child');

-- room stay (comped suite)
INSERT INTO room_stay (room_stay_id, reservation_id, room_type_code, room_number, rate_plan_code, nightly_rate, is_comped, occupancy_adults, occupancy_minors) VALUES
  ('RS-0001','RES-0001','SUITE-PANO','3201','BLACKCOMP',0.00,TRUE,2,1);

-- pre-booked event (locked dinner) — drives conflict avoidance
INSERT INTO pre_booked_event (event_id, reservation_id, venue_id, offering_id, title, segment, venue_name, starts_at, ends_at, party_count, is_locked, source_system) VALUES
  ('EVT-0001','RES-0001','VEN-0006','OFR-0006','SW Steakhouse Dinner','dining','SW Steakhouse','2026-09-19 20:00:00','2026-09-19 21:30:00',3,TRUE,'OpenTable');

-- schedule constraint (child bedtime quiet window)
INSERT INTO stay_schedule_constraint (constraint_id, reservation_id, constraint_date, earliest_start, latest_end, quiet_window, note) VALUES
  ('CON-0001','RES-0001','2026-09-19','09:00','22:00','22:00-08:00','Child bedtime by 22:00');

-- consent (contact PII granted; marketing not)
INSERT INTO guest_consent (consent_id, guest_id, scope, granted, granted_at, expires_at, source) VALUES
  ('CNS-0001','GST-0002','pii:contact',TRUE ,'2026-08-01 10:00:00','2027-08-01 10:00:00','app'),
  ('CNS-0002','GST-0002','marketing'  ,FALSE,'2026-08-01 10:00:00',NULL               ,'app');

-- venues (owned + partner)
INSERT INTO venue (venue_id, provider_id, venue_name, category_id, property_code, opens_time, closes_time, capacity, min_age, is_active) VALUES
  ('VEN-0001','PRV-LYNN','Lynn Theater',4,'LYNN','19:00','22:30',200,NULL,TRUE),
  ('VEN-0002','PRV-LYNN','The Spa at Lynn',5,'LYNN','08:00','20:00',40,18,TRUE),
  ('VEN-0003','PRV-LYNN','Encore Beach Club',6,'LYNN','11:00','19:00',300,21,TRUE),
  ('VEN-0004','PRV-LYNN','Lynn Esplanade',3,'LYNN','10:00','23:00',999,NULL,TRUE),
  ('VEN-0005','PRV-LYNN','High-Limit Salon',1,'LYNN','12:00','23:59',50,21,TRUE),
  ('VEN-0006','PRV-LYNN','SW Steakhouse',2,'LYNN','17:00','23:00',40,NULL,TRUE),
  ('VEN-0007','PRV-CIRQ','Encore Theater',4,'LYNN','20:00','22:00',180,NULL,TRUE),
  ('VEN-0008','PRV-SKY','Lynn Helipad',4,'LYNN','07:00','16:00',12,NULL,TRUE),
  ('VEN-0009','PRV-BOTT','Bottega Luxe Boutique',3,'LYNN','10:00','22:00',50,NULL,TRUE);

-- offerings
INSERT INTO offering (offering_id, venue_id, provider_id, title, category_id, segment, typical_start, duration_min, base_price, currency, is_age_restricted, min_age, is_bookable, availability_status) VALUES
  ('OFR-0001','VEN-0001','PRV-LYNN','Le Rêve — The Dream',8,'show','19:00',90,150.00,'USD',FALSE,NULL,TRUE,'available'),
  ('OFR-0002','VEN-0002','PRV-LYNN','Signature Spa Day',9,'spa','10:00',120,180.00,'USD',TRUE,18,TRUE,'available'),
  ('OFR-0003','VEN-0003','PRV-LYNN','Beach Club Daybed',6,'dayclub','11:00',480,75.00,'USD',TRUE,21,TRUE,'available'),
  ('OFR-0004','VEN-0004','PRV-LYNN','Esplanade Shopping Experience',3,'retail','14:00',90,0.00,'USD',FALSE,NULL,TRUE,'available'),
  ('OFR-0005','VEN-0005','PRV-LYNN','High-Limit Baccarat Seat',7,'table','21:00',180,0.00,'USD',TRUE,21,TRUE,'available'),
  ('OFR-0006','VEN-0006','PRV-LYNN','SW Steakhouse Chef''s Table',2,'dining','20:00',120,295.00,'USD',FALSE,NULL,TRUE,'available'),
  ('OFR-0007','VEN-0007','PRV-CIRQ','Cirque Aqua Show',8,'show','20:00',120,129.00,'USD',FALSE,NULL,TRUE,'available'),
  ('OFR-0008','VEN-0008','PRV-SKY','Grand Canyon Helicopter Tour',4,'tour','07:00',240,499.00,'USD',FALSE,NULL,TRUE,'available'),
  ('OFR-0009','VEN-0009','PRV-BOTT','Bottega Luxe Personal Shopping',3,'retail','11:00',60,0.00,'USD',FALSE,NULL,TRUE,'available');

-- promotions (offering-scoped, tier + age gated)
INSERT INTO promotion (promo_id, offering_id, provider_id, promo_code, title, comp_tier_required, discount_type, discount_value, redemption_rules, valid_from, valid_to, is_active) VALUES
  ('PRM-0001','OFR-0006','PRV-LYNN','BLKDINE','Black Dining Credit',2,'amount',500.00,'One per stay; excludes tax/gratuity','2026-01-01','2026-12-31',TRUE),
  ('PRM-0002','OFR-0002','PRV-LYNN','CHRSPA','Chairman Spa Comp',3,'amount',750.00,'One per stay; 18+','2026-01-01','2026-12-31',TRUE),
  ('PRM-0003','OFR-0005','PRV-LYNN','HLMATCH','High-Limit Match Play',2,'amount',1000.00,'Match on first buy-in; 21+','2026-01-01','2026-12-31',TRUE),
  ('PRM-0004','OFR-0001','PRV-LYNN','SHOW2','Show Ticket 2-for-1',1,'percent',50.00,'Buy one get one; select shows','2026-01-01','2026-12-31',TRUE);

-- interests (0..100). Alex trip-scoped to RES-0001; Marcus profile-level.
INSERT INTO guest_interest (guest_interest_id, guest_id, reservation_id, category_id, affinity_score, is_explicit, source, captured_at) VALUES
  ('GI-0001','GST-0002','RES-0001',1,90,TRUE ,'stated'  ,'2026-08-10 09:00:00'),
  ('GI-0002','GST-0002','RES-0001',2,80,TRUE ,'stated'  ,'2026-08-10 09:00:00'),
  ('GI-0003','GST-0002','RES-0001',4,60,TRUE ,'stated'  ,'2026-08-10 09:00:00'),
  ('GI-0004','GST-0002','RES-0001',6,40,FALSE,'play_hist','2026-08-10 09:00:00'),
  ('GI-0005','GST-0002','RES-0001',5,30,FALSE,'play_hist','2026-08-10 09:00:00'),
  ('GI-0006','GST-0003',NULL      ,2,90,TRUE ,'stated'  ,'2026-08-11 09:00:00'),
  ('GI-0007','GST-0003',NULL      ,5,70,TRUE ,'stated'  ,'2026-08-11 09:00:00'),
  ('GI-0008','GST-0003',NULL      ,3,60,TRUE ,'stated'  ,'2026-08-11 09:00:00'),
  ('GI-0009','GST-0003',NULL      ,4,50,FALSE,'play_hist','2026-08-11 09:00:00'),
  ('GI-0010','GST-0003',NULL      ,1,20,FALSE,'play_hist','2026-08-11 09:00:00');

-- persisted recommendations for the hero (shows WHY items were suppressed)
INSERT INTO reservation_offer_recommendation (rec_id, reservation_id, offering_id, matched_category_id, match_score, is_age_eligible, is_tier_eligible, suppressed_reason) VALUES
  ('REC-0001','RES-0001','OFR-0001',8,0.80,TRUE ,TRUE ,NULL),
  ('REC-0002','RES-0001','OFR-0006',2,0.78,TRUE ,TRUE ,NULL),
  ('REC-0003','RES-0001','OFR-0008',4,0.62,TRUE ,TRUE ,NULL),
  ('REC-0004','RES-0001','OFR-0005',7,0.90,FALSE,TRUE ,'minor_present:age_restricted(21)'),
  ('REC-0005','RES-0001','OFR-0003',6,0.40,FALSE,TRUE ,'minor_present:age_restricted(21)'),
  ('REC-0006','RES-0001','OFR-0002',9,0.30,FALSE,FALSE,'minor_present:age_restricted(18)');

-- sample access-audit row
INSERT INTO reservation_access_audit (reservation_id, accessed_by, mcp_tool, action, fields_returned, request_context) VALUES
  ('RES-0001','itinerary-agent','getReservation','read',
   JSON_ARRAY('confirmation_code','check_in_date','check_out_date','comp_tier_id'),
   JSON_OBJECT('consent','pii:contact','client_id','broker-demo'));
