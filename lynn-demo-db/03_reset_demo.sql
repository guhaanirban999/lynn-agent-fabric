-- ============================================================
-- Lynn Agent Fabric Demo — RESET transactional data to baseline
-- 03_reset_demo.sql   (run against Aiven `lynn_demo` before a demo)
-- ------------------------------------------------------------
-- Clears accumulated test bookings/comps and restores the seed
-- baseline. Reference data (guests, room_types, restaurants,
-- gaming_tables) is left untouched. TRUNCATE also resets each
-- table's AUTO_INCREMENT so new demo bookings get clean IDs.
-- ============================================================
USE lynn_demo;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE room_reservations;
TRUNCATE TABLE dining_reservations;
TRUNCATE TABLE table_reservations;
TRUNCATE TABLE comps;
SET FOREIGN_KEY_CHECKS = 1;

-- Baseline reservations/comps (identical to 02_seed.sql)
INSERT INTO room_reservations (guest_id,room_type_id,check_in,check_out,num_guests,rate_quoted,status) VALUES
 (2,4,'2026-09-12','2026-09-14',2,999.00,'confirmed'),
 (4,3,'2026-09-18','2026-09-20',2,629.00,'confirmed'),
 (7,6,'2026-09-25','2026-09-27',3,749.00,'confirmed');

INSERT INTO dining_reservations (guest_id,restaurant_id,reservation_datetime,party_size,status) VALUES
 (2,4,'2026-09-12 19:30:00',2,'confirmed'),
 (4,1,'2026-09-18 20:00:00',2,'confirmed'),
 (7,2,'2026-09-25 19:00:00',4,'confirmed');

INSERT INTO table_reservations (guest_id,table_id,reservation_datetime,party_size,status) VALUES
 (2,2,'2026-09-12 22:00:00',1,'confirmed'),
 (6,1,'2026-09-19 21:30:00',2,'confirmed');

INSERT INTO comps (guest_id,comp_type,value,status,reason) VALUES
 (1,'dining',500.00,'issued','Black tier anniversary dining credit'),
 (2,'room',2000.00,'issued','Chairman tier — 2 nights Tower Suite'),
 (1,'show',300.00,'evaluated','Eligible for Awakening tickets based on recent play');

-- Sanity check
SELECT 'room_reservations' t, COUNT(*) n FROM room_reservations
UNION ALL SELECT 'dining_reservations', COUNT(*) FROM dining_reservations
UNION ALL SELECT 'table_reservations', COUNT(*) FROM table_reservations
UNION ALL SELECT 'comps', COUNT(*) FROM comps;
