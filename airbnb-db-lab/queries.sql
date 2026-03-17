-- Простые DML операции
INSERT INTO users (name,email)
VALUES ('Maria Keller','maria@mail.com');

UPDATE properties
SET price_per_night = 90
WHERE property_id = 1;

DELETE FROM reviews
WHERE review_id = 2;

-- Агрегатные запросы
SELECT city, COUNT(*) AS property_count
FROM properties
GROUP BY city
ORDER BY property_count DESC;

SELECT city, AVG(price_per_night) AS avg_price
FROM properties
GROUP BY city;

SELECT SUM(total_price) AS total_revenue
FROM bookings;

SELECT city, COUNT(*)
FROM properties
GROUP BY city
HAVING COUNT(*) > 1;

-- JOIN запросы

-- Гости и их бронирования
SELECT u.name, b.booking_id, b.check_in, b.check_out
FROM bookings b
INNER JOIN users u
ON b.guest_id = u.user_id;

-- Объекты и их владельцы
SELECT p.title, u.name AS host
FROM properties p
INNER JOIN users u
ON p.host_id = u.user_id;

-- Бронирования и отзывы
SELECT b.booking_id, r.rating, r.comment
FROM bookings b
LEFT JOIN reviews r
ON b.booking_id = r.booking_id;
