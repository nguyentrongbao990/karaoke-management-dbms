-- 08_test_queries.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Kịch bản Demo nghiệm thu đồ án (Chạy từng khối lệnh từ trên xuống dưới)

-- ============================================================================
-- KỊCH BẢN 1: LUỒNG NGHIỆP VỤ CHUẨN (HAPPY PATH)
-- ============================================================================

-- 1. Lễ tân (ID: 2) tạo phiếu đặt phòng cho khách Kevin Nguyễn (ID: 1) vào Phòng P101 (ID: 1)
-- Sử dụng mã sinh viên làm mã Booking để đánh dấu bản quyền đồ án
CALL sp_create_booking(
    'B23DCCE014', 
    1, 1, 2, 
    CURRENT_TIMESTAMP, 
    CURRENT_TIMESTAMP + INTERVAL '2 hours', 
    5, 'Khách yêu cầu phòng lạnh'
);

-- Xem lịch đặt phòng vừa tạo (Sẽ thấy phòng đang ở trạng thái pending/confirmed)
SELECT * FROM vw_booking_schedule;

-- 2. Khách đến quán, Lễ tân thực hiện Check-in (Xác nhận 5 người vào phòng)
CALL sp_check_in_booking(1, 2, 5);

-- Quản lý kiểm tra phòng đang hoạt động (Phòng 101 đã chuyển sang occupied)
SELECT * FROM vw_active_room_sessions;

-- 3. Khách gọi món: Phục vụ (ID: 4) ghi nhận đơn nháp
INSERT INTO service_orders (session_id, created_by_employee_id, order_status) 
VALUES (1, 4, 'draft');

-- Khách gọi 1 đĩa Khô gà (ID: 5) và 10 lon Tiger Bạc (ID: 2)
-- (Lưu ý: Trigger trg_calculate_service_order_item_total sẽ tự động nhân tiền)
INSERT INTO service_order_items (service_order_id, item_id, quantity, unit_price) VALUES 
(1, 5, 1, 80000),
(1, 2, 10, 30000);

-- Phục vụ mang đồ lên phòng và Bấm xác nhận đơn (Kho sẽ bị trừ ở bước này)
CALL sp_confirm_service_order(1);

-- Kiểm tra lại kho Tiger Bạc (Từ 300 lon sẽ chỉ còn 290 lon)
SELECT item_name, stock_quantity FROM menu_items WHERE item_id = 2;

-- ============================================================================
-- *** FIX LỖI THỜI GIAN: DỪNG 1 GIÂY TRƯỚC KHI CHECK-OUT ***
-- Đảm bảo actual_end_time luôn lớn hơn actual_start_time
SELECT pg_sleep(1);
-- ============================================================================

-- 4. Khách hát xong, Thu ngân (ID: 3) tiến hành Check-out và tạo hóa đơn (Giảm giá 20k)
CALL sp_check_out_booking(1, 3, 20000, 'INV-DEMO-001');

-- 5. Phát sinh sự cố: Kỹ thuật báo khách làm vỡ 1 cái ly (Phụ thu ID: 2)
-- (Lưu ý: Trigger trg_refresh_invoice_total_after_surcharge_change sẽ tự động cộng tiền vào Hóa đơn)
INSERT INTO invoice_surcharges (invoice_id, surcharge_type_id, quantity, unit_amount, recorded_by_employee_id) 
VALUES (1, 2, 1, 50000, 3);

-- 6. Thu ngân in hóa đơn chi tiết cho khách kiểm tra trước khi tính tiền
-- View này đã gom đủ: Tiền phòng + Tiền dịch vụ (380k) + Phụ thu vỡ ly (50k) - Giảm giá (20k)
SELECT * FROM vw_invoice_details WHERE invoice_number = 'INV-DEMO-001';

-- Lấy số tiền tổng cộng (total_amount) từ câu lệnh trên để chốt thanh toán
-- Giả sử tổng tiền là 560,000 VND. Khách quẹt thẻ (bank_transfer)
CALL sp_confirm_payment(1, 560000, 'bank_transfer', 'MBBANK-TKS123456', 3);

-- ============================================================================
-- KỊCH BẢN 2: TEST CÁC TRIGGER BẢO VỆ DỮ LIỆU (BÁO LỖI LÀ THÀNH CÔNG)
-- ============================================================================

-- Test 1: Cố tình đặt phòng P101 trùng giờ với nhóm khách đang hát (Sẽ bị báo lỗi)
CALL sp_create_booking(
    'B23DCCE015', 
    2, 1, 2, 
    CURRENT_TIMESTAMP, 
    CURRENT_TIMESTAMP + INTERVAL '1 hour', 
    2, 'Khách vãng lai'
);

-- Test 2: Cố tình sửa giá món ăn trong hóa đơn đã thanh toán (Sẽ bị Trigger chặn lại)
UPDATE service_order_items SET unit_price = 1000 WHERE service_order_item_id = 1;

-- Test 3: Thu ngân cố tình xóa hóa đơn đã thu tiền để đút túi riêng (Sẽ bị Trigger chặn lại)
DELETE FROM invoices WHERE invoice_id = 1;

-- ============================================================================
-- KỊCH BẢN 3: XEM DASHBOARD BÁO CÁO CỦA QUẢN LÝ
-- ============================================================================
SELECT * FROM vw_dashboard_summary;
SELECT * FROM vw_top_menu_items;
SELECT * FROM vw_employee_transactions;
