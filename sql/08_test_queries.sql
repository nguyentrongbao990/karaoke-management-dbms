-- 08_test_queries_FINAL.sql
-- Hệ thống quản lý Karaoke - Sinh viên: B23DCCE014
-- Mục đích: Demo luồng nghiệp vụ hoàn chỉnh và kiểm tra các ràng buộc bảo mật

-- ============================================================================
-- KỊCH BẢN 1: ĐẶT PHÒNG VÀ KIỂM TRA TRÙNG LỊCH (TRƯỚC CHECK-IN) 
-- ============================================================================

-- 1. Lễ tân (ID: 2) tạo phiếu đặt phòng cho khách Kevin Nguyễn vào Phòng P101 (ID: 1)
CALL sp_create_booking('BOOK-014-A', 1, 1, 2, '2026-04-27 21:00:00', '2026-04-27 23:00:00', 5, 'Khách VIP');

-- 2. TEST TRÙNG LỊCH (PHẢI BÁO LỖI): Cố tình đặt phòng P101 vào khung giờ đang bận [cite: 463]
-- (Nếu chạy dòng này, PostgreSQL phải báo lỗi "Trùng lịch với một đặt phòng khác")
-- CALL sp_create_booking('BOOK-014-B', 2, 1, 2, '2026-04-27 22:00:00', '2026-04-27 23:59:00', 3, 'Khách vãng lai');

-- ============================================================================
-- KỊCH BẢN 2: CHECK-IN VÀ GỌI MÓN (CÓ HỦY ĐƠN ĐỂ TEST HOÀN KHO)
-- ============================================================================

-- 3. Khách đến nhận phòng thực tế (Dùng chính ID Booking vừa tạo)
CALL sp_check_in_booking(1, 2, 5);

-- 4. Gọi món: Khách gọi 10 lon Tiger Bạc (ID: 1)
INSERT INTO service_orders (session_id, created_by_employee_id, order_status) VALUES (1, 2, 'draft');
INSERT INTO service_order_items (service_order_id, item_id, quantity, unit_price) VALUES (1, 1, 10, 30000);
CALL sp_confirm_service_order(1); -- Chốt đơn, kho trừ 10 lon

-- 5. TEST HỦY ĐƠN (HOÀN KHO): Khách trả lại 10 lon bia, thực hiện hủy đơn 
CALL sp_cancel_service_order(1); -- Trạng thái sang cancelled, kho cộng trả lại 10 lon

-- 6. Gọi món mới: 5 lon Tiger Bạc và 1 đĩa Khô gà (ID: 2)
INSERT INTO service_orders (session_id, created_by_employee_id, order_status) VALUES (1, 2, 'draft');
INSERT INTO service_order_items (service_order_id, item_id, quantity, unit_price) VALUES (2, 1, 5, 30000), (2, 2, 1, 80000);
CALL sp_confirm_service_order(2);

-- ============================================================================
-- KỊCH BẢN 3: ĐỔI PHÒNG (TEST TÍNH TIỀN LIÊN TỤC) [cite: 354-362, 374-385]
-- ============================================================================

-- 7. Khách muốn đổi từ P101 sang phòng VIP P201 (ID: 3)
CALL sp_transfer_room(1, 3, 2, 'Khách muốn không gian riêng tư hơn');

-- Kiểm tra xem tiền phòng P101 đã được ghi nhận vào tổng chưa (View doanh thu phòng)
SELECT * FROM vw_revenue_by_room;

-- ============================================================================
-- KỊCH BẢN 4: THANH TOÁN VÀ PHỤ THU
-- ============================================================================

-- 8. Kết thúc phiên hát (Check-out) - Giảm giá 10,000đ
CALL sp_check_out_booking(1, 3, 10000, 'INV-23DCCE014-01');

-- 9. Thêm phụ thu: Khách làm vỡ ly (Surcharge ID: 1) 
CALL sp_add_invoice_surcharge(1, 1, 1, 3, 'Khách làm rơi ly lúc đổi phòng');

-- 10. XEM SỐ TIỀN THỰC TẾ TRƯỚC KHI THANH TOÁN (TRÁNH HARD-CODE) 
SELECT invoice_number, total_amount FROM invoices WHERE invoice_id = 1;

-- 11. Xác nhận thanh toán (Dùng số tiền vừa xem được ở bước 10)
-- Lưu ý: Nếu điền sai số tiền thấp hơn total_amount, Procedure sẽ chặn lại [cite: 397]
CALL sp_confirm_payment(1, 230000, 'cash', 'CASH_DIRECT', 3); -- Thay 230000 bằng số thực tế bạn thấy

-- ============================================================================
-- KỊCH BẢN 5: KIỂM TRA DASHBOARD CUỐI CÙNG
-- ============================================================================
SELECT * FROM vw_dashboard_summary;
SELECT * FROM vw_top_menu_items;
