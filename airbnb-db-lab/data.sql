-- TRUNCATE автоматически сбрасывает последовательности
TRUNCATE TABLE reviews, bookings, properties, users RESTART IDENTITY CASCADE;

INSERT INTO users (name, email, phone) 
VALUES 
('Ivan Ivanov', 'ivan@mail.com', '+491234567'),
('Anna Petrova', 'anna@mail.com', '987654'),
('John Smith', 'john@mail.com', '555111');

INSERT INTO properties (host_id, title, city, price_per_night, max_guests) 
VALUES 
(1, 'Cozy Apartment', 'Berlin', 80, 2),
(1, 'City Studio', 'Berlin', 60, 2),
(2, 'Big House', 'Munich', 150, 6);

INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status) 
VALUES 
(1, 2, '2026-06-01', '2026-06-05', 320, 'confirmed'),
(2, 3, '2026-06-10', '2026-06-12', 120, 'confirmed'),
(3, 1, '2026-07-01', '2026-07-07', 900, 'confirmed');

INSERT INTO reviews (booking_id, rating, comment) 
VALUES 
(1, 5, 'Excellent stay'),
(2, 4, 'Nice apartment');