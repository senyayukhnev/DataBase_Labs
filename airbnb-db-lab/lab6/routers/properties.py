from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from typing import List, Optional
from decimal import Decimal

from database import get_db
from models import Property
from schemas import PropertyCreate, PropertyUpdate, PropertyResponse

router = APIRouter(prefix="/properties", tags=["Properties"])


def _get_or_404(db: Session, property_id: int) -> Property:
    prop = db.get(Property, property_id)
    if not prop:
        raise HTTPException(status_code=404, detail=f"Property {property_id} not found")
    return prop


@router.get("", response_model=List[PropertyResponse])
def list_properties(
    page:      int            = Query(1,   ge=1),
    limit:     int            = Query(10,  ge=1, le=200),
    sort:      str            = Query("property_id"),
    order:     str            = Query("asc", pattern="^(asc|desc)$"),
    city:      Optional[str]  = Query(None, description="Filter by city (exact)"),
    min_price: Optional[Decimal] = Query(None),
    max_price: Optional[Decimal] = Query(None),
    filter:    Optional[str]  = Query(None, description="Filter by title (ILIKE)"),
    db:        Session        = Depends(get_db),
):
    allowed = {"property_id", "title", "city", "price_per_night", "max_guests", "booking_count"}
    if sort not in allowed:
        raise HTTPException(status_code=400, detail=f"sort must be one of {allowed}")

    q = db.query(Property)
    if city:
        q = q.filter(Property.city == city)
    if min_price is not None:
        q = q.filter(Property.price_per_night >= min_price)
    if max_price is not None:
        q = q.filter(Property.price_per_night <= max_price)
    if filter:
        q = q.filter(Property.title.ilike(f"%{filter}%"))

    col = getattr(Property, sort)
    q = q.order_by(col.desc() if order == "desc" else col.asc())
    return q.offset((page - 1) * limit).limit(limit).all()


@router.get("/{property_id}", response_model=PropertyResponse)
def get_property(property_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, property_id)


@router.post("", response_model=PropertyResponse, status_code=201)
def create_property(body: PropertyCreate, db: Session = Depends(get_db)):
    prop = Property(**body.model_dump())
    db.add(prop)
    try:
        db.commit()
        db.refresh(prop)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Foreign key violation: host_id does not exist")
    return prop


@router.put("/{property_id}", response_model=PropertyResponse)
def update_property(property_id: int, body: PropertyUpdate, db: Session = Depends(get_db)):
    prop = _get_or_404(db, property_id)
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(prop, field, value)
    db.commit()
    db.refresh(prop)
    return prop


@router.delete("/{property_id}", status_code=204)
def delete_property(property_id: int, db: Session = Depends(get_db)):
    prop = _get_or_404(db, property_id)
    try:
        db.delete(prop)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Cannot delete property with existing bookings")


@router.get("/{property_id}/avg-rating")
def avg_rating(property_id: int, db: Session = Depends(get_db)):
    """Вызывает функцию get_avg_rating() из лаб. работы №3."""
    _get_or_404(db, property_id)
    result = db.execute(text("SELECT get_avg_rating(:pid)"), {"pid": property_id})
    avg = result.scalar()
    return {"property_id": property_id, "avg_rating": float(avg) if avg is not None else None}
