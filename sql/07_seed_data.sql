-- 07_seed_data.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Khởi tạo dữ liệu danh mục mẫu (Master Data) để test hệ thống

-- ============================================================================
-- 1. THÊM DỮ LIỆU VAI TRÒ & NHÂN VIÊN
-- ============================================================================
INSERT INTO roles (role_name, description) VALUES
('Quản lý', 'Toàn quyền kiểm soát hệ thống'),
('Lễ tân', 'Tiếp đón khách, đặt phòng, check-in/out'),
('Thu ngân', 'Chốt hóa đơn, thu tiền'),
('Phục vụ', 'Ghi nhận gọi món, bưng bê'),
('Kỹ thuật', 'Quản lý bảo trì thiết bị');

-- Giả định các role_id từ 1 đến 5 tương ứng như trên
INSERT INTO employees (full_name, phone, email, role_id, hire_date) VALUES
('Trần Quản Lý', '0999888777', 'admin@karaoke.com', 1, '2025-01-01'),
('Nguyễn Lễ Tân', '0901234014', 'letan@karaoke.com', 2, '2025-01-15'),
('Lê Thu Ngân', '0911222333', 'thungan@karaoke.com', 3, '2025-01-15'),
('Phạm Phục Vụ', '0944555666', 'phucvu@karaoke.com', 4, '2025-02-01');

-- Cấp tài khoản đăng nhập cho quản lý và lễ tân
INSERT INTO accounts (employee_id, username, password_hash) VALUES
(1, 'admin', 'hash_cua_mat_khau_admin_123'),
(2, 'letan1', 'hash_cua_mat_khau_letan_123');

-- ============================================================================
-- 2. THÊM DỮ LIỆU CƠ SỞ VẬT CHẤT & PHÒNG HÁT
-- ============================================================================
INSERT INTO room_types (room_type_name, description, max_capacity, hourly_rate) VALUES
('Thường (Standard)', 'Phòng tiêu chuẩn cho nhóm nhỏ', 10, 150000),
('VIP', 'Phòng VIP, cách âm tốt, đèn LED', 15, 300000),
('Super VIP (Party)', 'Phòng lớn tổ chức sinh nhật, sự kiện', 30, 500000);

-- Giả định room_type_id: 1=Thường, 2=VIP, 3=Party
INSERT INTO rooms (room_code, room_name, room_type_id, floor_no, actual_capacity, status) VALUES
('P101', 'Phòng 101', 1, 1, 10, 'available'),
('P102', 'Phòng 102', 1, 1, 12, 'available'),
('P201', 'Phòng 201 (VIP)', 2, 2, 15, 'available'),
('P301', 'Phòng 301 (Party)', 3, 3, 35, 'available');

INSERT INTO facilities (facility_name, default_unit, description) VALUES
('Micro không dây', 'cái', 'Micro chuẩn hát nhẹ'),
('Màn hình TV 65 inch', 'cái', 'Màn hình chọn bài'),
('Hệ thống loa JBL', 'bộ', 'Loa công suất lớn');

-- Thêm thiết bị cho phòng P201 (VIP)
INSERT INTO room_facilities (room_id, facility_id, quantity) VALUES
(3, 1, 4), -- 4 Micro
(3, 2, 2), -- 2 TV
(3, 3, 1); -- 1 Dàn loa

-- ============================================================================
-- 3. THÊM DỮ LIỆU KHÁCH HÀNG
-- ============================================================================
INSERT INTO customers (full_name, phone, email, gender, customer_type, note) VALUES
('Kevin Nguyễn', '0988123014', 'kevin.n@email.com', 'male', 'vip', 'Khách quen thường đặt phòng VIP cuối tuần'),
('Tyson Ngô', '0909999888', 'tyson.vlr@email.com', 'male', 'regular', 'Thích uống nước tăng lực khi hát'),
('Lê Trần Trà My', '0977666555', 'tramy@email.com', 'female', 'loyal', '');

-- ============================================================================
-- 4. THÊM DỮ LIỆU DANH MỤC MENU & TỒN KHO
-- ============================================================================
INSERT INTO menu_categories (category_name, description) VALUES
('Bia & Rượu', 'Các loại đồ uống có cồn'),
('Nước ngọt', 'Nước giải khát có gas và không gas'),
('Đồ ăn vặt', 'Khô gà, bò khô, trái cây sấy...'),
('Trái cây', 'Trái cây tươi dọn theo đĩa/combo');

-- Giả định category_id: 1=Bia, 2=Nước ngọt, 3=Đồ ăn, 4=Trái cây
INSERT INTO menu_items (item_name, category_id, unit, sale_price, stock_quantity) VALUES
('Bia Heineken (Lon)', 1, 'lon', 35000, 200),
('Bia Tiger Bạc (Lon)', 1, 'lon', 30000, 300),
('Nước tăng lực Redbull', 2, 'lon', 25000, 100),
('Nước suối Dasani', 2, 'chai', 15000, 150),
('Khô gà lá chanh', 3, 'đĩa', 80000, 50),
('Trái cây thập cẩm (Lớn)', 4, 'đĩa', 250000, 20);

-- ============================================================================
-- 5. THÊM DỮ LIỆU DANH MỤC PHỤ THU
-- ============================================================================
INSERT INTO surcharge_types (surcharge_name, default_amount, description) VALUES
('Mang đồ uống từ ngoài', 150000, 'Phụ thu khi khách tự xách bia/rượu vào phòng'),
('Vỡ ly/cốc thủy tinh', 50000, 'Phí đền bù vỡ 1 ly/cốc'),
('Phí vệ sinh đặc biệt', 200000, 'Thu khi phòng bẩn nặng (bánh kem dính sàn, nôn trớ)');
