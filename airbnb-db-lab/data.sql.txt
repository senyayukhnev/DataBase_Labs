INSERT INTO users (name, email, phone)
VALUES ('Ivan Ivanov', 'ivan@mail.com', '+491234567');

INSERT INTO users (name, email)
VALUES ('Anna Petrova', 'anna@mail.com');

INSERT INTO properties (host_id, title, city, price_per_night, max_guests)
VALUES (1, 'Cozy Apartment', 'Berlin', 80, 2);

INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (1, 2, '2026-06-01', '2026-06-05', 320, 'confirmed');

INSERT INTO reviews (booking_id, rating, comment)
VALUES (1, 5, 'Great apartment!');