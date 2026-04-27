# Airbnb Rental Service Database

Лабораторные работы по дисциплине «Базы данных» — проектирование и работа с реляционной БД на основе Airbnb-подобного сервиса.

## Структура проекта

```
airbnb-db-lab/
├── schema.sql        # DDL: создание таблиц
├── data.sql          # DML: тестовые данные
├── queries.sql       # Лаб. 2 — базовые запросы
├── views.sql         # Лаб. 3 — представления и процедуры
├── lab3.sql          # Лаб. 3 — дополнительные задачи
├── lab4.sql          # Лаб. 4 — индексы и EXPLAIN ANALYZE
├── lab5.sql          # Лаб. 5 — уровни изоляции транзакций
├── lab4_report.docx  # Отчёт по лаб. 4
├── er_diagram/       # ER-диаграмма
└── lab6/             # Лаб. 6 — REST API (FastAPI)
    ├── main.py
    ├── database.py
    ├── models.py
    ├── schemas.py
    ├── requirements.txt
    └── routers/
        ├── users.py
        ├── properties.py
        ├── bookings.py
        ├── reviews.py
        └── reports.py
```

## Таблицы базы данных

| Таблица | Описание |
|---------|----------|
| `users` | Пользователи (арендаторы и арендодатели) |
| `properties` | Объекты недвижимости |
| `bookings` | Бронирования |
| `reviews` | Отзывы |

## ER-диаграмма

![ER Diagram](er_diagram/er_diagram.png)

---

## Предварительные требования

- PostgreSQL 14+
- Python 3.10+
- pgAdmin 4 (опционально, для работы с БД через GUI)

---

## 1. Настройка базы данных

### Создать БД и заполнить данными

Выполнить в pgAdmin или `psql`:

```sql
-- 1. Создать базу данных
CREATE DATABASE airbnb_service;

-- 2. Подключиться к ней (\c airbnb_service в psql)

-- 3. Создать схему
\i schema.sql

-- 4. Загрузить тестовые данные
\i data.sql
```

Или через psql одной командой:

```bash
psql -U postgres -c "CREATE DATABASE airbnb_service;"
psql -U postgres -d airbnb_service -f schema.sql
psql -U postgres -d airbnb_service -f data.sql
```

---

## 2. Лабораторные работы 2–5 (SQL)

Каждый SQL-файл открыть в pgAdmin (Query Tool → Open File) или выполнить через psql.

| Лаб. | Файл | Описание |
|------|------|----------|
| 2 | `queries.sql` | Выборки, агрегации, JOIN |
| 3 | `views.sql`, `lab3.sql` | Представления, хранимые процедуры, триггеры |
| 4 | `lab4.sql` | Индексы, EXPLAIN ANALYZE |
| 5 | `lab5.sql` | Уровни изоляции транзакций |

### Лаб. 5 — тестирование изоляции транзакций

Для корректного воспроизведения сценариев (например, REPEATABLE READ) нужно **открыть два отдельных окна Query Tool** в pgAdmin:

1. В pgAdmin: ПКМ на базе → **Query Tool** (первая сессия)
2. Ещё раз: ПКМ на базе → **Query Tool** (вторая сессия)
3. Выполнять шаги поочерёдно в разных окнах, как указано в скрипте

---

## 3. Лаб. 6 — REST API (FastAPI)

### Установка зависимостей

```bash
cd airbnb-db-lab/lab6
python -m venv .venv

# Windows (PowerShell)
.venv\Scripts\Activate.ps1

# Linux / macOS
source .venv/bin/activate

pip install -r requirements.txt
```

### Запуск сервера

**PowerShell:**

```powershell
cd airbnb-db-lab\lab6
.venv\Scripts\Activate.ps1

$env:DATABASE_URL = "postgresql://postgres:YOUR_PASSWORD@localhost:5432/airbnb_service"

python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

**bash / Linux / macOS:**

```bash
cd airbnb-db-lab/lab6
source .venv/bin/activate

export DATABASE_URL="postgresql://postgres:YOUR_PASSWORD@localhost:5432/airbnb_service"

uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

> Замените `YOUR_PASSWORD` на пароль вашего пользователя `postgres`.

### Документация API

После запуска открыть в браузере:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **Healthcheck**: http://localhost:8000/

### Доступные эндпоинты

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/users` | Список пользователей |
| POST | `/users` | Создать пользователя |
| GET | `/users/{id}` | Пользователь по ID |
| GET | `/properties` | Список объектов недвижимости |
| POST | `/properties` | Создать объект |
| GET | `/properties/{id}` | Объект по ID |
| GET | `/bookings` | Список бронирований |
| POST | `/bookings` | Создать бронирование |
| GET | `/bookings/{id}` | Бронирование по ID |
| GET | `/reviews` | Список отзывов |
| POST | `/reviews` | Создать отзыв |
| GET | `/reports/...` | Отчёты и аналитика |

---

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `DATABASE_URL` | `postgresql://postgres:postgres@localhost:5432/airbnb_service` | Строка подключения к БД |
