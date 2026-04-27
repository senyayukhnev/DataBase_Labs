from sqlalchemy import Column, Integer, String, Text, DateTime, Date, Numeric, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base


class User(Base):
    __tablename__ = "users"

    user_id    = Column(Integer, primary_key=True, index=True)
    name       = Column(String(100), nullable=False)
    email      = Column(String(150), unique=True, nullable=False)
    phone      = Column(String(20))
    created_at = Column(DateTime, server_default=func.now())

    properties = relationship("Property", back_populates="host", lazy="select")
    bookings   = relationship("Booking",  back_populates="guest", lazy="select")


class Property(Base):
    __tablename__ = "properties"

    property_id     = Column(Integer, primary_key=True, index=True)
    host_id         = Column(Integer, ForeignKey("users.user_id"), nullable=False)
    title           = Column(String(200), nullable=False)
    description     = Column(Text)
    city            = Column(String(100))
    address         = Column(String(200))
    price_per_night = Column(Numeric(10, 2), nullable=False)
    max_guests      = Column(Integer)
    booking_count   = Column(Integer, default=0)

    host     = relationship("User",    back_populates="properties", lazy="select")
    bookings = relationship("Booking", back_populates="property",   lazy="select")


class Booking(Base):
    __tablename__ = "bookings"

    booking_id  = Column(Integer, primary_key=True, index=True)
    property_id = Column(Integer, ForeignKey("properties.property_id"), nullable=False)
    guest_id    = Column(Integer, ForeignKey("users.user_id"),          nullable=False)
    check_in    = Column(Date, nullable=False)
    check_out   = Column(Date, nullable=False)
    total_price = Column(Numeric(10, 2))
    status      = Column(String(50), default="pending")

    property = relationship("Property", back_populates="bookings", lazy="select")
    guest    = relationship("User",     back_populates="bookings", lazy="select")
    review   = relationship("Review",   back_populates="booking",  lazy="select", uselist=False)


class Review(Base):
    __tablename__ = "reviews"

    review_id  = Column(Integer, primary_key=True, index=True)
    booking_id = Column(Integer, ForeignKey("bookings.booking_id"), unique=True)
    rating     = Column(Integer)
    comment    = Column(Text)
    created_at = Column(DateTime, server_default=func.now())

    booking = relationship("Booking", back_populates="review", lazy="select")
