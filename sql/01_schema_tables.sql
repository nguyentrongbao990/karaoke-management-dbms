-- 01_schema_tables.sql
-- Database: karaoke_management
-- DBMS: PostgreSQL

-- 1. ROOM TYPES
CREATE TABLE room_types (
    room_type_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_type_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    max_capacity INT NOT NULL CHECK (max_capacity > 0),
    hourly_rate NUMERIC(12,2) NOT NULL CHECK (hourly_rate >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- 2. ROOMS
CREATE TABLE rooms (
    room_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_code VARCHAR(20) NOT NULL UNIQUE,
    room_name VARCHAR(100),
    room_type_id BIGINT NOT NULL REFERENCES room_types(room_type_id),
    floor_no SMALLINT,
    actual_capacity INT NOT NULL CHECK (actual_capacity > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'available'
        CHECK (status IN ('available', 'reserved', 'occupied', 'maintenance', 'inactive')),
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- 3. FACILITIES

CREATE TABLE facilities (
    facility_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    facility_name VARCHAR(100) NOT NULL UNIQUE,
    default_unit VARCHAR(20) NOT NULL DEFAULT 'cái',
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- 4. ROOM FACILITIES

CREATE TABLE room_facilities (
    room_facility_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id BIGINT NOT NULL REFERENCES rooms(room_id),
    facility_id BIGINT NOT NULL REFERENCES facilities(facility_id),
    quantity INT NOT NULL CHECK (quantity > 0),
    condition_status VARCHAR(20) NOT NULL DEFAULT 'good'
        CHECK (condition_status IN ('good', 'damaged', 'repairing', 'missing')),
    issue_note TEXT,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (room_id, facility_id)
);

-- 5. CUSTOMERS
CREATE TABLE customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(15) NOT NULL UNIQUE,
    email VARCHAR(100),
    gender VARCHAR(10)
        CHECK (gender IN ('male', 'female', 'other')),
    date_of_birth DATE,
    address TEXT,
    customer_type VARCHAR(20) NOT NULL DEFAULT 'regular'
        CHECK (customer_type IN ('regular', 'loyal', 'vip')),
    note TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- 6. ROLES
CREATE TABLE roles (
    role_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- 7. EMPLOYEES
CREATE TABLE employees (
    employee_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(15) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    role_id BIGINT NOT NULL REFERENCES roles(role_id),
    hire_date DATE NOT NULL,
    employment_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (employment_status IN ('active', 'inactive', 'resigned')),
    note TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- 8. ACCOUNTS
CREATE TABLE accounts (
    account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id BIGINT NOT NULL UNIQUE REFERENCES employees(employee_id),
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    account_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (account_status IN ('active', 'locked', 'disabled')),
    last_login_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);


-- 9. MENU CATEGORIES
CREATE TABLE menu_categories (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- 10. MENU ITEMS
CREATE TABLE menu_items (
    item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_name VARCHAR(150) NOT NULL,
    category_id BIGINT NOT NULL REFERENCES menu_categories(category_id),
    unit VARCHAR(20) NOT NULL DEFAULT 'phần',
    sale_price NUMERIC(12,2) NOT NULL CHECK (sale_price >= 0),
    stock_quantity INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP
);

-- 11. BOOKINGS
CREATE TABLE bookings (
    booking_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_code VARCHAR(30) NOT NULL UNIQUE,
    customer_id BIGINT NOT NULL REFERENCES customers(customer_id),
    room_id BIGINT NOT NULL REFERENCES rooms(room_id),
    created_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
    booking_created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expected_start_time TIMESTAMP NOT NULL,
    expected_end_time TIMESTAMP NOT NULL,
    guest_count INT NOT NULL CHECK (guest_count > 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'confirmed', 'checked_in', 'cancelled', 'completed')),
    note TEXT,
    CHECK (expected_end_time > expected_start_time)
);

-- 12. ROOM SESSIONS
CREATE TABLE room_sessions (
    session_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id BIGINT NOT NULL REFERENCES bookings(booking_id),
    room_id BIGINT NOT NULL REFERENCES rooms(room_id),
    checked_in_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
    checked_out_by_employee_id BIGINT REFERENCES employees(employee_id),
    actual_start_time TIMESTAMP NOT NULL,
    actual_end_time TIMESTAMP,
    guest_count_actual INT CHECK (guest_count_actual > 0),
    session_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (session_status IN ('active', 'transferred', 'completed', 'cancelled')),
    note TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (actual_end_time IS NULL OR actual_end_time > actual_start_time)
);

-- 13. ROOM TRANSFERS
CREATE TABLE room_transfers (
    transfer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id BIGINT NOT NULL REFERENCES bookings(booking_id),
    from_session_id BIGINT NOT NULL UNIQUE REFERENCES room_sessions(session_id),
    to_session_id BIGINT NOT NULL UNIQUE REFERENCES room_sessions(session_id),
    transfer_time TIMESTAMP NOT NULL,
    reason TEXT,
    approved_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
    CHECK (from_session_id <> to_session_id)
);

-- 14. SERVICE ORDERS
CREATE TABLE service_orders (
    service_order_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id BIGINT NOT NULL REFERENCES room_sessions(session_id),
    created_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
    ordered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    order_status VARCHAR(20) NOT NULL DEFAULT 'confirmed'
        CHECK (order_status IN ('draft', 'confirmed', 'cancelled')),
    note TEXT
);

-- 15. SERVICE ORDER ITEMS
CREATE TABLE service_order_items (
    service_order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_order_id BIGINT NOT NULL REFERENCES service_orders(service_order_id),
    item_id BIGINT NOT NULL REFERENCES menu_items(item_id),
    quantity INT NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(12,2) NOT NULL CHECK (line_total >= 0),
    note TEXT,
    UNIQUE (service_order_id, item_id)
);

-- 16. INVOICES
CREATE TABLE invoices (
    invoice_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number VARCHAR(30) NOT NULL UNIQUE,
    booking_id BIGINT NOT NULL UNIQUE REFERENCES bookings(booking_id),
    created_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
    issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    room_charge NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (room_charge >= 0),
    service_charge NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (service_charge >= 0),
    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    invoice_status VARCHAR(20) NOT NULL DEFAULT 'unpaid'
        CHECK (invoice_status IN ('draft', 'unpaid', 'paid', 'cancelled')),
    note TEXT
);

-- 17. PAYMENTS
CREATE TABLE payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id BIGINT NOT NULL REFERENCES invoices(invoice_id),
    amount_paid NUMERIC(12,2) NOT NULL CHECK (amount_paid >= 0),
    payment_method VARCHAR(20) NOT NULL
        CHECK (payment_method IN ('cash', 'bank_transfer', 'e_wallet')),
    paid_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_status VARCHAR(20) NOT NULL DEFAULT 'successful'
        CHECK (payment_status IN ('pending', 'successful', 'failed', 'refunded')),
    transaction_reference VARCHAR(100),
    received_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id),
    note TEXT
);

-- 18. SURCHARGE TYPES
CREATE TABLE surcharge_types (
    surcharge_type_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    surcharge_name VARCHAR(100) NOT NULL UNIQUE,
    default_amount NUMERIC(12,2) CHECK (default_amount >= 0),
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);


-- 19. INVOICE SURCHARGES

CREATE TABLE invoice_surcharges (
    invoice_surcharge_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id BIGINT NOT NULL REFERENCES invoices(invoice_id),
    surcharge_type_id BIGINT NOT NULL REFERENCES surcharge_types(surcharge_type_id),
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_amount NUMERIC(12,2) NOT NULL CHECK (unit_amount >= 0),
    line_total NUMERIC(12,2) NOT NULL CHECK (line_total >= 0),
    note TEXT,
    recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    recorded_by_employee_id BIGINT NOT NULL REFERENCES employees(employee_id)
);