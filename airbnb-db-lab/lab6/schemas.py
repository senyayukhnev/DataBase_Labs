from pydantic import BaseModel, field_validator, model_validator
from typing import Optional
from datetime import date, datetime
from decimal import Decimal


# ─── Users ────────────────────────────────────────────────────────────────────

class UserCreate(BaseModel):
    name:  str
    email: str
    phone: Optional[str] = None


class UserUpdate(BaseModel):
    name:  Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None


class UserResponse(BaseModel):
    user_id:    int
    name:       str
    email:      str
    phone:      Optional[str]
    created_at: Optional[datetime]

    model_config = {"from_attributes": True}


# ─── Properties ───────────────────────────────────────────────────────────────

class PropertyCreate(BaseModel):
    host_id:         int
    title:           str
    description:     Optional[str]   = None
    city:            Optional[str]   = None
    address:         Optional[str]   = None
    price_per_night: Decimal
    max_guests:      Optional[int]   = None

    @field_validator("price_per_night")
    @classmethod
    def price_positive(cls, v):
        if v <= 0:
            raise ValueError("price_per_night must be positive")
        return v


class PropertyUpdate(BaseModel):
    title:           Optional[str]     = None
    description:     Optional[str]     = None
    city:            Optional[str]     = None
    address:         Optional[str]     = None
    price_per_night: Optional[Decimal] = None
    max_guests:      Optional[int]     = None


class PropertyResponse(BaseModel):
    property_id:     int
    host_id:         int
    title:           str
    description:     Optional[str]
    city:            Optional[str]
    address:         Optional[str]
    price_per_night: Decimal
    max_guests:      Optional[int]
    booking_count:   Optional[int]

    model_config = {"from_attributes": True}


# ─── Bookings ─────────────────────────────────────────────────────────────────

class BookingCreate(BaseModel):
    property_id: int
    guest_id:    int
    check_in:    date
    check_out:   date
    total_price: Optional[Decimal] = None
    status:      Optional[str]     = "pending"

    @model_validator(mode="after")
    def dates_valid(self):
        if self.check_out <= self.check_in:
            raise ValueError("check_out must be after check_in")
        return self


class BookingUpdate(BaseModel):
    status:      Optional[str]     = None
    total_price: Optional[Decimal] = None


class BookingResponse(BaseModel):
    booking_id:  int
    property_id: int
    guest_id:    int
    check_in:    date
    check_out:   date
    total_price: Optional[Decimal]
    status:      Optional[str]

    model_config = {"from_attributes": True}


# ─── Reviews ──────────────────────────────────────────────────────────────────

class ReviewCreate(BaseModel):
    booking_id: int
    rating:     int
    comment:    Optional[str] = None

    @field_validator("rating")
    @classmethod
    def rating_range(cls, v):
        if not 1 <= v <= 5:
            raise ValueError("rating must be between 1 and 5")
        return v


class ReviewUpdate(BaseModel):
    rating:  Optional[int] = None
    comment: Optional[str] = None

    @field_validator("rating")
    @classmethod
    def rating_range(cls, v):
        if v is not None and not 1 <= v <= 5:
            raise ValueError("rating must be between 1 and 5")
        return v


class ReviewResponse(BaseModel):
    review_id:  int
    booking_id: int
    rating:     int
    comment:    Optional[str]
    created_at: Optional[datetime]

    model_config = {"from_attributes": True}


# ─── Stored procedure input ───────────────────────────────────────────────────

class AddBookingRequest(BaseModel):
    user_id:     int
    property_id: int
    check_in:    date
    check_out:   date

    @model_validator(mode="after")
    def dates_valid(self):
        if self.check_out <= self.check_in:
            raise ValueError("check_out must be after check_in")
        return self


# ─── Pagination helper ────────────────────────────────────────────────────────

class PaginationParams(BaseModel):
    page:  int = 1
    limit: int = 10

    @field_validator("page")
    @classmethod
    def page_ge1(cls, v):
        if v < 1:
            raise ValueError("page must be >= 1")
        return v

    @field_validator("limit")
    @classmethod
    def limit_range(cls, v):
        if not 1 <= v <= 200:
            raise ValueError("limit must be between 1 and 200")
        return v
