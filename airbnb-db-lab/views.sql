-- Информация о жилье и владельце
CREATE VIEW property_hosts AS
SELECT
p.property_id,
p.title,
p.city,
p.price_per_night,
u.name AS host_name
FROM properties p
JOIN users u
ON p.host_id = u.user_id;

-- Общая сумма бронирований по объектам
CREATE VIEW property_revenue AS
SELECT
p.title,
SUM(b.total_price) AS total_income
FROM properties p
JOIN bookings b
ON p.property_id = b.property_id
GROUP BY p.title;

-- Средний рейтинг объектов
CREATE VIEW property_ratings AS
SELECT
p.title,
AVG(r.rating) AS avg_rating
FROM properties p
JOIN bookings b ON p.property_id = b.property_id
JOIN reviews r ON b.booking_id = r.booking_id
GROUP BY p.title;