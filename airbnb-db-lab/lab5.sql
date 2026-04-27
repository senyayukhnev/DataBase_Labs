-- =====================================================================
-- ЛАБОРАТОРНАЯ РАБОТА №5
-- Исследование транзакций в PostgreSQL
-- Вариант 2: Airbnb-подобный сервис
-- =====================================================================
-- Три бизнес-сценария:
--   1. Создание бронирования
--   2. Добавление отзыва
--   3. Отмена бронирования
-- =====================================================================

-- Убеждаемся, что данные есть (запустите lab4.sql перед этим файлом)
SELECT 'users'      AS tbl, COUNT(*) FROM users
UNION ALL
SELECT 'properties', COUNT(*) FROM properties
UNION ALL
SELECT 'bookings',   COUNT(*) FROM bookings;


-- =====================================================================
-- СЦЕНАРИЙ 1: Создание бронирования
-- Бизнес-логика: гость бронирует объект → запись в bookings +
--                инкремент booking_count в properties.
-- =====================================================================

-- ─────────────────────────────────────────────────────────────────────
-- 1А. Успешное выполнение (COMMIT)
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (1, 2, '2025-07-01', '2025-07-07', 12000.00, 'pending');

UPDATE properties SET booking_count = booking_count + 1 WHERE property_id = 1;

-- Промежуточная проверка (видно только внутри транзакции)
SELECT b.booking_id, b.status, b.check_in,
       p.booking_count
FROM bookings b, properties p
WHERE b.property_id = 1 AND p.property_id = 1
ORDER BY b.booking_id DESC LIMIT 1;

COMMIT;

SELECT '1А: транзакция зафиксирована' AS result;
SELECT booking_id, status FROM bookings ORDER BY booking_id DESC LIMIT 1;


-- ─────────────────────────────────────────────────────────────────────
-- 1Б. Ошибка → полный откат (ROLLBACK)
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (2, 3, '2025-08-01', '2025-08-07', 14000.00, 'pending');

-- Нарушение внешнего ключа: несуществующий property_id → транзакция прерывается
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (999999, 3, '2025-08-10', '2025-08-12', 5000.00, 'pending');

-- Эта строка не выполнится — транзакция уже в состоянии ошибки
UPDATE properties SET booking_count = booking_count + 1 WHERE property_id = 2;

ROLLBACK;

SELECT '1Б: транзакция отменена — оба INSERT отклонены' AS result;
-- Проверяем: бронирований за 2025-08 нет
SELECT COUNT(*) AS should_be_0 FROM bookings WHERE check_in = '2025-08-01';


-- ─────────────────────────────────────────────────────────────────────
-- 1В. Частичный откат (SAVEPOINT)
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

-- Шаг 1: создаём бронирование
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (3, 4, '2025-09-01', '2025-09-05', 8000.00, 'pending');

SAVEPOINT after_insert;

-- Шаг 2: ошибочно применяем скидку → отрицательная цена
UPDATE bookings SET total_price = -500 WHERE check_in = '2025-09-01' AND guest_id = 4;
-- В реальной схеме здесь был бы CHECK(total_price > 0); откатываемся к точке сохранения

ROLLBACK TO SAVEPOINT after_insert;

-- Шаг 3: корректная скидка 10%
UPDATE bookings SET total_price = 7200.00 WHERE check_in = '2025-09-01' AND guest_id = 4;

UPDATE properties SET booking_count = booking_count + 1 WHERE property_id = 3;

COMMIT;

SELECT '1В: бронирование создано, частичный откат применён' AS result;
SELECT booking_id, total_price, status
FROM bookings WHERE check_in = '2025-09-01' AND guest_id = 4;


-- =====================================================================
-- СЦЕНАРИЙ 2: Добавление отзыва
-- Бизнес-логика: гость оставляет отзыв только для завершённого бронирования.
-- =====================================================================

-- Готовим тестовое завершённое бронирование
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (1, 5, '2024-01-10', '2024-01-15', 6000.00, 'completed')
RETURNING booking_id;
-- Запомните полученный booking_id; ниже обозначается как <completed_id>

-- ─────────────────────────────────────────────────────────────────────
-- 2А. Успешное добавление отзыва (COMMIT)
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_bid INT;
    v_status VARCHAR(50);
BEGIN
    -- Берём последнее завершённое бронирование без отзыва
    SELECT b.booking_id INTO v_bid
    FROM bookings b
    LEFT JOIN reviews r ON b.booking_id = r.booking_id
    WHERE b.status = 'completed' AND r.review_id IS NULL
    ORDER BY b.booking_id DESC LIMIT 1;

    IF v_bid IS NULL THEN
        RAISE EXCEPTION 'Нет подходящих бронирований';
    END IF;

    -- Проверяем статус
    SELECT status INTO v_status FROM bookings WHERE booking_id = v_bid;
    IF v_status <> 'completed' THEN
        RAISE EXCEPTION 'Отзыв можно оставить только для завершённого бронирования';
    END IF;

    INSERT INTO reviews (booking_id, rating, comment)
    VALUES (v_bid, 5, 'Отличное место, всё понравилось!');

    RAISE NOTICE '2А: отзыв добавлен для бронирования %', v_bid;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 2Б. Ошибка — повторный отзыв → UNIQUE violation → откат
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

-- Берём бронирование, для которого уже есть отзыв
DO $$
DECLARE v_bid INT;
BEGIN
    SELECT booking_id INTO v_bid FROM reviews LIMIT 1;
    -- Пытаемся вставить второй отзыв (reviews.booking_id UNIQUE)
    INSERT INTO reviews (booking_id, rating, comment)
    VALUES (v_bid, 3, 'Повторный отзыв — не должен быть добавлен');
END $$;

ROLLBACK;

SELECT '2Б: транзакция отменена — UNIQUE violation на booking_id' AS result;


-- ─────────────────────────────────────────────────────────────────────
-- 2В. Точка сохранения — некорректный рейтинг → частичный откат
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

-- Добавляем ещё одно завершённое бронирование без отзыва
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (2, 6, '2024-02-01', '2024-02-04', 4500.00, 'completed');

SAVEPOINT before_review;

-- Пытаемся вставить некорректный рейтинг → триггер check_rating_trigger откажет
DO $$
DECLARE v_bid INT;
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2024-02-01' AND guest_id = 6;

    INSERT INTO reviews (booking_id, rating, comment)
    VALUES (v_bid, 10, 'Рейтинг вне диапазона 1–5');
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '2В: ошибка триггера — %. Откат до SAVEPOINT.', SQLERRM;
END $$;

ROLLBACK TO SAVEPOINT before_review;

-- Вставляем корректный отзыв
DO $$
DECLARE v_bid INT;
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2024-02-01' AND guest_id = 6;

    INSERT INTO reviews (booking_id, rating, comment)
    VALUES (v_bid, 4, 'Хорошее место, рекомендую');
    RAISE NOTICE '2В: отзыв с корректным рейтингом добавлен';
END $$;

COMMIT;
SELECT '2В: отзыв добавлен после частичного отката' AS result;


-- =====================================================================
-- СЦЕНАРИЙ 3: Отмена бронирования
-- Бизнес-логика: гость отменяет подтверждённое бронирование →
--               статус меняется на 'cancelled', booking_count уменьшается.
-- =====================================================================

-- Создаём тестовые бронирования
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES
    (4, 7, '2025-10-01', '2025-10-05', 10000.00, 'confirmed'),  -- будем отменять
    (4, 8, '2025-10-10', '2025-10-15', 12000.00, 'confirmed')   -- для параллельных сессий
RETURNING booking_id, status;

-- ─────────────────────────────────────────────────────────────────────
-- 3А. Успешная отмена (COMMIT)
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

DO $$
DECLARE
    v_bid  INT;
    v_stat VARCHAR(50);
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2025-10-01' AND guest_id = 7;

    SELECT status INTO v_stat FROM bookings WHERE booking_id = v_bid FOR UPDATE;

    IF v_stat NOT IN ('pending', 'confirmed') THEN
        RAISE EXCEPTION 'Нельзя отменить бронирование со статусом %', v_stat;
    END IF;

    UPDATE bookings SET status = 'cancelled' WHERE booking_id = v_bid;

    UPDATE properties
    SET booking_count = GREATEST(booking_count - 1, 0)
    WHERE property_id = (SELECT property_id FROM bookings WHERE booking_id = v_bid);

    RAISE NOTICE '3А: бронирование % отменено', v_bid;
END $$;

COMMIT;

SELECT '3А: бронирование отменено' AS result;
SELECT booking_id, status FROM bookings WHERE check_in = '2025-10-01' AND guest_id = 7;


-- ─────────────────────────────────────────────────────────────────────
-- 3Б. Ошибка — попытка отменить уже отменённое бронирование → откат
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

DO $$
DECLARE
    v_bid  INT;
    v_stat VARCHAR(50);
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2025-10-01' AND guest_id = 7;

    SELECT status INTO v_stat FROM bookings WHERE booking_id = v_bid;

    IF v_stat = 'cancelled' THEN
        RAISE EXCEPTION 'Бронирование % уже отменено', v_bid;
    END IF;

    UPDATE bookings SET status = 'cancelled' WHERE booking_id = v_bid;
END $$;

ROLLBACK;

SELECT '3Б: транзакция отменена — нельзя повторно отменить' AS result;


-- ─────────────────────────────────────────────────────────────────────
-- 3В. SAVEPOINT — отмена + частичный возврат средств
-- ─────────────────────────────────────────────────────────────────────
BEGIN;

DO $$
DECLARE v_bid INT;
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2025-10-10' AND guest_id = 8;

    UPDATE bookings SET status = 'cancelled' WHERE booking_id = v_bid;
    RAISE NOTICE '3В: статус изменён на cancelled';
END $$;

SAVEPOINT after_cancel;

-- Ошибочно обнуляем цену
DO $$
DECLARE v_bid INT;
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2025-10-10' AND guest_id = 8;
    UPDATE bookings SET total_price = 0 WHERE booking_id = v_bid;
    RAISE NOTICE '3В: обнуление цены (ошибочное действие)';
END $$;

ROLLBACK TO SAVEPOINT after_cancel;

-- Корректно: возвращаем 50%
DO $$
DECLARE v_bid INT;
BEGIN
    SELECT booking_id INTO v_bid
    FROM bookings WHERE check_in = '2025-10-10' AND guest_id = 8;
    UPDATE bookings SET total_price = total_price * 0.5 WHERE booking_id = v_bid;
    RAISE NOTICE '3В: возврат 50%% применён';
END $$;

COMMIT;

SELECT '3В: отмена с частичным возвратом зафиксирована' AS result;
SELECT booking_id, status, total_price FROM bookings WHERE check_in = '2025-10-10' AND guest_id = 8;


-- =====================================================================
-- ПАРАЛЛЕЛЬНЫЕ СЕССИИ И УРОВНИ ИЗОЛЯЦИИ
-- =====================================================================
-- Откройте ДВА терминала psql и выполняйте шаги в указанном порядке.
-- Сценарий: два клиента работают с одним бронированием одновременно.
-- =====================================================================

-- ПОДГОТОВКА (выполнить в любой сессии один раз):
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (5, 9, '2025-12-01', '2025-12-07', 15000.00, 'confirmed')
RETURNING booking_id;
-- Запомните booking_id → ниже обозначается как TARGET_ID

-- Для удобства создадим переменную (замените 999 на реальный ID):
-- \set target_id 999   ← psql-метакоманда


-- ════════════════════════════════════════════════════════════════════
-- УРОВЕНЬ ИЗОЛЯЦИИ 1: READ COMMITTED (по умолчанию)
-- Аномалия: NON-REPEATABLE READ
-- ════════════════════════════════════════════════════════════════════

-- ШАГ 1 — СЕССИЯ 1:
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT total_price FROM bookings WHERE booking_id = 999;
-- Результат: 15000.00

-- ШАГ 2 — СЕССИЯ 2:
BEGIN;
UPDATE bookings SET total_price = 9000.00 WHERE booking_id = 999;
COMMIT;
-- Изменение зафиксировано

-- ШАГ 3 — СЕССИЯ 1:
SELECT total_price FROM bookings WHERE booking_id = 999;
-- АНОМАЛИЯ: результат 9000.00 — значение изменилось внутри транзакции!
-- Это Non-Repeatable Read: READ COMMITTED видит новые коммиты других сессий.
COMMIT;


-- ════════════════════════════════════════════════════════════════════
-- УРОВЕНЬ ИЗОЛЯЦИИ 2: REPEATABLE READ
-- Non-Repeatable Read устранён; снимок фиксируется в начале транзакции
-- ════════════════════════════════════════════════════════════════════

-- Сбрасываем данные:
UPDATE bookings SET total_price = 15000.00 WHERE booking_id = 999;

-- ШАГ 1 — СЕССИЯ 1:
BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT total_price FROM bookings WHERE booking_id = 999;
-- Результат: 15000.00 — снимок зафиксирован

-- ШАГ 2 — СЕССИЯ 2:
BEGIN;
UPDATE bookings SET total_price = 6000.00 WHERE booking_id = 999;
COMMIT;

-- ШАГ 3 — СЕССИЯ 1:
SELECT total_price FROM bookings WHERE booking_id = 999;
-- Результат: 15000.00 — снимок НЕ изменился. Аномалия устранена.
COMMIT;


-- ════════════════════════════════════════════════════════════════════
-- УРОВЕНЬ ИЗОЛЯЦИИ 3: SERIALIZABLE
-- Демонстрация ошибки сериализации (serialization failure)
-- Сценарий: обе сессии читают агрегат и вставляют запись на его основе.
-- ════════════════════════════════════════════════════════════════════

UPDATE bookings SET total_price = 15000.00, status = 'confirmed'
WHERE booking_id = 999;

-- ШАГ 1 — СЕССИЯ 1:
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Читаем текущую сумму подтверждённых бронирований
SELECT SUM(total_price) FROM bookings WHERE status = 'confirmed';
-- Сумма = X

-- ШАГ 2 — СЕССИЯ 2:
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Параллельно добавляем бронирование и меняем статус
UPDATE bookings SET status = 'cancelled' WHERE booking_id = 999;
COMMIT;

-- ШАГ 3 — СЕССИЯ 1 (продолжаем на основе прочитанного агрегата):
INSERT INTO bookings (property_id, guest_id, check_in, check_out, total_price, status)
VALUES (1, 1, '2026-01-01', '2026-01-03', 5000, 'confirmed');
COMMIT;
-- Возможная ошибка:
-- ERROR:  could not serialize access due to read/write dependencies among transactions
-- DETAIL: Processes N1 and N2 deadlocked on serializable transactions.
-- → PostgreSQL обнаружил конфликт сериализации и откатил одну из транзакций.


-- ════════════════════════════════════════════════════════════════════
-- ДЕМОНСТРАЦИЯ БЛОКИРОВКИ (SELECT FOR UPDATE)
-- ════════════════════════════════════════════════════════════════════

UPDATE bookings SET status = 'confirmed', total_price = 15000.00
WHERE booking_id = 999;

-- ШАГ 1 — СЕССИЯ 1:
BEGIN;
-- Блокируем строку — другие транзакции не смогут изменить её до COMMIT
SELECT * FROM bookings WHERE booking_id = 999 FOR UPDATE;
-- Строка заблокирована. Теперь переходим в Сессию 2.

-- ШАГ 2 — СЕССИЯ 2 (выполняется ПОКА Сессия 1 удерживает блокировку):
BEGIN;
SELECT * FROM bookings WHERE booking_id = 999 FOR UPDATE;
-- ← ЗАВИСАЕТ И ЖДЁТ разблокировки Сессией 1

-- ШАГ 3 — СЕССИЯ 1 (завершаем работу с заблокированной строкой):
UPDATE bookings SET status = 'cancelled' WHERE booking_id = 999;
COMMIT;
-- Теперь Сессия 2 продолжает выполнение и видит уже обновлённые данные.

-- ШАГ 4 — СЕССИЯ 2 (разблокировалась):
-- Видит status = 'cancelled' (данные после COMMIT Сессии 1)
UPDATE bookings SET total_price = total_price * 0.5 WHERE booking_id = 999;
COMMIT;

-- Просмотр текущих блокировок (выполнить в третьей сессии во время теста):
SELECT
    pid,
    LEFT(query, 60)  AS query_snippet,
    wait_event_type,
    wait_event,
    state
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY pid;

-- =====================================================================
-- ИТОГОВОЕ СРАВНЕНИЕ УРОВНЕЙ ИЗОЛЯЦИИ:
-- ┌───────────────────┬──────────────┬──────────────────┬─────────┐
-- │ Уровень           │ Dirty Read   │ Non-Repeatable   │ Phantom │
-- ├───────────────────┼──────────────┼──────────────────┼─────────┤
-- │ READ COMMITTED    │ Нет          │ Да               │ Да      │
-- │ REPEATABLE READ   │ Нет          │ Нет              │ Нет*    │
-- │ SERIALIZABLE      │ Нет          │ Нет              │ Нет     │
-- └───────────────────┴──────────────┴──────────────────┴─────────┘
-- * PostgreSQL использует MVCC — Repeatable Read также предотвращает фантомы.
-- =====================================================================
