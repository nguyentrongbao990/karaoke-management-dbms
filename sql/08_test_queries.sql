-- 08_test_queries.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Demo luồng nghiệp vụ hoàn chỉnh và kiểm tra một số ràng buộc

-- ============================================================================
-- KỊCH BẢN 1: ĐẶT PHÒNG VÀ KIỂM TRA TRÙNG LỊCH
-- ============================================================================

-- 1. Lễ tân tạo phiếu đặt phòng cho khách Kevin Nguyễn vào phòng P101.
CALL sp_create_booking(
    'BOOK-DEMO-001',
    1,
    1,
    2,
    '2026-04-27 21:00:00',
    '2026-04-27 23:00:00',
    5,
    'Khách VIP đặt trước'
);

-- 2. Test trùng lịch: bỏ comment dòng dưới để kiểm tra hệ thống chặn đặt trùng phòng.
-- CALL sp_create_booking(
--     'BOOK-DEMO-002',
--     2,
--     1,
--     2,
--     '2026-04-27 22:00:00',
--     '2026-04-27 23:30:00',
--     3,
--     'Booking trùng giờ để test'
-- );

SELECT * FROM vw_booking_schedule;


-- ============================================================================
-- KỊCH BẢN 2: CHECK-IN, GỌI MÓN, HỦY ĐƠN VÀ HOÀN KHO
-- ============================================================================

-- 3. Khách đến nhận phòng.
CALL sp_check_in_booking(1, 2, 5);

SELECT * FROM vw_active_room_sessions;

-- 4. Tạo đơn nháp: 10 lon Tiger Bạc.
INSERT INTO service_orders (session_id, created_by_employee_id, order_status)
VALUES (1, 4, 'draft');

INSERT INTO service_order_items (service_order_id, item_id, quantity, unit_price)
VALUES (1, 1, 10, 30000);

CALL sp_confirm_service_order(1);

-- Kiểm tra tồn kho sau khi xác nhận đơn.
SELECT item_name, stock_quantity
FROM menu_items
WHERE item_id = 1;

-- 5. Hủy đơn đã xác nhận để kiểm tra hoàn kho.
CALL sp_cancel_service_order(1);

SELECT item_name, stock_quantity
FROM menu_items
WHERE item_id = 1;

-- 6. Tạo đơn mới: 5 lon Tiger Bạc + 1 đĩa khô gà.
INSERT INTO service_orders (session_id, created_by_employee_id, order_status)
VALUES (1, 4, 'draft');

INSERT INTO service_order_items (service_order_id, item_id, quantity, unit_price)
VALUES
(2, 1, 5, 30000),
(2, 6, 1, 80000);

CALL sp_confirm_service_order(2);

SELECT * FROM vw_top_menu_items;


-- ============================================================================
-- KỊCH BẢN 3: ĐỔI PHÒNG
-- ============================================================================

-- 7. Khách đổi từ P101 sang P201 VIP.
CALL sp_transfer_room(1, 4, 2, 'Khách muốn chuyển sang phòng VIP');

-- Kiểm tra session sau đổi phòng.
SELECT
    rs.session_id,
    rs.booking_id,
    r.room_code,
    rs.actual_start_time,
    rs.actual_end_time,
    rs.session_status,
    rs.guest_count_actual
FROM room_sessions rs
JOIN rooms r ON rs.room_id = r.room_id
WHERE rs.booking_id = 1
ORDER BY rs.session_id;

SELECT * FROM room_transfers;


-- ============================================================================
-- KỊCH BẢN 4: CHECK-OUT, PHỤ THU VÀ THANH TOÁN
-- ============================================================================

-- 8. Check-out, lập hóa đơn, giảm giá 10.000đ.
CALL sp_check_out_booking(1, 3, 10000, 'INV-DEMO-001');

SELECT * FROM vw_invoice_details;

-- 9. Thêm phụ thu: khách làm vỡ 1 ly.
CALL sp_add_invoice_surcharge(
    1,
    1,
    1,
    3,
    'Khách làm rơi ly lúc đổi phòng'
);

-- 10. Thêm phụ thu theo đơn giá tùy chỉnh: hư hỏng micro.
CALL sp_add_invoice_surcharge(
    1,
    4,
    1,
    3,
    'Micro bị rơi, tính phí theo thực tế',
    150000
);

SELECT * FROM vw_invoice_details;

-- 11. Xác nhận thanh toán bằng đúng total_amount, không hard-code số tiền.
DO $$
DECLARE
    v_total NUMERIC(12,2);
BEGIN
    SELECT total_amount
    INTO v_total
    FROM invoices
    WHERE invoice_id = 1;

    CALL sp_confirm_payment(1, v_total, 'cash', 'CASH_DIRECT', 3);
END;
$$;

SELECT * FROM payments;
SELECT * FROM vw_invoice_details;


-- ============================================================================
-- KỊCH BẢN 5: KIỂM TRA KHÓA DỮ LIỆU SAU THANH TOÁN
-- ============================================================================

-- Các câu dưới đây nên báo lỗi nếu bỏ comment, vì hóa đơn đã paid.

-- CALL sp_add_invoice_surcharge(1, 2, 1, 3, 'Test thêm phụ thu sau thanh toán');

-- UPDATE room_sessions
-- SET actual_end_time = actual_end_time + INTERVAL '10 minutes'
-- WHERE booking_id = 1;

-- UPDATE service_order_items
-- SET quantity = quantity + 1
-- WHERE service_order_id = 2;


-- ============================================================================
-- KỊCH BẢN 6: XEM BÁO CÁO VÀ DASHBOARD
-- ============================================================================

SELECT * FROM vw_room_current_status;
SELECT * FROM vw_daily_revenue;
SELECT * FROM vw_monthly_revenue;
SELECT * FROM vw_revenue_by_room;
SELECT * FROM vw_revenue_by_room_type;
SELECT * FROM vw_customer_spending;
SELECT * FROM vw_customer_usage_history;
SELECT * FROM vw_employee_transactions;
SELECT * FROM vw_low_stock_items;
SELECT * FROM vw_dashboard_summary;
