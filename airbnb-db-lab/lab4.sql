-- =====================================================================
-- ЛАБОРАТОРНАЯ РАБОТА №4
-- Исследование индексирования и оптимизации запросов в PostgreSQL
-- Вариант 2: Airbnb-подобный сервис
-- =====================================================================
-- Основная таблица для индексирования: bookings (1 000 000 строк)
-- =====================================================================


-- =====================================================================
-- ЧАСТЬ 1: ПОДГОТОВКА ТЕСТОВЫХ ДАННЫХ
-- =====================================================================

-- Отключаем триггеры и FK-проверки для ускорения массовой вставки
SET session_replication_role = replica;

-- Очищаем таблицы
TRUNCATE reviews, bookings, properties, users RESTART IDENTITY CASCADE;

-- Добавляем колонку booking_count (если ещё не добавлена лабой 3)
ALTER TABLE properties ADD COLUMN IF NOT EXISTS booking_count INT DEFAULT 0;

-- Генерируем 10 000 пользователей
INSERT INTO users (name, email, phone, created_at)
SELECT
    'User_' || i,
    'user' || i || '@example.com',
    '+7900' || LPAD(i::text, 7, '0'),
    CURRENT_TIMESTAMP - (i % 1095) * INTERVAL '1 day'
FROM generate_series(1, 10000) AS s(i);

-- Генерируем 5 000 объектов недвижимости
INSERT INTO properties (host_id, title, description, city, address, price_per_night, max_guests, booking_count)
SELECT
    (i % 10000) + 1,
    (ARRAY['Cozy', 'Luxury', 'Modern', 'Vintage', 'Spacious'])[1 + i%5]
        || ' '
        || (ARRAY['Apartment', 'House', 'Studio', 'Villa', 'Cottage'])[1 + (i/5)%5],
    (ARRAY[
        'Beautiful cozy place near the city centre. Great for couples.',
        'Luxury accommodation with full amenities and stunning views.',
        'Modern studio in the heart of the city. Perfect for business.',
        'Vintage apartment with charming Soviet-era decor. Unique experience.',
        'Spacious house with garden, perfect for families with children.'
    ])[1 + i%5],
    (ARRAY['Moscow', 'Saint Petersburg', 'Sochi', 'Kazan',
           'Novosibirsk', 'Yekaterinburg', 'Vladivostok', 'Ufa'])[1 + i%8],
    'ul. Lenina ' || (i%200 + 1) || ', kv. ' || (i%100 + 1),
    (500 + (i % 95) * 100)::decimal(10,2),
    (1 + i%8),
    0
FROM generate_series(1, 5000) AS s(i);

-- Генерируем 1 000 000 бронирований
-- check_out всегда > check_in (разница 1–14 дней)
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
SELECT
    (i % 5000) + 1,
    (i % 10000) + 1,
    '2022-01-01'::date + (i % 730),
    '2022-01-01'::date + (i % 730) + (i % 14 + 1),
    (1000 + (i % 50) * 1000)::decimal(10, 2),
    (ARRAY['pending', 'confirmed', 'cancelled', 'completed'])[1 + i%4]
FROM generate_series(1, 1000000) AS s(i);

-- Возвращаем триггеры
SET session_replication_role = DEFAULT;

-- Обновляем booking_count вручную (триггер был отключён)
UPDATE properties p
SET booking_count = (SELECT COUNT(*) FROM bookings b WHERE b.property_id = p.property_id);

-- Обновляем статистику планировщика
ANALYZE users;
ANALYZE properties;
ANALYZE bookings;

-- Проверяем объём данных
SELECT table_name, row_count FROM (
    SELECT 'users'      AS table_name, COUNT(*) AS row_count FROM users
    UNION ALL
    SELECT 'properties', COUNT(*) FROM properties
    UNION ALL
    SELECT 'bookings',   COUNT(*) FROM bookings
) t;


-- =====================================================================
-- СЦЕНАРИЙ 1: Сложный фильтр (точное сравнение + диапазон)
-- =====================================================================
-- Запрос: подтверждённые бронирования за 2023 год с ценой > 20 000 руб.

DROP INDEX IF EXISTS idx_s1_status_checkin;

-- ===== ДО ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT booking_id, property_id, guest_id, check_in, check_out, total_price
FROM bookings
WHERE status = 'confirmed'
  AND check_in BETWEEN '2023-01-01' AND '2023-12-31'
  AND total_price > 20000;
-- Ожидается: Seq Scan на 1 000 000 строк → медленно

-- Гипотеза: составной индекс (status, check_in) позволяет PostgreSQL
-- применить точный фильтр по status, а потом Range Scan по check_in,
-- не просматривая остальные строки.

-- ===== СОЗДАНИЕ ИНДЕКСА =====
CREATE INDEX idx_s1_status_checkin ON bookings(status, check_in);
ANALYZE bookings;

-- ===== ПОСЛЕ ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT booking_id, property_id, guest_id, check_in, check_out, total_price
FROM bookings
WHERE status = 'confirmed'
  AND check_in BETWEEN '2023-01-01' AND '2023-12-31'
  AND total_price > 20000;
-- Ожидается: Bitmap Index Scan / Index Scan через idx_s1_status_checkin


-- =====================================================================
-- СЦЕНАРИЙ 2: Сортировка с ограничением (ORDER BY + LIMIT)
-- =====================================================================
-- Запрос: 20 самых дорогих завершённых бронирований

DROP INDEX IF EXISTS idx_s2_status_price;

-- ===== ДО ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT booking_id, property_id, total_price, status
FROM bookings
WHERE status = 'completed'
ORDER BY total_price DESC
LIMIT 20;
-- Ожидается: Seq Scan + Sort на ~250 000 строк

-- Гипотеза: составной индекс (status, total_price DESC) даёт планировщику
-- готовый упорядоченный доступ — первые 20 строк берутся без полной сортировки.

-- ===== СОЗДАНИЕ ИНДЕКСА =====
CREATE INDEX idx_s2_status_price ON bookings(status, total_price DESC);
ANALYZE bookings;

-- ===== ПОСЛЕ ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT booking_id, property_id, total_price, status
FROM bookings
WHERE status = 'completed'
ORDER BY total_price DESC
LIMIT 20;
-- Ожидается: Index Scan через idx_s2_status_price без узла Sort


-- =====================================================================
-- СЦЕНАРИЙ 3: Альтернативные варианты индексирования
-- =====================================================================
-- Запрос: бронирования конкретного гостя, отсортированные по дате заезда (DESC)

DROP INDEX IF EXISTS idx_s3a_guest_id;
DROP INDEX IF EXISTS idx_s3b_guest_checkin;

-- ===== ДО ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT booking_id, property_id, check_in, check_out, status
FROM bookings
WHERE guest_id = 42
ORDER BY check_in DESC;
-- Ожидается: Seq Scan + Sort

-- ===== ВАРИАНТ А: простой индекс по guest_id =====
CREATE INDEX idx_s3a_guest_id ON bookings(guest_id);
ANALYZE bookings;

EXPLAIN ANALYZE
SELECT booking_id, property_id, check_in, check_out, status
FROM bookings
WHERE guest_id = 42
ORDER BY check_in DESC;
-- Index Scan по guest_id, НО требуется дополнительный узел Sort по check_in

DROP INDEX idx_s3a_guest_id;

-- ===== ВАРИАНТ Б: составной индекс (guest_id, check_in DESC) =====
CREATE INDEX idx_s3b_guest_checkin ON bookings(guest_id, check_in DESC);
ANALYZE bookings;

EXPLAIN ANALYZE
SELECT booking_id, property_id, check_in, check_out, status
FROM bookings
WHERE guest_id = 42
ORDER BY check_in DESC;
-- Index Scan без узла Sort — порядок уже закодирован в индексе.
-- Вывод: вариант Б лучше — устраняет этап сортировки.


-- =====================================================================
-- СЦЕНАРИЙ 4: Текстовый поиск (подстрока, префикс, суффикс)
-- =====================================================================
-- Таблица properties.title (5 000 строк)

DROP INDEX IF EXISTS idx_s4_title_btree;
DROP INDEX IF EXISTS idx_s4_title_trgm;

-- ===== ДО ИНДЕКСИРОВАНИЯ =====

-- 4а) Поиск по префиксу
EXPLAIN ANALYZE
SELECT property_id, title, city FROM properties WHERE title LIKE 'Cozy%';

-- 4б) Поиск по подстроке
EXPLAIN ANALYZE
SELECT property_id, title, city FROM properties WHERE title LIKE '%Apartment%';

-- 4в) Поиск по суффиксу
EXPLAIN ANALYZE
SELECT property_id, title, city FROM properties WHERE title LIKE '%Cottage';
-- Все три: Seq Scan

-- Гипотеза А: B-tree индекс ускоряет только поиск по ПРЕФИКСУ (LIKE 'X%').
-- Гипотеза Б: GIN-индекс с расширением pg_trgm покрывает все три паттерна.

-- ===== ВАРИАНТ А: B-tree (только для префикса) =====
CREATE INDEX idx_s4_title_btree ON properties(title);
ANALYZE properties;

-- Для корректного сравнения форсируем использование индекса
SET enable_seqscan = off;

EXPLAIN ANALYZE SELECT property_id, title FROM properties WHERE title LIKE 'Cozy%';
-- Index Scan — работает для префикса

EXPLAIN ANALYZE SELECT property_id, title FROM properties WHERE title LIKE '%Apartment%';
-- Seq Scan — B-tree не поддерживает поиск по подстроке

SET enable_seqscan = on;
DROP INDEX idx_s4_title_btree;

-- ===== ВАРИАНТ Б: GIN + pg_trgm (для всех паттернов) =====
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_s4_title_trgm ON properties USING GIN(title gin_trgm_ops);
ANALYZE properties;

SET enable_seqscan = off;

EXPLAIN ANALYZE SELECT property_id, title FROM properties WHERE title LIKE 'Cozy%';
EXPLAIN ANALYZE SELECT property_id, title FROM properties WHERE title LIKE '%Apartment%';
EXPLAIN ANALYZE SELECT property_id, title FROM properties WHERE title LIKE '%Cottage';
-- Все три: Bitmap Index Scan через idx_s4_title_trgm

SET enable_seqscan = on;
-- Вывод: для произвольного текстового поиска нужен GIN с pg_trgm.
-- B-tree применим лишь для фиксированных префиксов.


-- =====================================================================
-- СЦЕНАРИЙ 5: Соединение таблиц (JOIN)
-- =====================================================================
-- Запрос: подтверждённые бронирования в Москве с именем гостя и названием объекта

DROP INDEX IF EXISTS idx_s5_city;
DROP INDEX IF EXISTS idx_s5_bk_property;
DROP INDEX IF EXISTS idx_s5_bk_status_property;

-- ===== ДО ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT
    b.booking_id,
    u.name  AS guest_name,
    p.title AS property_title,
    p.city,
    b.check_in,
    b.check_out,
    b.total_price
FROM bookings b
JOIN properties p ON b.property_id = p.property_id
JOIN users     u ON b.guest_id     = u.user_id
WHERE p.city   = 'Moscow'
  AND b.status = 'confirmed';
-- Ожидается: Seq Scan на bookings + Hash Join

-- Гипотеза: индекс на properties.city ускорит фильтр по городу,
-- индекс на bookings.property_id ускорит JOIN с properties.

-- ===== СОЗДАНИЕ ИНДЕКСОВ =====
CREATE INDEX idx_s5_city            ON properties(city);
CREATE INDEX idx_s5_bk_property     ON bookings(property_id);
ANALYZE properties;
ANALYZE bookings;

-- ===== ПОСЛЕ ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT
    b.booking_id,
    u.name  AS guest_name,
    p.title AS property_title,
    p.city,
    b.check_in,
    b.check_out,
    b.total_price
FROM bookings b
JOIN properties p ON b.property_id = p.property_id
JOIN users     u ON b.guest_id     = u.user_id
WHERE p.city   = 'Moscow'
  AND b.status = 'confirmed';
-- Ожидается: Index Scan на properties(city) + Nested Loop / Hash Join через индекс


-- =====================================================================
-- СЦЕНАРИЙ 6: Негативный сценарий — индекс не даёт прироста
-- =====================================================================
-- Запрос: GROUP BY по полю с низкой селективностью (4 уникальных значения)

DROP INDEX IF EXISTS idx_s6_status;

-- ===== ДО ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT status, COUNT(*) AS cnt, AVG(total_price) AS avg_price
FROM bookings
GROUP BY status;
-- Seq Scan — нужно прочитать всю таблицу в любом случае

-- Гипотеза: индекс на status не поможет, т.к. при 4 значениях
-- каждое встречается в ~25% строк (250 000 строк). Чтение через индекс
-- при такой «низкой селективности» дороже, чем последовательный просмотр.

-- ===== СОЗДАНИЕ ИНДЕКСА =====
CREATE INDEX idx_s6_status ON bookings(status);
ANALYZE bookings;

-- ===== ПОСЛЕ ИНДЕКСИРОВАНИЯ =====
EXPLAIN ANALYZE
SELECT status, COUNT(*) AS cnt, AVG(total_price) AS avg_price
FROM bookings
GROUP BY status;
-- Планировщик выбирает Seq Scan — индекс проигнорирован.
-- Подтверждение: включаем принудительное использование индекса:
SET enable_seqscan = off;
EXPLAIN ANALYZE
SELECT status, COUNT(*) AS cnt, AVG(total_price) AS avg_price
FROM bookings GROUP BY status;
-- Время с индексом ХУЖЕ или сопоставимо с Seq Scan → индекс бесполезен.
SET enable_seqscan = on;

-- Вывод: индексы эффективны при высокой селективности (< 5–10% строк).
-- Для агрегаций по полю с малым числом уникальных значений индекс не нужен.


-- =====================================================================
-- ДОПОЛНИТЕЛЬНОЕ ИССЛЕДОВАНИЕ: Влияние индексов на INSERT / UPDATE
-- =====================================================================

-- Удаляем все тестовые индексы для «чистого» состояния
DROP INDEX IF EXISTS idx_s1_status_checkin;
DROP INDEX IF EXISTS idx_s2_status_price;
DROP INDEX IF EXISTS idx_s3b_guest_checkin;
DROP INDEX IF EXISTS idx_s4_title_trgm;
DROP INDEX IF EXISTS idx_s5_city;
DROP INDEX IF EXISTS idx_s5_bk_property;
DROP INDEX IF EXISTS idx_s6_status;

ANALYZE bookings;

-- ===== ТЕСТ INSERT БЕЗ ДОПОЛНИТЕЛЬНЫХ ИНДЕКСОВ =====
-- (присутствует только PK-индекс на booking_id)
EXPLAIN ANALYZE
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
SELECT
    (i % 5000) + 1,
    (i % 10000) + 1,
    '2025-01-01'::date + (i % 365),
    '2025-01-01'::date + (i % 365) + 3,
    5000,
    'pending'
FROM generate_series(1, 10000) AS s(i);
-- Запоминаем время из строки "Execution Time: X ms"

-- Очищаем тестовые строки
DELETE FROM bookings WHERE check_in >= '2025-01-01';

-- ===== СОЗДАЁМ 4 ДОПОЛНИТЕЛЬНЫХ ИНДЕКСА =====
CREATE INDEX idx_perf_status_checkin ON bookings(status, check_in);
CREATE INDEX idx_perf_status_price   ON bookings(status, total_price DESC);
CREATE INDEX idx_perf_guest_checkin  ON bookings(guest_id, check_in DESC);
CREATE INDEX idx_perf_property_id    ON bookings(property_id);

-- ===== ТЕСТ INSERT С ИНДЕКСАМИ =====
EXPLAIN ANALYZE
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
SELECT
    (i % 5000) + 1,
    (i % 10000) + 1,
    '2025-01-01'::date + (i % 365),
    '2025-01-01'::date + (i % 365) + 3,
    5000,
    'pending'
FROM generate_series(1, 10000) AS s(i);
-- Ожидается: время БОЛЬШЕ — каждая строка требует обновления 4 индексов

-- ===== ТЕСТ UPDATE =====
-- UPDATE по проиндексированному полю (быстрый поиск строк):
EXPLAIN ANALYZE
UPDATE bookings SET total_price = total_price * 1.1
WHERE status = 'pending' AND check_in = '2025-03-15';
-- Ожидается: Index Scan по idx_perf_status_checkin + быстрое обновление

-- Очищаем
DELETE FROM bookings WHERE check_in >= '2025-01-01';
DROP INDEX IF EXISTS idx_perf_status_checkin;
DROP INDEX IF EXISTS idx_perf_status_price;
DROP INDEX IF EXISTS idx_perf_guest_checkin;
DROP INDEX IF EXISTS idx_perf_property_id;

-- =====================================================================
-- ВЫВОД ПО ДОПОЛНИТЕЛЬНОМУ ИССЛЕДОВАНИЮ:
-- INSERT без доп. индексов быстрее, т.к. нет накладных расходов на
-- обновление B-tree структур. INSERT с 4 индексами ощутимо медленнее.
-- UPDATE по проиндексированному WHERE значительно быстрее, чем Seq Scan.
-- Компромисс: индексы замедляют запись, но ускоряют чтение.
-- =====================================================================
