CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE properties (
    property_id SERIAL PRIMARY KEY,
    host_id INT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    city VARCHAR(100),
    address VARCHAR(200),
    price_per_night DECIMAL(10,2) NOT NULL,
    max_guests INT,

    FOREIGN KEY (host_id) REFERENCES users(user_id)
);

CREATE TABLE bookings (
    booking_id SERIAL PRIMARY KEY,
    property_id INT NOT NULL,
    guest_id INT NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    total_price DECIMAL(10,2),
    status VARCHAR(50),

    FOREIGN KEY (property_id) REFERENCES properties(property_id),
    FOREIGN KEY (guest_id) REFERENCES users(user_id)
);

CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    booking_id INT UNIQUE,
    rating INT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
);

