-- 02_indexes.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tối ưu hóa tốc độ truy vấn cho các bảng dữ liệu

-- ============================================================================
-- I. NHÓM QUẢN LÝ PHÒNG VÀ CƠ SỞ VẬT CHẤT
-- ============================================================================

-- Tăng tốc join phòng với loại phòng và thống kê theo loại phòng [cite: 516-523]
CREATE INDEX idx_rooms_room_type_id ON rooms(room_type_id);

-- Tăng tốc lọc tìm phòng theo trạng thái (available, occupied...) [cite: 524-531]
CREATE INDEX idx_rooms_status ON rooms(status);

-- Tăng tốc tra cứu phòng nào có thiết bị cụ thể [cite: 532-538]
CREATE INDEX idx_room_facilities_facility_id ON room_facilities(facility_id);


-- ============================================================================
-- II. NHÓM QUẢN LÝ KHÁCH HÀNG
-- ============================================================================

-- Tăng tốc tìm kiếm khách hàng theo tên [cite: 540-545]
CREATE INDEX idx_customers_full_name ON customers(full_name);

-- Tăng tốc lọc khách hàng theo hạng (Regular, Loyal, VIP) [cite: 546-551]
CREATE INDEX idx_customers_customer_type ON customers(customer_type);


-- ============================================================================
-- III. NHÓM QUẢN LÝ NHÂN SỰ VÀ TÀI KHOẢN
-- ============================================================================

-- Tăng tốc join nhân viên với vai trò/chức vụ [cite: 553-559]
CREATE INDEX idx_employees_role_id ON employees(role_id);

-- Tăng tốc lọc nhân viên theo trạng thái làm việc [cite: 560-565]
CREATE INDEX idx_employees_status ON employees(employment_status);


-- ============================================================================
-- IV. NHÓM DỊCH VỤ VÀ MÓN BÁN
-- ============================================================================

-- Tăng tốc hiển thị menu theo danh mục và thống kê theo nhóm món [cite: 567-573]
CREATE INDEX idx_menu_items_category_id ON menu_items(category_id);

-- Tăng tốc lọc các món đang kinh doanh [cite: 574-579]
CREATE INDEX idx_menu_items_is_active ON menu_items(is_active);

-- Tăng tốc truy vấn cảnh báo hàng sắp hết [cite: 580-586]
CREATE INDEX idx_menu_items_stock_quantity ON menu_items(stock_quantity);


-- ============================================================================
-- V. NHÓM ĐẶT PHÒNG VÀ LỊCH PHÒNG (QUAN TRỌNG NHẤT)
-- ============================================================================

-- Tăng tốc tìm lịch sử đặt phòng của một khách hàng [cite: 589-595]
CREATE INDEX idx_bookings_customer_id ON bookings(customer_id);

-- Tăng tốc tra cứu lịch đặt theo từng phòng cụ thể [cite: 596-601]
CREATE INDEX idx_bookings_room_id ON bookings(room_id);

-- Index phức hợp: Kiểm tra trùng lịch đặt phòng (truy vấn cốt lõi) [cite: 607-616]
CREATE INDEX idx_bookings_room_time_status 
ON bookings(room_id, expected_start_time, expected_end_time, status);

-- Tăng tốc lọc lịch đặt phòng theo trạng thái và thời gian [cite: 617-623]
CREATE INDEX idx_bookings_status_time ON bookings(status, expected_start_time);


-- ============================================================================
-- VI. NHÓM PHIÊN SỬ DỤNG PHÒNG VÀ ĐỔI PHÒNG
-- ============================================================================

-- Tăng tốc tìm tất cả session (phiên hát) của một booking để tính tiền [cite: 631-639]
CREATE INDEX idx_room_sessions_booking_id ON room_sessions(booking_id);

-- Tăng tốc thống kê lượt sử dụng theo phòng [cite: 640-646]
CREATE INDEX idx_room_sessions_room_id ON room_sessions(room_id);

-- Partial Index: Chỉ index các phòng đang có khách (cực nhanh khi check-out/đổi phòng) 
CREATE INDEX idx_room_sessions_active 
ON room_sessions(room_id, session_status) 
WHERE session_status = 'active';

-- Tăng tốc tìm lịch sử đổi phòng của một booking [cite: 669-675]
CREATE INDEX idx_room_transfers_booking_id ON room_transfers(booking_id);


-- ============================================================================
-- VII. NHÓM GỌI MÓN VÀ DOANH THU DỊCH VỤ
-- ============================================================================

-- Tăng tốc tìm các đơn gọi món của một phiên hát [cite: 677-683]
CREATE INDEX idx_service_orders_session_id ON service_orders(session_id);

-- Tăng tốc thống kê món bán chạy nhất [cite: 697-703]
CREATE INDEX idx_service_order_items_item_id ON service_order_items(item_id);


-- ============================================================================
-- VIII. NHÓM HÓA ĐƠN VÀ THANH TOÁN
-- ============================================================================

-- Tăng tốc báo cáo doanh thu theo thời gian (Ngày/Tháng/Năm) [cite: 715-721]
CREATE INDEX idx_invoices_issued_at ON invoices(issued_at);

-- Index kết hợp: Lọc hóa đơn đã thanh toán theo thời gian để làm báo cáo [cite: 722-729]
CREATE INDEX idx_invoices_status_issued_at ON invoices(invoice_status, issued_at);

-- Tăng tốc tra cứu các lần thanh toán của một hóa đơn [cite: 730-735]
CREATE INDEX idx_payments_invoice_id ON payments(invoice_id);

-- Tăng tốc thống kê doanh thu theo phương thức thanh toán (Cash, Bank, E-wallet) [cite: 743-748]
CREATE INDEX idx_payments_method ON payments(payment_method);


-- ============================================================================
-- IX. NHÓM PHỤ THU
-- ============================================================================

-- Tăng tốc tính tổng phụ thu cho hóa đơn [cite: 755-761]
CREATE INDEX idx_invoice_surcharges_invoice_id ON invoice_surcharges(invoice_id);

-- Tăng tốc thống kê loại phụ thu nào phát sinh nhiều nhất (vỡ ly, đồ ngoài...) [cite: 762-767]
CREATE INDEX idx_invoice_surcharges_type_id ON invoice_surcharges(surcharge_type_id);
