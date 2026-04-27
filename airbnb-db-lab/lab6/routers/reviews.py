from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from typing import List, Optional

from database import get_db
from models import Review
from schemas import ReviewCreate, ReviewUpdate, ReviewResponse

router = APIRouter(prefix="/reviews", tags=["Reviews"])


def _get_or_404(db: Session, review_id: int) -> Review:
    r = db.get(Review, review_id)
    if not r:
        raise HTTPException(status_code=404, detail=f"Review {review_id} not found")
    return r


@router.get("", response_model=List[ReviewResponse])
def list_reviews(
    page:       int           = Query(1,  ge=1),
    limit:      int           = Query(10, ge=1, le=200),
    sort:       str           = Query("review_id"),
    order:      str           = Query("asc", pattern="^(asc|desc)$"),
    min_rating: Optional[int] = Query(None, ge=1, le=5),
    max_rating: Optional[int] = Query(None, ge=1, le=5),
    filter:     Optional[str] = Query(None, description="Filter by comment (ILIKE)"),
    db:         Session       = Depends(get_db),
):
    allowed = {"review_id", "rating", "created_at"}
    if sort not in allowed:
        raise HTTPException(status_code=400, detail=f"sort must be one of {allowed}")

    q = db.query(Review)
    if min_rating is not None:
        q = q.filter(Review.rating >= min_rating)
    if max_rating is not None:
        q = q.filter(Review.rating <= max_rating)
    if filter:
        q = q.filter(Review.comment.ilike(f"%{filter}%"))

    col = getattr(Review, sort)
    q = q.order_by(col.desc() if order == "desc" else col.asc())
    return q.offset((page - 1) * limit).limit(limit).all()


@router.get("/{review_id}", response_model=ReviewResponse)
def get_review(review_id: int, db: Session = Depends(get_db)):
    return _get_or_404(db, review_id)


@router.post("", response_model=ReviewResponse, status_code=201)
def create_review(body: ReviewCreate, db: Session = Depends(get_db)):
    review = Review(**body.model_dump())
    db.add(review)
    try:
        db.commit()
        db.refresh(review)
    except IntegrityError as e:
        db.rollback()
        msg = str(e.orig)
        if "unique" in msg.lower():
            raise HTTPException(status_code=409, detail="A review for this booking already exists")
        if "foreign" in msg.lower():
            raise HTTPException(status_code=409, detail="booking_id does not exist")
        raise HTTPException(status_code=409, detail="Database constraint violation")
    return review


@router.put("/{review_id}", response_model=ReviewResponse)
def update_review(review_id: int, body: ReviewUpdate, db: Session = Depends(get_db)):
    review = _get_or_404(db, review_id)
    for field, value in body.model_dump(exclude_none=True).items():
        setattr(review, field, value)
    try:
        db.commit()
        db.refresh(review)
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    return review


@router.delete("/{review_id}", status_code=204)
def delete_review(review_id: int, db: Session = Depends(get_db)):
    review = _get_or_404(db, review_id)
    db.delete(review)
    db.commit()
