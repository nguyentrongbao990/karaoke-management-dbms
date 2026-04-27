-- 06_views_FIXED.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tạo các báo cáo thống kê chính xác, tránh tính trùng dữ liệu

-- 1. vw_room_current_status: Trạng thái hiện tại của từng phòng
CREATE OR REPLACE VIEW vw_room_current_status AS
SELECT r.room_code, r.room_name, rt.room_type_name, r.actual_capacity, rt.hourly_rate, r.status
FROM rooms r
JOIN room_types rt ON r.room_type_id = rt.room_type_id;

-- 2. vw_available_rooms: Danh sách phòng đang trống
CREATE OR REPLACE VIEW vw_available_rooms AS
SELECT room_code, room_name, room_type_name, actual_capacity, hourly_rate
FROM vw_room_current_status
WHERE status = 'available';

-- 3. vw_booking_schedule: Lịch đặt phòng
CREATE OR REPLACE VIEW vw_booking_schedule AS
SELECT b.booking_code, c.full_name AS customer_name, r.room_name, b.expected_start_time, b.expected_end_time, b.guest_count, b.status AS booking_status
FROM bookings b
JOIN customers c ON b.customer_id = c.customer_id
JOIN rooms r ON b.room_id = r.room_id;

-- 4. vw_active_room_sessions: Phiên sử dụng phòng đang diễn ra
CREATE OR REPLACE VIEW vw_active_room_sessions AS
SELECT r.room_name, c.full_name AS customer_name, rs.actual_start_time, rs.guest_count_actual, e.full_name AS checked_in_by
FROM room_sessions rs
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN customers c ON b.customer_id = c.customer_id
JOIN rooms r ON rs.room_id = r.room_id
JOIN employees e ON rs.checked_in_by_employee_id = e.employee_id
WHERE rs.session_status = 'active';

-- 5. vw_invoice_details: Chi tiết hóa đơn (Phụ thu tính theo SUM chi tiết)
CREATE OR REPLACE VIEW vw_invoice_details AS
SELECT i.invoice_number, c.full_name AS customer_name, b.booking_code, 
       i.room_charge, i.service_charge, 
       COALESCE((SELECT SUM(line_total) FROM invoice_surcharges s WHERE s.invoice_id = i.invoice_id), 0) AS total_surcharge,
       i.discount_amount, i.total_amount, i.invoice_status
FROM invoices i
JOIN bookings b ON i.booking_id = b.booking_id
JOIN customers c ON b.customer_id = c.customer_id;

-- 6. vw_daily_revenue: Doanh thu theo ngày
CREATE OR REPLACE VIEW vw_daily_revenue AS
SELECT DATE(issued_at) AS revenue_date, 
       SUM(room_charge) AS total_room_charge, 
       SUM(service_charge) AS total_service_charge, 
       SUM(total_amount - room_charge - service_charge + discount_amount) AS total_surcharge,
       SUM(total_amount) AS total_revenue, 
       COUNT(invoice_id) AS total_invoices
FROM invoices
WHERE invoice_status = 'paid'
GROUP BY DATE(issued_at);

-- 7. vw_revenue_by_room: Doanh thu theo phòng (ĐÃ FIX: TÍNH THEO SESSION ĐỂ TRÁNH TRÙNG LẶP) 
CREATE OR REPLACE VIEW vw_revenue_by_room AS
SELECT r.room_code, r.room_name, 
       COUNT(DISTINCT rs.session_id) AS total_sessions, 
       SUM(fn_calculate_session_duration(rs.actual_start_time, rs.actual_end_time) / 60.0 * rt.hourly_rate) AS total_room_revenue
FROM rooms r
JOIN room_types rt ON r.room_type_id = rt.room_type_id
JOIN room_sessions rs ON r.room_id = rs.room_id
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid' AND rs.session_status IN ('completed', 'transferred')
GROUP BY r.room_code, r.room_name;

-- 8. vw_revenue_by_room_type: Doanh thu theo loại phòng (ĐÃ FIX TÍNH THEO SESSION) 
CREATE OR REPLACE VIEW vw_revenue_by_room_type AS
SELECT rt.room_type_name, 
       COUNT(DISTINCT rs.session_id) AS total_sessions, 
       SUM(fn_calculate_session_duration(rs.actual_start_time, rs.actual_end_time) / 60.0 * rt.hourly_rate) AS total_room_revenue
FROM room_types rt
JOIN rooms r ON rt.room_type_id = r.room_type_id
JOIN room_sessions rs ON r.room_id = rs.room_id
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid' AND rs.session_status IN ('completed', 'transferred')
GROUP BY rt.room_type_name;

-- 9. vw_top_menu_items: Món bán chạy
CREATE OR REPLACE VIEW vw_top_menu_items AS
SELECT mi.item_name, mc.category_name, 
       SUM(soi.quantity) AS total_quantity_sold, 
       SUM(soi.line_total) AS total_revenue
FROM menu_items mi
JOIN menu_categories mc ON mi.category_id = mc.category_id
JOIN service_order_items soi ON mi.item_id = soi.item_id
JOIN service_orders so ON soi.service_order_id = so.service_order_id
WHERE so.order_status = 'confirmed'
GROUP BY mi.item_name, mc.category_name
ORDER BY total_quantity_sold DESC;

-- 10. vw_dashboard_summary: Dashboard tổng hợp (ĐÃ BỔ SUNG PHỤ THU) 
CREATE OR REPLACE VIEW vw_dashboard_summary AS
SELECT 
    (SELECT COALESCE(SUM(total_amount), 0) FROM invoices WHERE invoice_status = 'paid') AS total_revenue,
    (SELECT COUNT(*) FROM bookings) AS total_bookings,
    (SELECT COALESCE(SUM(room_charge), 0) FROM invoices WHERE invoice_status = 'paid') AS total_room_revenue,
    (SELECT COALESCE(SUM(service_charge), 0) FROM invoices WHERE invoice_status = 'paid') AS total_service_revenue,
    (SELECT COALESCE(SUM(total_amount - room_charge - service_charge + discount_amount), 0) FROM invoices WHERE invoice_status = 'paid') AS total_surcharge_revenue;
