-- 06_views.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tạo các view phục vụ tra cứu, hiển thị và báo cáo

-- ============================================================================
-- 1. Trạng thái hiện tại của phòng
-- ============================================================================

CREATE OR REPLACE VIEW vw_room_current_status AS
SELECT
    r.room_id,
    r.room_code,
    r.room_name,
    rt.room_type_name,
    r.actual_capacity,
    rt.hourly_rate,
    r.status,
    r.floor_no,
    r.notes
FROM rooms r
JOIN room_types rt ON r.room_type_id = rt.room_type_id;


-- ============================================================================
-- 2. Danh sách phòng hiện đang trống
-- ============================================================================

CREATE OR REPLACE VIEW vw_available_rooms AS
SELECT *
FROM vw_room_current_status
WHERE status = 'available';


-- ============================================================================
-- 3. Lịch đặt phòng
-- ============================================================================

CREATE OR REPLACE VIEW vw_booking_schedule AS
SELECT
    b.booking_id,
    b.booking_code,
    c.customer_id,
    c.full_name AS customer_name,
    c.phone AS customer_phone,
    r.room_id,
    r.room_code,
    r.room_name,
    b.expected_start_time,
    b.expected_end_time,
    b.guest_count,
    b.status AS booking_status,
    e.full_name AS created_by_employee
FROM bookings b
JOIN customers c ON b.customer_id = c.customer_id
JOIN rooms r ON b.room_id = r.room_id
JOIN employees e ON b.created_by_employee_id = e.employee_id;


-- ============================================================================
-- 4. Phiên sử dụng phòng đang active
-- ============================================================================

CREATE OR REPLACE VIEW vw_active_room_sessions AS
SELECT
    rs.session_id,
    b.booking_id,
    b.booking_code,
    r.room_id,
    r.room_code,
    r.room_name,
    c.customer_id,
    c.full_name AS customer_name,
    c.phone AS customer_phone,
    rs.actual_start_time,
    rs.guest_count_actual,
    e.full_name AS checked_in_by
FROM room_sessions rs
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN customers c ON b.customer_id = c.customer_id
JOIN rooms r ON rs.room_id = r.room_id
JOIN employees e ON rs.checked_in_by_employee_id = e.employee_id
WHERE rs.session_status = 'active';


-- ============================================================================
-- 5. Chi tiết hóa đơn
-- ============================================================================

CREATE OR REPLACE VIEW vw_invoice_details AS
SELECT
    i.invoice_id,
    i.invoice_number,
    b.booking_id,
    b.booking_code,
    c.customer_id,
    c.full_name AS customer_name,
    c.phone AS customer_phone,
    i.issued_at,
    i.room_charge,
    i.service_charge,
    COALESCE(SUM(s.line_total), 0) AS surcharge_total,
    i.discount_amount,
    i.total_amount AS stored_total_amount,
    fn_calculate_invoice_total(i.invoice_id) AS calculated_total_amount,
    i.invoice_status,
    e.full_name AS created_by_employee
FROM invoices i
JOIN bookings b ON i.booking_id = b.booking_id
JOIN customers c ON b.customer_id = c.customer_id
JOIN employees e ON i.created_by_employee_id = e.employee_id
LEFT JOIN invoice_surcharges s ON i.invoice_id = s.invoice_id
GROUP BY
    i.invoice_id,
    i.invoice_number,
    b.booking_id,
    b.booking_code,
    c.customer_id,
    c.full_name,
    c.phone,
    i.issued_at,
    i.room_charge,
    i.service_charge,
    i.discount_amount,
    i.total_amount,
    i.invoice_status,
    e.full_name;


-- ============================================================================
-- 6. Doanh thu theo ngày
-- ============================================================================

CREATE OR REPLACE VIEW vw_daily_revenue AS
SELECT
    DATE(i.issued_at) AS revenue_date,
    SUM(i.room_charge) AS total_room_charge,
    SUM(i.service_charge) AS total_service_charge,
    SUM(fn_calculate_surcharge_total(i.invoice_id)) AS total_surcharge,
    SUM(i.discount_amount) AS total_discount,
    SUM(i.total_amount) AS total_revenue,
    COUNT(i.invoice_id) AS total_invoices
FROM invoices i
WHERE i.invoice_status = 'paid'
GROUP BY DATE(i.issued_at);


-- ============================================================================
-- 7. Doanh thu theo tháng
-- ============================================================================

CREATE OR REPLACE VIEW vw_monthly_revenue AS
SELECT
    EXTRACT(YEAR FROM i.issued_at)::INT AS revenue_year,
    EXTRACT(MONTH FROM i.issued_at)::INT AS revenue_month,
    SUM(i.room_charge) AS total_room_charge,
    SUM(i.service_charge) AS total_service_charge,
    SUM(fn_calculate_surcharge_total(i.invoice_id)) AS total_surcharge,
    SUM(i.discount_amount) AS total_discount,
    SUM(i.total_amount) AS total_revenue,
    COUNT(i.invoice_id) AS total_invoices
FROM invoices i
WHERE i.invoice_status = 'paid'
GROUP BY
    EXTRACT(YEAR FROM i.issued_at),
    EXTRACT(MONTH FROM i.issued_at);


-- ============================================================================
-- 8. Doanh thu theo phòng
-- ============================================================================

CREATE OR REPLACE VIEW vw_revenue_by_room AS
SELECT
    r.room_id,
    r.room_code,
    r.room_name,
    COUNT(DISTINCT rs.session_id) AS total_sessions,
    SUM(fn_calculate_session_duration(rs.actual_start_time, rs.actual_end_time) / 60.0 * rt.hourly_rate) AS total_room_revenue
FROM rooms r
JOIN room_types rt ON r.room_type_id = rt.room_type_id
JOIN room_sessions rs ON r.room_id = rs.room_id
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid'
  AND rs.session_status IN ('completed', 'transferred')
GROUP BY r.room_id, r.room_code, r.room_name;


-- ============================================================================
-- 9. Doanh thu theo loại phòng
-- ============================================================================

CREATE OR REPLACE VIEW vw_revenue_by_room_type AS
SELECT
    rt.room_type_id,
    rt.room_type_name,
    COUNT(DISTINCT rs.session_id) AS total_sessions,
    SUM(fn_calculate_session_duration(rs.actual_start_time, rs.actual_end_time) / 60.0 * rt.hourly_rate) AS total_room_revenue
FROM room_types rt
JOIN rooms r ON rt.room_type_id = r.room_type_id
JOIN room_sessions rs ON r.room_id = rs.room_id
JOIN bookings b ON rs.booking_id = b.booking_id
JOIN invoices i ON b.booking_id = i.booking_id
WHERE i.invoice_status = 'paid'
  AND rs.session_status IN ('completed', 'transferred')
GROUP BY rt.room_type_id, rt.room_type_name;


-- ============================================================================
-- 10. Món bán chạy
-- ============================================================================

CREATE OR REPLACE VIEW vw_top_menu_items AS
SELECT
    mi.item_id,
    mi.item_name,
    mc.category_name,
    SUM(soi.quantity) AS total_quantity_sold,
    SUM(soi.line_total) AS total_revenue
FROM menu_items mi
JOIN menu_categories mc ON mi.category_id = mc.category_id
JOIN service_order_items soi ON mi.item_id = soi.item_id
JOIN service_orders so ON soi.service_order_id = so.service_order_id
WHERE so.order_status = 'confirmed'
GROUP BY mi.item_id, mi.item_name, mc.category_name
ORDER BY total_quantity_sold DESC, total_revenue DESC;


-- ============================================================================
-- 11. Món sắp hết hoặc hết hàng
-- ============================================================================

CREATE OR REPLACE VIEW vw_low_stock_items AS
SELECT
    mi.item_id,
    mi.item_name,
    mc.category_name,
    mi.stock_quantity,
    mi.is_active,
    CASE
        WHEN mi.stock_quantity = 0 THEN 'out_of_stock'
        WHEN mi.stock_quantity <= 10 THEN 'low_stock'
        ELSE 'normal'
    END AS stock_status
FROM menu_items mi
JOIN menu_categories mc ON mi.category_id = mc.category_id
WHERE mi.stock_quantity <= 10
   OR mi.is_active = FALSE;


-- ============================================================================
-- 12. Tổng chi tiêu theo khách hàng
-- ============================================================================

CREATE OR REPLACE VIEW vw_customer_spending AS
SELECT
    c.customer_id,
    c.full_name,
    c.phone,
    c.customer_type,
    COUNT(DISTINCT b.booking_id) AS total_bookings,
    COUNT(DISTINCT i.invoice_id) AS total_paid_invoices,
    COALESCE(SUM(i.total_amount), 0) AS total_spending
FROM customers c
LEFT JOIN bookings b ON c.customer_id = b.customer_id
LEFT JOIN invoices i ON b.booking_id = i.booking_id
                  AND i.invoice_status = 'paid'
GROUP BY c.customer_id, c.full_name, c.phone, c.customer_type;


-- ============================================================================
-- 13. Lịch sử sử dụng dịch vụ của khách hàng
-- ============================================================================

CREATE OR REPLACE VIEW vw_customer_usage_history AS
SELECT
    c.customer_id,
    c.full_name AS customer_name,
    c.phone AS customer_phone,
    b.booking_id,
    b.booking_code,
    b.expected_start_time,
    b.expected_end_time,
    b.status AS booking_status,
    STRING_AGG(DISTINCT r.room_code, ', ' ORDER BY r.room_code) AS used_rooms,
    MIN(rs.actual_start_time) AS first_check_in,
    MAX(rs.actual_end_time) AS last_check_out,
    i.invoice_id,
    i.invoice_number,
    i.total_amount,
    i.invoice_status
FROM customers c
JOIN bookings b ON c.customer_id = b.customer_id
LEFT JOIN room_sessions rs ON b.booking_id = rs.booking_id
LEFT JOIN rooms r ON rs.room_id = r.room_id
LEFT JOIN invoices i ON b.booking_id = i.booking_id
GROUP BY
    c.customer_id,
    c.full_name,
    c.phone,
    b.booking_id,
    b.booking_code,
    b.expected_start_time,
    b.expected_end_time,
    b.status,
    i.invoice_id,
    i.invoice_number,
    i.total_amount,
    i.invoice_status;


-- ============================================================================
-- 14. Giao dịch theo nhân viên
-- ============================================================================

CREATE OR REPLACE VIEW vw_employee_transactions AS
SELECT
    e.employee_id,
    e.full_name AS employee_name,
    ro.role_name,
    COALESCE(bk.total_bookings_created, 0) AS total_bookings_created,
    COALESCE(inv.total_invoices_created, 0) AS total_invoices_created,
    COALESCE(pay.total_payments_received, 0) AS total_payments_received,
    COALESCE(ord.total_service_orders_created, 0) AS total_service_orders_created,
    COALESCE(sur.total_surcharges_recorded, 0) AS total_surcharges_recorded
FROM employees e
JOIN roles ro ON e.role_id = ro.role_id
LEFT JOIN (
    SELECT created_by_employee_id AS employee_id, COUNT(*) AS total_bookings_created
    FROM bookings
    GROUP BY created_by_employee_id
) bk ON e.employee_id = bk.employee_id
LEFT JOIN (
    SELECT created_by_employee_id AS employee_id, COUNT(*) AS total_invoices_created
    FROM invoices
    GROUP BY created_by_employee_id
) inv ON e.employee_id = inv.employee_id
LEFT JOIN (
    SELECT received_by_employee_id AS employee_id, COUNT(*) AS total_payments_received
    FROM payments
    GROUP BY received_by_employee_id
) pay ON e.employee_id = pay.employee_id
LEFT JOIN (
    SELECT created_by_employee_id AS employee_id, COUNT(*) AS total_service_orders_created
    FROM service_orders
    GROUP BY created_by_employee_id
) ord ON e.employee_id = ord.employee_id
LEFT JOIN (
    SELECT recorded_by_employee_id AS employee_id, COUNT(*) AS total_surcharges_recorded
    FROM invoice_surcharges
    GROUP BY recorded_by_employee_id
) sur ON e.employee_id = sur.employee_id;


-- ============================================================================
-- 15. Dashboard tổng hợp
-- ============================================================================

CREATE OR REPLACE VIEW vw_dashboard_summary AS
SELECT
    (SELECT COALESCE(SUM(total_amount), 0) FROM invoices WHERE invoice_status = 'paid') AS total_revenue,
    (SELECT COUNT(*) FROM bookings) AS total_bookings,
    (SELECT COUNT(*) FROM invoices WHERE invoice_status = 'paid') AS total_paid_invoices,
    (SELECT COALESCE(SUM(room_charge), 0) FROM invoices WHERE invoice_status = 'paid') AS total_room_revenue,
    (SELECT COALESCE(SUM(service_charge), 0) FROM invoices WHERE invoice_status = 'paid') AS total_service_revenue,
    (SELECT COALESCE(SUM(fn_calculate_surcharge_total(invoice_id)), 0) FROM invoices WHERE invoice_status = 'paid') AS total_surcharge_revenue,
    (SELECT room_name FROM vw_revenue_by_room ORDER BY total_sessions DESC, total_room_revenue DESC LIMIT 1) AS top_room,
    (SELECT item_name FROM vw_top_menu_items ORDER BY total_quantity_sold DESC, total_revenue DESC LIMIT 1) AS top_menu_item;
