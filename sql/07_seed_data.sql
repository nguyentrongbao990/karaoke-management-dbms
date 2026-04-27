-- 07_seed_data.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Khởi tạo dữ liệu mẫu phục vụ kiểm thử và demo

-- ============================================================================
-- 1. Vai trò
-- ============================================================================

INSERT INTO roles (role_name, description) VALUES
('Quản lý', 'Quản trị và theo dõi toàn bộ hệ thống'),
('Lễ tân', 'Tiếp nhận đặt phòng và check-in'),
('Thu ngân', 'Lập hóa đơn và xác nhận thanh toán'),
('Phục vụ', 'Ghi nhận gọi món trong phòng hát'),
('Kỹ thuật', 'Theo dõi tình trạng phòng và thiết bị');


-- ============================================================================
-- 2. Nhân viên
-- ============================================================================

INSERT INTO employees (full_name, phone, email, role_id, hire_date) VALUES
('Trần Quản Lý', '0999888777', 'admin@karaoke.com', 1, '2025-01-01'),
('Nguyễn Lễ Tân', '0901234014', 'letan@karaoke.com', 2, '2025-01-15'),
('Lê Thu Ngân', '0911222333', 'thungan@karaoke.com', 3, '2025-01-15'),
('Phạm Phục Vụ', '0922333444', 'phucvu@karaoke.com', 4, '2025-02-01'),
('Đỗ Kỹ Thuật', '0933444555', 'kythuat@karaoke.com', 5, '2025-02-10');


-- ============================================================================
-- 3. Tài khoản đăng nhập mẫu
-- Lưu ý: password_hash chỉ là dữ liệu demo, không dùng cho production.
-- ============================================================================

INSERT INTO accounts (employee_id, username, password_hash) VALUES
(1, 'admin', 'demo_hash_admin'),
(2, 'letan', 'demo_hash_letan'),
(3, 'thungan', 'demo_hash_thungan'),
(4, 'phucvu', 'demo_hash_phucvu'),
(5, 'kythuat', 'demo_hash_kythuat');


-- ============================================================================
-- 4. Loại phòng và phòng
-- ============================================================================

INSERT INTO room_types (room_type_name, description, max_capacity, hourly_rate) VALUES
('Thường', 'Phòng tiêu chuẩn cho nhóm nhỏ', 10, 150000),
('VIP', 'Phòng chất lượng cao, âm thanh tốt', 15, 300000),
('Party', 'Phòng lớn cho nhóm đông người', 30, 500000),
('Couple', 'Phòng nhỏ cho nhóm ít người', 5, 120000);

INSERT INTO rooms (room_code, room_name, room_type_id, floor_no, actual_capacity, status) VALUES
('P101', 'Phòng 101', 1, 1, 10, 'available'),
('P102', 'Phòng 102', 1, 1, 10, 'available'),
('P103', 'Phòng 103', 4, 1, 5, 'available'),
('P201', 'Phòng 201 VIP', 2, 2, 15, 'available'),
('P202', 'Phòng 202 VIP', 2, 2, 15, 'available'),
('P301', 'Phòng 301 Party', 3, 3, 30, 'available'),
('P302', 'Phòng 302 Party', 3, 3, 30, 'available'),
('P401', 'Phòng 401 Bảo trì', 2, 4, 15, 'maintenance');


-- ============================================================================
-- 5. Cơ sở vật chất
-- ============================================================================

INSERT INTO facilities (facility_name, default_unit, description) VALUES
('Micro không dây', 'cái', 'Micro dùng trong phòng hát'),
('Loa', 'cái', 'Loa âm thanh'),
('TV màn hình lớn', 'cái', 'Màn hình hiển thị bài hát'),
('Điều hòa', 'cái', 'Thiết bị làm mát'),
('Đèn LED', 'bộ', 'Hệ thống đèn trang trí');

INSERT INTO room_facilities (room_id, facility_id, quantity, condition_status, issue_note) VALUES
(1, 1, 2, 'good', NULL),
(1, 2, 2, 'good', NULL),
(1, 3, 1, 'good', NULL),
(1, 4, 1, 'good', NULL),
(2, 1, 2, 'good', NULL),
(2, 2, 2, 'good', NULL),
(3, 1, 2, 'good', NULL),
(4, 1, 4, 'good', NULL),
(4, 2, 4, 'good', NULL),
(4, 3, 1, 'good', NULL),
(5, 1, 4, 'good', NULL),
(6, 1, 6, 'good', NULL),
(6, 2, 6, 'good', NULL),
(6, 5, 2, 'good', NULL),
(8, 1, 4, 'repairing', 'Đang kiểm tra micro');


-- ============================================================================
-- 6. Khách hàng
-- ============================================================================

INSERT INTO customers (full_name, phone, email, customer_type, note) VALUES
('Kevin Nguyễn', '0988123014', 'kevin@example.com', 'vip', 'Khách quen'),
('Tyson Ngô', '0909999888', 'tyson@example.com', 'regular', NULL),
('Minh Anh', '0912345678', 'minhanh@example.com', 'loyal', NULL),
('Hoàng Nam', '0934567890', 'hoangnam@example.com', 'regular', NULL),
('Lan Phương', '0977777888', 'lanphuong@example.com', 'vip', 'Hay đặt phòng VIP');


-- ============================================================================
-- 7. Danh mục món và món bán
-- ============================================================================

INSERT INTO menu_categories (category_name, description) VALUES
('Bia', 'Các loại bia lon/chai'),
('Nước ngọt', 'Nước ngọt, nước suối'),
('Đồ ăn', 'Đồ ăn nhẹ'),
('Trái cây', 'Trái cây theo đĩa'),
('Khác', 'Dịch vụ khác');

INSERT INTO menu_items (item_name, category_id, unit, sale_price, stock_quantity) VALUES
('Bia Tiger Bạc', 1, 'lon', 30000, 300),
('Bia Heineken', 1, 'lon', 35000, 200),
('Coca Cola', 2, 'lon', 20000, 180),
('Pepsi', 2, 'lon', 20000, 160),
('Nước suối', 2, 'chai', 10000, 250),
('Khô gà lá chanh', 3, 'đĩa', 80000, 50),
('Khoai tây chiên', 3, 'đĩa', 70000, 45),
('Trái cây tổng hợp', 4, 'đĩa', 150000, 30),
('Hạt hướng dương', 3, 'đĩa', 50000, 60),
('Khăn lạnh', 5, 'cái', 5000, 500);


-- ============================================================================
-- 8. Loại phụ thu
-- ============================================================================

INSERT INTO surcharge_types (surcharge_name, default_amount, description) VALUES
('Vỡ ly thủy tinh', 50000, 'Phụ thu khi khách làm vỡ ly'),
('Phí vệ sinh nặng', 200000, 'Phụ thu khi cần vệ sinh đặc biệt'),
('Mang đồ uống ngoài vào', 100000, 'Phụ thu khi khách mang đồ uống từ ngoài vào'),
('Hư hỏng micro', NULL, 'Phụ thu theo giá trị hư hỏng thực tế'),
('Hư hỏng thiết bị khác', NULL, 'Phụ thu tùy tình huống');
