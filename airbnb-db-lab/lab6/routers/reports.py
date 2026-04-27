from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List

from database import get_db

router = APIRouter(tags=["Views & Reports"])


# ─── Views из лаб. работы №2 ──────────────────────────────────────────────────

@router.get("/views/property-hosts")
def view_property_hosts(
    page:  int = Query(1,  ge=1),
    limit: int = Query(10, ge=1, le=200),
    db:    Session = Depends(get_db),
):
    """Читает представление property_hosts (объект + владелец)."""
    offset = (page - 1) * limit
    rows = db.execute(
        text("SELECT * FROM property_hosts ORDER BY property_id LIMIT :lim OFFSET :off"),
        {"lim": limit, "off": offset},
    ).mappings().all()
    return list(rows)


@router.get("/views/property-revenue")
def view_property_revenue(
    page:  int = Query(1,  ge=1),
    limit: int = Query(10, ge=1, le=200),
    db:    Session = Depends(get_db),
):
    """Читает представление property_revenue (выручка по объектам)."""
    offset = (page - 1) * limit
    rows = db.execute(
        text("SELECT * FROM property_revenue ORDER BY total_income DESC NULLS LAST LIMIT :lim OFFSET :off"),
        {"lim": limit, "off": offset},
    ).mappings().all()
    return list(rows)


@router.get("/views/property-ratings")
def view_property_ratings(
    page:  int = Query(1,  ge=1),
    limit: int = Query(10, ge=1, le=200),
    db:    Session = Depends(get_db),
):
    """Читает представление property_ratings (средний рейтинг по объектам)."""
    offset = (page - 1) * limit
    rows = db.execute(
        text("SELECT * FROM property_ratings ORDER BY avg_rating DESC NULLS LAST LIMIT :lim OFFSET :off"),
        {"lim": limit, "off": offset},
    ).mappings().all()
    return list(rows)


# ─── Агрегации и отчёты ───────────────────────────────────────────────────────

@router.get("/reports/top-properties")
def top_properties(
    limit: int = Query(10, ge=1, le=100),
    db:    Session = Depends(get_db),
):
    """Топ объектов по количеству бронирований."""
    rows = db.execute(
        text("""
            SELECT
                p.property_id,
                p.title,
                p.city,
                p.price_per_night,
                p.booking_count,
                COALESCE(AVG(r.rating), 0)::numeric(3,2) AS avg_rating
            FROM properties p
            LEFT JOIN bookings b ON b.property_id = p.property_id
            LEFT JOIN reviews  r ON r.booking_id  = b.booking_id
            GROUP BY p.property_id, p.title, p.city, p.price_per_night, p.booking_count
            ORDER BY p.booking_count DESC
            LIMIT :lim
        """),
        {"lim": limit},
    ).mappings().all()
    return list(rows)


@router.get("/reports/revenue-by-city")
def revenue_by_city(db: Session = Depends(get_db)):
    """Суммарная выручка и количество бронирований по городам."""
    rows = db.execute(
        text("""
            SELECT
                p.city,
                COUNT(b.booking_id)    AS total_bookings,
                SUM(b.total_price)     AS total_revenue,
                AVG(b.total_price)::numeric(12,2) AS avg_booking_price
            FROM properties p
            JOIN bookings b ON b.property_id = p.property_id
            WHERE b.status IN ('confirmed', 'completed')
            GROUP BY p.city
            ORDER BY total_revenue DESC NULLS LAST
        """)
    ).mappings().all()
    return list(rows)


@router.get("/reports/top-guests")
def top_guests(
    limit: int = Query(10, ge=1, le=100),
    db:    Session = Depends(get_db),
):
    """Топ гостей по количеству бронирований и суммарным расходам."""
    rows = db.execute(
        text("""
            SELECT
                u.user_id,
                u.name,
                u.email,
                COUNT(b.booking_id)          AS total_bookings,
                SUM(b.total_price)::numeric  AS total_spent
            FROM users u
            JOIN bookings b ON b.guest_id = u.user_id
            WHERE b.status IN ('confirmed', 'completed')
            GROUP BY u.user_id, u.name, u.email
            ORDER BY total_bookings DESC
            LIMIT :lim
        """),
        {"lim": limit},
    ).mappings().all()
    return list(rows)


@router.get("/reports/booking-stats")
def booking_stats(db: Session = Depends(get_db)):
    """Общая статистика по бронированиям."""
    row = db.execute(
        text("""
            SELECT
                COUNT(*)                                        AS total_bookings,
                COUNT(*) FILTER (WHERE status = 'confirmed')   AS confirmed,
                COUNT(*) FILTER (WHERE status = 'completed')   AS completed,
                COUNT(*) FILTER (WHERE status = 'cancelled')   AS cancelled,
                COUNT(*) FILTER (WHERE status = 'pending')     AS pending,
                AVG(total_price)::numeric(12,2)                AS avg_price,
                SUM(total_price)                               AS total_revenue
            FROM bookings
        """)
    ).mappings().one()
    return dict(row)
