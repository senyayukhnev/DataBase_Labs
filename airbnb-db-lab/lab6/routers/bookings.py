from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from typing import List, Optional
from datetime import date

from database import get_db
from models import Booking
from schemas import BookingCreate, BookingUpdate, BookingResponse, AddBookingRequest

router = APIRouter(prefix="/bookings", tags=["Bookings"])

VALID_STATUSES = {"pending", "confirmed", "cancelled", "completed"}


def _get_or_404(db: Session, booking_id: int) -> Booking:
    b = db.get(Booking, booking_id)
    if not b:
        raise HTTPException(status_code=404, detail=f"Booking {booking_id} not found")
    return b


@router.get("", response_model=List[BookingResponse])
def list_bookings(
    page:        int           = Query(1,   ge=1),
    limit:       int           = Query(10,  ge=1, le=200),
    sort:        str           = Query("booking_id"),
    order:       str           = Query("asc", pattern="^(asc|desc)$"),
    status:      Optional[str] = Query(None),
    guest_id:    Optional[int] = Query(None),
    property_id: Optional[int] = Query(None),
    check_in_from: Optional[date] = Query(None),
    check_in_to:   Optional[date] = Query(None),
    db:          Session       = Depends(get_db),
):
    allowed = {"booking_id", "check_in", "check_out", "total_price", "status"}
    if sort not in allowed:
        raise HTTPException(status_code=400, detail=f"sort must be one of {allowed}")
    if status and status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"status must be one of {VALID_STATUSES}")

    q = db.query(Booking)
    if status:
        q = q.filter(Booking.status == status)
    if guest_id:
        q = q.filter(Booking.guest_id == guest_id)
    if property_id:
        q = q.filter(Booking.property_id == property_id)
    if check_in_from:
        q = q.filter(Booking.check_in >= check_in_from)
    if check_in_to:
        q = q.filter(Booking.check_in <= check_in_to)

    col = getattr(Booking, sort)
    q = q.order_by(col.desc() if order == "desc" else col.asc())
    return q.offset((page - 1) * limit).limit(limit).all()


@router.get("/{booking_id}", response_model=BookingResponse)
def get_booking(booking_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, booking_id)


@router.post("", response_model=BookingResponse, status_code=201)
def create_booking(body: BookingCreate, db: Session = Depends(get_db)):
    booking = Booking(**body.model_dump())
    db.add(booking)
    try:
        db.commit()
        db.refresh(booking)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Foreign key violation: property or guest not found")
    return booking


@router.post("/add", response_model=BookingResponse, status_code=201)
def add_booking_procedure(body: AddBookingRequest, db: Session = Depends(get_db)):
    """Вызывает хранимую процедуру add_booking() из лаб. работы №3."""
    try:
        db.execute(
            text("CALL add_booking(:uid, :pid, :start_d, :end_d)"),
            {
                "uid":     body.user_id,
                "pid":     body.property_id,
                "start_d": body.check_in,
                "end_d":   body.check_out,
            },
        )
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    booking = (
        db.query(Booking)
        .filter(
            Booking.guest_id    == body.user_id,
            Booking.property_id == body.property_id,
            Booking.check_in    == body.check_in,
        )
        .order_by(Booking.booking_id.desc())
        .first()
    )
    return booking


@router.put("/{booking_id}", response_model=BookingResponse)
def update_booking(booking_id: int, body: BookingUpdate, db: Session = Depends(get_db)):
    booking = _get_or_404(db, booking_id)
    if body.status and body.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=f"status must be one of {VALID_STATUSES}")
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(booking, field, value)
    db.commit()
    db.refresh(booking)
    return booking


@router.delete("/{booking_id}", status_code=204)
def delete_booking(booking_id: int, db: Session = Depends(get_db)):
    booking = _get_or_404(db, booking_id)
    try:
        db.delete(booking)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Cannot delete booking with an existing review")
