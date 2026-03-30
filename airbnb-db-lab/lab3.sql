-- ============================================
-- 1. ФУНКЦИЯ: проверка активности пользователя
-- ============================================

-- Функция возвращает TRUE, если у пользователя есть хотя бы одно бронирование
CREATE OR REPLACE FUNCTION is_user_active(u_id INT)
RETURNS BOOLEAN AS $$
DECLARE
    booking_count INT; -- переменная для хранения количества бронирований
BEGIN
    -- считаем количество бронирований пользователя
    SELECT COUNT(*) INTO booking_count
    FROM bookings
    WHERE guest_id = u_id;

    -- если больше 0 → пользователь активен
    RETURN booking_count > 0;
END;
$$ LANGUAGE plpgsql;



-- ============================================
-- 2. ПРОЦЕДУРА: добавление бронирования
-- ============================================

-- Процедура выполняет бизнес-логику:
-- проверяет входные данные и добавляет запись
CREATE OR REPLACE PROCEDURE add_booking(
    u_id INT,
    p_id INT,
    start_d DATE,
    end_d DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверка корректности дат
    IF start_d >= end_d THEN
        RAISE EXCEPTION 'Дата начала должна быть раньше даты окончания';
    END IF;

    -- Проверка существования пользователя
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = u_id) THEN
        RAISE EXCEPTION 'Пользователь не найден';
    END IF;

    -- Проверка существования объекта
    IF NOT EXISTS (SELECT 1 FROM properties WHERE property_id = p_id) THEN
        RAISE EXCEPTION 'Объект не найден';
    END IF;

    -- Основное действие: добавление бронирования
    INSERT INTO bookings(guest_id, property_id, check_in, check_out)
    VALUES (u_id, p_id, start_d, end_d);

-- ============================================
-- ОБРАБОТКА ОШИБОК
-- ============================================
EXCEPTION
    -- ошибка внешнего ключа (например, несуществующий guest_id)
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Ошибка внешнего ключа';

    -- попытка вставить дубликат (если есть UNIQUE)
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Дублирование записи';
END;
$$;



-- ============================================
-- 3. ФУНКЦИЯ: средний рейтинг объекта
-- ============================================

-- Функция возвращает средний рейтинг конкретного жилья
CREATE OR REPLACE FUNCTION get_avg_rating(p_id INT)
RETURNS DECIMAL(3,2) AS $$
DECLARE
    avg_r DECIMAL(3,2); -- переменная для результата
BEGIN
    -- считаем средний рейтинг через JOIN
    SELECT AVG(r.rating)
    INTO avg_r
    FROM reviews r
    JOIN bookings b ON r.booking_id = b.booking_id
    WHERE b.property_id = p_id;

    RETURN avg_r;
END;
$$ LANGUAGE plpgsql;



-- ============================================
-- 4. ТРИГГЕР: проверка рейтинга
-- ============================================

-- Функция-триггер, которая НЕ даёт вставить некорректный рейтинг
CREATE OR REPLACE FUNCTION check_rating()
RETURNS TRIGGER AS $$
BEGIN
    -- проверка диапазона рейтинга
    IF NEW.rating < 1 OR NEW.rating > 5 THEN
        RAISE EXCEPTION 'Рейтинг должен быть от 1 до 5';
    END IF;

    RETURN NEW; -- обязательно вернуть строку
END;
$$ LANGUAGE plpgsql;

-- Удаляем старый триггер, если есть
DROP TRIGGER IF EXISTS rating_check_trigger ON reviews;

-- Сам триггер (срабатывает ДО вставки или обновления)
CREATE TRIGGER rating_check_trigger
BEFORE INSERT OR UPDATE ON reviews
FOR EACH ROW
EXECUTE FUNCTION check_rating();



-- ============================================
-- 5. ТРИГГЕР: счётчик бронирований
-- ============================================

-- Добавляем колонку для хранения статистики
ALTER TABLE properties
ADD COLUMN IF NOT EXISTS booking_count INT DEFAULT 0;

-- Функция-триггер: увеличивает счётчик
CREATE OR REPLACE FUNCTION update_booking_count()
RETURNS TRIGGER AS $$
BEGIN
    -- увеличиваем счётчик бронирований у объекта
    UPDATE properties
    SET booking_count = booking_count + 1
    WHERE property_id = NEW.property_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS booking_count_trigger ON bookings;

-- Триггер (срабатывает ПОСЛЕ вставки)
CREATE TRIGGER booking_count_trigger
AFTER INSERT ON bookings
FOR EACH ROW
EXECUTE FUNCTION update_booking_count();



-- ============================================
-- 6. ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ (для защиты)
-- ============================================

-- Проверка функции (активен ли пользователь)
SELECT is_user_active(1) AS is_active;

-- Добавление бронирования через процедуру
CALL add_booking(1, 1, '2025-06-01', '2025-06-10');

-- Проверим, что добавилось
SELECT * FROM bookings ORDER BY booking_id DESC LIMIT 1;

-- Получение среднего рейтинга
SELECT get_avg_rating(1) AS avg_rating;

-- Проверка триггера (должна быть ошибка)
INSERT INTO reviews(booking_id, rating)
VALUES (1, 10);


