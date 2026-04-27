-- 02_indexes.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tối ưu hóa tốc độ truy vấn cho các bảng dữ liệu

-- ============================================================================
-- I. NHÓM QUẢN LÝ PHÒNG VÀ CƠ SỞ VẬT CHẤT
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_rooms_room_type_id
ON rooms(room_type_id);

CREATE INDEX IF NOT EXISTS idx_rooms_status
ON rooms(status);

CREATE INDEX IF NOT EXISTS idx_room_facilities_facility_id
ON room_facilities(facility_id);


-- ============================================================================
-- II. NHÓM QUẢN LÝ KHÁCH HÀNG
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_customers_full_name
ON customers(full_name);

CREATE INDEX IF NOT EXISTS idx_customers_customer_type
ON customers(customer_type);


-- ============================================================================
-- III. NHÓM QUẢN LÝ NHÂN SỰ VÀ TÀI KHOẢN
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_employees_role_id
ON employees(role_id);

CREATE INDEX IF NOT EXISTS idx_employees_status
ON employees(employment_status);


-- ============================================================================
-- IV. NHÓM DỊCH VỤ VÀ MÓN BÁN
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_menu_items_category_id
ON menu_items(category_id);

CREATE INDEX IF NOT EXISTS idx_menu_items_is_active
ON menu_items(is_active);

CREATE INDEX IF NOT EXISTS idx_menu_items_stock_quantity
ON menu_items(stock_quantity);


-- ============================================================================
-- V. NHÓM ĐẶT PHÒNG VÀ LỊCH PHÒNG
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_bookings_customer_id
ON bookings(customer_id);

CREATE INDEX IF NOT EXISTS idx_bookings_room_id
ON bookings(room_id);

CREATE INDEX IF NOT EXISTS idx_bookings_created_by_employee_id
ON bookings(created_by_employee_id);

-- Tối ưu kiểm tra trùng lịch cho các booking còn hiệu lực.
CREATE INDEX IF NOT EXISTS idx_bookings_room_time_active_status
ON bookings(room_id, expected_start_time, expected_end_time)
WHERE status IN ('pending', 'confirmed', 'checked_in');

CREATE INDEX IF NOT EXISTS idx_bookings_status_time
ON bookings(status, expected_start_time);

CREATE INDEX IF NOT EXISTS idx_bookings_customer_status_time
ON bookings(customer_id, status, expected_start_time);


-- ============================================================================
-- VI. NHÓM PHIÊN SỬ DỤNG PHÒNG VÀ ĐỔI PHÒNG
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_room_sessions_booking_id
ON room_sessions(booking_id);

CREATE INDEX IF NOT EXISTS idx_room_sessions_room_id
ON room_sessions(room_id);

CREATE INDEX IF NOT EXISTS idx_room_sessions_active
ON room_sessions(room_id, session_status)
WHERE session_status = 'active';

CREATE INDEX IF NOT EXISTS idx_room_sessions_booking_status
ON room_sessions(booking_id, session_status);

CREATE INDEX IF NOT EXISTS idx_room_sessions_actual_time
ON room_sessions(actual_start_time, actual_end_time);

CREATE INDEX IF NOT EXISTS idx_room_transfers_booking_id
ON room_transfers(booking_id);


-- ============================================================================
-- VII. NHÓM GỌI MÓN VÀ DOANH THU DỊCH VỤ
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_service_orders_session_id
ON service_orders(session_id);

CREATE INDEX IF NOT EXISTS idx_service_orders_created_by_employee_id
ON service_orders(created_by_employee_id);

CREATE INDEX IF NOT EXISTS idx_service_orders_status_time
ON service_orders(order_status, ordered_at);

CREATE INDEX IF NOT EXISTS idx_service_order_items_item_id
ON service_order_items(item_id);

-- Không tạo idx_service_order_items_order_id vì UNIQUE(service_order_id, item_id)
-- đã tạo index có thể phục vụ truy vấn theo service_order_id.


-- ============================================================================
-- VIII. NHÓM HÓA ĐƠN VÀ THANH TOÁN
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_invoices_created_by_employee_id
ON invoices(created_by_employee_id);

CREATE INDEX IF NOT EXISTS idx_invoices_issued_at
ON invoices(issued_at);

CREATE INDEX IF NOT EXISTS idx_invoices_status_issued_at
ON invoices(invoice_status, issued_at);

CREATE INDEX IF NOT EXISTS idx_payments_invoice_id
ON payments(invoice_id);

CREATE INDEX IF NOT EXISTS idx_payments_paid_at
ON payments(paid_at);

CREATE INDEX IF NOT EXISTS idx_payments_method
ON payments(payment_method);

CREATE INDEX IF NOT EXISTS idx_payments_received_by_employee_id
ON payments(received_by_employee_id);


-- ============================================================================
-- IX. NHÓM PHỤ THU
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_invoice_surcharges_invoice_id
ON invoice_surcharges(invoice_id);

CREATE INDEX IF NOT EXISTS idx_invoice_surcharges_type_id
ON invoice_surcharges(surcharge_type_id);

CREATE INDEX IF NOT EXISTS idx_invoice_surcharges_recorded_by_employee_id
ON invoice_surcharges(recorded_by_employee_id);
