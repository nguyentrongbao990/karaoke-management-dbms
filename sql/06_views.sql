-- 06_views.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tạo các khung nhìn (View) phục vụ tra cứu nhanh và thống kê báo cáo

-- ==========================================
-- 1. CÁC VIEW TRẠNG THÁI VÀ VẬN HÀNH PHÒNG
-- ==========================================

-- 1. vw_room_current_status: Hiển thị trạng thái hiện tại của từng phòng [cite: 1279-1288]
CREATE OR REPLACE VIEW vw_room_current_status AS
SELECT r.room_code, r.room_name, rt.room_type_name, r.actual_capacity, rt.hourly_rate, r.status
FROM rooms r
JOIN room_types rt ON r.room_type_id = rt.room_type_id;

-- 2. vw_available_rooms: Hiển thị các phòng hiện đang trống [cite: 1289-1296]
CREATE OR REPLACE VIEW vw_available_rooms AS
SELECT room_code, room_name, room_type_name, actual_capacity, hourly_rate
FROM vw_room_current_status
WHERE status = 'available';

-- 3. vw_booking_schedule: Hiển thị lịch đặt phòng [cite: 1297-1306]
CREATE OR REPLACE VIEW vw_booking_schedule AS
SELECT b.booking_code, c.full_name AS customer_name, r.room_name, b.expected_start_time, b.expected_end_time, b.guest_count, b.status AS booking_status
FROM bookings b
JOIN customers c ON b.customer_id = c.customer_id
JOIN rooms r ON b.room_id = r.room_id;

-- 4. vw_active_room_sessions: Hiển thị các phiên sử dụng phòng đang diễn ra [cite: 1307-1315]
CREATE OR REPLACE VIEW vw_active_room_sessions AS
SELECT r.room_name, c.full_name AS customer_name, rs.actual_start_time, rs.guest_count_actual, e.full_name AS checked_in_by
FROM room_sessions rs
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN customers c ON b.customer_id = c.customer_id
JOIN rooms r ON rs.room_id = r.room_id
JOIN employees e ON rs.checked_in_by_employee_id = e.employee_id
WHERE rs.session_status = 'active';

-- ==========================================
-- 2. CÁC VIEW LIÊN QUAN ĐẾN TÀI CHÍNH VÀ HÓA ĐƠN
-- ==========================================

-- 5. vw_invoice_details: Hiển thị chi tiết hóa đơn tổng hợp 
CREATE OR REPLACE VIEW vw_invoice_details AS
SELECT i.invoice_number, c.full_name AS customer_name, b.booking_code, 
       i.room_charge, i.service_charge, 
       COALESCE((SELECT SUM(line_total) FROM invoice_surcharges s WHERE s.invoice_id = i.invoice_id), 0) AS total_surcharge,
       i.discount_amount, i.total_amount, i.invoice_status
FROM invoices i
JOIN bookings b ON i.booking_id = b.booking_id
JOIN customers c ON b.customer_id = c.customer_id;

-- 6. vw_daily_revenue: Thống kê doanh thu theo ngày [cite: 1331-1340]
CREATE OR REPLACE VIEW vw_daily_revenue AS
SELECT DATE(issued_at) AS revenue_date, 
       SUM(room_charge) AS total_room_charge, 
       SUM(service_charge) AS total_service_charge, 
       -- Tổng phụ thu được tính ngược bằng cách lấy tổng cuối trừ đi các thành phần gốc
       SUM(total_amount - room_charge - service_charge + discount_amount) AS total_surcharge,
       SUM(total_amount) AS total_revenue, 
       COUNT(invoice_id) AS total_invoices
FROM invoices
WHERE invoice_status = 'paid'
GROUP BY DATE(issued_at);

-- 7. vw_monthly_revenue: Thống kê doanh thu theo tháng [cite: 1341-1348]
CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT EXTRACT(MONTH FROM issued_at) AS revenue_month, 
       EXTRACT(YEAR FROM issued_at) AS revenue_year,
       SUM(total_amount) AS total_revenue, 
       COUNT(invoice_id) AS total_invoices
FROM invoices
WHERE invoice_status = 'paid'
GROUP BY EXTRACT(YEAR FROM issued_at), EXTRACT(MONTH FROM issued_at);

-- 8. vw_revenue_by_room: Thống kê doanh thu theo từng phòng [cite: 1349-1357]
CREATE OR REPLACE VIEW vw_revenue_by_room AS
SELECT r.room_code, r.room_name, 
       COUNT(DISTINCT rs.session_id) AS total_sessions, 
       SUM(i.room_charge) AS total_room_revenue
FROM rooms r
JOIN room_sessions rs ON r.room_id = rs.room_id
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid'
GROUP BY r.room_code, r.room_name;

-- 9. vw_revenue_by_room_type: Thống kê doanh thu theo loại phòng [cite: 1358-1365]
CREATE OR REPLACE VIEW vw_revenue_by_room_type AS
SELECT rt.room_type_name, 
       COUNT(DISTINCT rs.session_id) AS total_sessions, 
       SUM(i.room_charge) AS total_room_revenue
FROM room_types rt
JOIN rooms r ON rt.room_type_id = r.room_type_id
JOIN room_sessions rs ON r.room_id = rs.room_id
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid'
GROUP BY rt.room_type_name;

-- ==========================================
-- 3. CÁC VIEW LIÊN QUAN ĐẾN DỊCH VỤ VÀ MÓN BÁN
-- ==========================================

-- 10. vw_top_menu_items: Thống kê món bán chạy [cite: 1366-1373]
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

-- 11. vw_low_stock_items: Hiển thị món sắp hết hoặc đã hết hàng [cite: 1374-1381]
CREATE OR REPLACE VIEW vw_low_stock_items AS
SELECT mi.item_name, mc.category_name, mi.stock_quantity, mi.is_active
FROM menu_items mi
JOIN menu_categories mc ON mi.category_id = mc.category_id
WHERE mi.stock_quantity <= 10; -- Mức cảnh báo mặc định là 10, có thể chỉnh sửa

-- ==========================================
-- 4. CÁC VIEW LIÊN QUAN ĐẾN KHÁCH HÀNG VÀ NHÂN VIÊN
-- ==========================================

-- 12. vw_customer_spending: Thống kê tổng chi tiêu của khách hàng [cite: 1382-1389]
CREATE OR REPLACE VIEW vw_customer_spending AS
SELECT c.full_name, c.phone, 
       COUNT(DISTINCT b.booking_id) AS total_bookings, 
       COUNT(DISTINCT i.invoice_id) AS total_paid_invoices, 
       SUM(i.total_amount) AS total_spent
FROM customers c
JOIN bookings b ON c.customer_id = b.customer_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid'
GROUP BY c.full_name, c.phone;

-- 13. vw_customer_usage_history: Hiển thị lịch sử sử dụng dịch vụ của từng khách hàng [cite: 1390-1400]
CREATE OR REPLACE VIEW vw_customer_usage_history AS
SELECT c.full_name, b.booking_code, r.room_name, 
       b.expected_start_time, b.expected_end_time, 
       i.total_amount, i.invoice_status
FROM customers c
JOIN bookings b ON c.customer_id = b.customer_id
JOIN rooms r ON b.room_id = r.room_id
LEFT JOIN invoices i ON b.booking_id = i.booking_id;

-- 14. vw_employee_transactions: Thống kê giao dịch theo nhân viên [cite: 1401-1410]
CREATE OR REPLACE VIEW vw_employee_transactions AS
SELECT e.full_name, r.role_name,
       (SELECT COUNT(*) FROM bookings WHERE created_by_employee_id = e.employee_id) AS bookings_created,
       (SELECT COUNT(*) FROM invoices WHERE created_by_employee_id = e.employee_id) AS invoices_created,
       (SELECT COUNT(*) FROM payments WHERE received_by_employee_id = e.employee_id) AS payments_received,
       (SELECT COUNT(*) FROM service_orders WHERE created_by_employee_id = e.employee_id) AS orders_taken
FROM employees e
JOIN roles r ON e.role_id = r.role_id;

-- ==========================================
-- 5. VIEW TỔNG HỢP DASHBOARD
-- ==========================================

-- 15. vw_dashboard_summary: Cung cấp số liệu tổng hợp nhanh cho quản lý [cite: 1411-1422]
CREATE OR REPLACE VIEW vw_dashboard_summary AS
SELECT 
    (SELECT COALESCE(SUM(total_amount), 0) FROM invoices WHERE invoice_status = 'paid') AS total_revenue,
    (SELECT COUNT(*) FROM bookings) AS total_bookings,
    (SELECT COUNT(*) FROM invoices WHERE invoice_status = 'paid') AS total_paid_invoices,
    (SELECT COALESCE(SUM(room_charge), 0) FROM invoices WHERE invoice_status = 'paid') AS total_room_revenue,
    (SELECT COALESCE(SUM(service_charge), 0) FROM invoices WHERE invoice_status = 'paid') AS total_service_revenue;
