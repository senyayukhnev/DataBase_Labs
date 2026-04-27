from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from typing import List, Optional

from database import get_db
from models import User
from schemas import UserCreate, UserUpdate, UserResponse

router = APIRouter(prefix="/users", tags=["Users"])


def _get_or_404(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found")
    return user


@router.get("", response_model=List[UserResponse])
def list_users(
    page:   int            = Query(1,    ge=1),
    limit:  int            = Query(10,   ge=1, le=200),
    sort:   str            = Query("user_id"),
    order:  str            = Query("asc", pattern="^(asc|desc)$"),
    filter: Optional[str]  = Query(None, description="Filter by name (ILIKE)"),
    db:     Session        = Depends(get_db),
):
    allowed = {"user_id", "name", "email", "created_at"}
    if sort not in allowed:
        raise HTTPException(status_code=400, detail=f"sort must be one of {allowed}")

    q = db.query(User)
    if filter:
        q = q.filter(User.name.ilike(f"%{filter}%"))

    col = getattr(User, sort)
    q = q.order_by(col.desc() if order == "desc" else col.asc())
    return q.offset((page - 1) * limit).limit(limit).all()


@router.get("/{user_id}", response_model=UserResponse)
def get_user(user_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, user_id)


@router.post("", response_model=UserResponse, status_code=201)
def create_user(body: UserCreate, db: Session = Depends(get_db)):
    user = User(**body.model_dump())
    db.add(user)
    try:
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Email already exists")
    return user


@router.put("/{user_id}", response_model=UserResponse)
def update_user(user_id: int, body: UserUpdate, db: Session = Depends(get_db)):
    user = _get_or_404(db, user_id)
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(user, field, value)
    try:
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Email already exists")
    return user


@router.delete("/{user_id}", status_code=204)
def delete_user(user_id: int, db: Session = Depends(get_db)):
    user = _get_or_404(db, user_id)
    try:
        db.delete(user)
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Cannot delete user with existing bookings/properties")


@router.get("/{user_id}/is-active")
def is_user_active(user_id: int, db: Session = Depends(get_db)):
    """Вызывает функцию is_user_active() из лаб. работы №3."""
    _get_or_404(db, user_id)
    result = db.execute(text("SELECT is_user_active(:uid)"), {"uid": user_id})
    active = result.scalar()
    return {"user_id": user_id, "is_active": active}
