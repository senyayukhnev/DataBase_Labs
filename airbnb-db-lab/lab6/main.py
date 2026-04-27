from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError

from database import engine, Base
from routers import users, properties, bookings, reviews, reports

# Создаём таблицы если нужно (можно убрать если схема уже создана вручную)
# Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Airbnb-like API",
    description=(
        "RESTful API для Airbnb-подобного сервиса. "
        "Лабораторная работа №6 — вариант 2."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)

# ─── Глобальная обработка ошибок БД ──────────────────────────────────────────

@app.exception_handler(SQLAlchemyError)
async def db_exception_handler(request: Request, exc: SQLAlchemyError):
    return JSONResponse(
        status_code=500,
        content={"detail": "Database error", "error": str(exc)},
    )


# ─── Роутеры ─────────────────────────────────────────────────────────────────

app.include_router(users.router)
app.include_router(properties.router)
app.include_router(bookings.router)
app.include_router(reviews.router)
app.include_router(reports.router)


@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "docs": "/docs"}


# ─── Запуск ──────────────────────────────────────────────────────────────────
# uvicorn main:app --reload --host 0.0.0.0 --port 8000
