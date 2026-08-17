-- ============================================================
-- casino_demo — room inventory for search_rooms / book_room (v3.1)
-- 08_casino_demo_rooms.sql  (run after 06/07)
-- Adds a room_type catalog (inventory + rate + occupancy) so lodging
-- availability + booking work. room_stay.room_type_code -> room_type
-- (FK added by the runner, guarded). Idempotent table + seed.
-- ============================================================
USE casino_demo;

CREATE TABLE IF NOT EXISTS room_type (
  room_type_code    VARCHAR(40) PRIMARY KEY,
  room_type_name    VARCHAR(80) NOT NULL,
  property_code     VARCHAR(20) NOT NULL,      -- LYNN | ENCORE
  description       VARCHAR(255),
  base_nightly_rate DECIMAL(12,2) NOT NULL,
  max_occupancy     INT NOT NULL,
  total_inventory   INT NOT NULL
) ENGINE=InnoDB;

INSERT INTO room_type (room_type_code, room_type_name, property_code, description, base_nightly_rate, max_occupancy, total_inventory) VALUES
  ('STD-LYNN',    'Lynn Deluxe King',   'LYNN',  'Deluxe king room, Lynn tower',        650.00, 2, 40),
  ('STD-ENCORE',  'Encore Resort King', 'ENCORE','Resort king room, Encore tower',      700.00, 2, 40),
  ('SUITE-PANO',  'Panoramic Suite',    'LYNN',  'Corner suite with Strip views',      1200.00, 4, 10),
  ('SUITE-TOWER', 'Tower Suite',        'ENCORE','Tower suite, Encore',                1500.00, 4,  8),
  ('VILLA',       'Duplex Villa',       'LYNN',  'Private two-story villa',            5000.00, 6,  3)
AS new ON DUPLICATE KEY UPDATE room_type_name=new.room_type_name, base_nightly_rate=new.base_nightly_rate,
  max_occupancy=new.max_occupancy, total_inventory=new.total_inventory;
