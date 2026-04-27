-- 07_seed_data_FIXED.sql
-- Khởi tạo dữ liệu mẫu nhất quán với nghiệp vụ

-- 1. Vai trò & Nhân viên
INSERT INTO roles (role_name) VALUES ('Quản lý'), ('Lễ tân'), ('Thu ngân'), ('Phục vụ');

INSERT INTO employees (full_name, phone, email, role_id, hire_date) VALUES
('Trần Quản Lý', '0999888777', 'admin@karaoke.com', 1, '2025-01-01'),
('Nguyễn Lễ Tân', '0901234014', 'letan@karaoke.com', 2, '2025-01-15'),
('Lê Thu Ngân', '0911222333', 'thungan@karaoke.com', 3, '2025-01-15');

-- 2. Loại phòng & Phòng (Đã sửa lỗi sức chứa mâu thuẫn) [cite: 454-459]
INSERT INTO room_types (room_type_name, max_capacity, hourly_rate) VALUES
('Thường (Standard)', 10, 150000), -- Sức chứa tối đa 10
('VIP', 15, 300000),
('Party', 30, 500000);            -- Sức chứa tối đa 30

INSERT INTO rooms (room_code, room_name, room_type_id, floor_no, actual_capacity) VALUES
('P101', 'Phòng 101', 1, 1, 10),
('P102', 'Phòng 102', 1, 1, 10), -- Fix: Giảm từ 12 xuống 10 cho khớp loại phòng [cite: 455]
('P201', 'Phòng 201 (VIP)', 2, 2, 15),
('P301', 'Phòng 301 (Party)', 3, 3, 30); -- Fix: Giảm từ 35 xuống 30 cho khớp loại phòng [cite: 458]

-- 3. Khách hàng & Menu
INSERT INTO customers (full_name, phone, customer_type) VALUES
('Kevin Nguyễn', '0988123014', 'vip'),
('Tyson Ngô', '0909999888', 'regular');

INSERT INTO menu_categories (category_name) VALUES ('Bia'), ('Đồ ăn');

INSERT INTO menu_items (item_name, category_id, unit, sale_price, stock_quantity) VALUES
('Bia Tiger Bạc', 1, 'lon', 30000, 300),
('Khô gà lá chanh', 2, 'đĩa', 80000, 50);

-- 4. Phụ thu
INSERT INTO surcharge_types (surcharge_name, default_amount) VALUES
('Vỡ ly thủy tinh', 50000),
('Phí vệ sinh nặng', 200000);
