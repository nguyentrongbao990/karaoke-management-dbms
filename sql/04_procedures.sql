-- 04_procedures.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Thực hiện các nghiệp vụ thay đổi dữ liệu nhiều bước

-- 1. Tạo phiếu đặt phòng mới [cite: 1111-1120]
CREATE OR REPLACE PROCEDURE sp_create_booking(
    p_booking_code VARCHAR(30),
    p_customer_id BIGINT,
    p_room_id BIGINT,
    p_employee_id BIGINT,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_guest_count INT,
    p_note TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Kiểm tra phòng có sẵn trong khung giờ đó không [cite: 1118]
    IF NOT fn_is_room_available(p_room_id, p_start_time, p_end_time) THEN
        RAISE EXCEPTION 'Phòng không khả dụng trong khoảng thời gian này hoặc đang bảo trì.';
    END IF;

    -- Kiểm tra sức chứa [cite: 1117]
    IF p_guest_count > (SELECT actual_capacity FROM rooms WHERE room_id = p_room_id) THEN
        RAISE EXCEPTION 'Số khách vượt quá sức chứa thực tế của phòng.';
    END IF;

    -- Tạo booking [cite: 1119]
    INSERT INTO bookings (
        booking_code, customer_id, room_id, created_by_employee_id,
        expected_start_time, expected_end_time, guest_count, status, note
    ) VALUES (
        p_booking_code, p_customer_id, p_room_id, p_employee_id,
        p_start_time, p_end_time, p_guest_count, 'confirmed', p_note
    );
END;
$$;

-- 2. Xử lý khách nhận phòng (Check-in) [cite: 1129-1138]
CREATE OR REPLACE PROCEDURE sp_check_in_booking(
    p_booking_id BIGINT,
    p_employee_id BIGINT,
    p_guest_count_actual INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_room_id BIGINT;
BEGIN
    SELECT room_id INTO v_room_id FROM bookings WHERE booking_id = p_booking_id;

    -- Kiểm tra trạng thái phòng hiện tại [cite: 1133]
    IF (SELECT status FROM rooms WHERE room_id = v_room_id) <> 'available' THEN
        -- Nếu là reserved thì vẫn cho vào, nếu occupied thì chặn
        IF (SELECT status FROM rooms WHERE room_id = v_room_id) = 'occupied' THEN
            RAISE EXCEPTION 'Phòng hiện đang có khách, không thể check-in.';
        END IF;
    END IF;

    -- Tạo phiên sử dụng phòng thực tế [cite: 1135]
    INSERT INTO room_sessions (
        booking_id, room_id, checked_in_by_employee_id,
        actual_start_time, guest_count_actual, session_status
    ) VALUES (
        p_booking_id, v_room_id, p_employee_id,
        CURRENT_TIMESTAMP, p_guest_count_actual, 'active'
    );

    -- Cập nhật trạng thái [cite: 1136-1137]
    UPDATE bookings SET status = 'checked_in' WHERE booking_id = p_booking_id;
    UPDATE rooms SET status = 'occupied' WHERE room_id = v_room_id;
END;
$$;

-- 3. Xử lý đổi phòng khi đang sử dụng [cite: 1139-1149]
CREATE OR REPLACE PROCEDURE sp_transfer_room(
    p_booking_id BIGINT,
    p_to_room_id BIGINT,
    p_employee_id BIGINT,
    p_reason TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_session_id BIGINT;
    v_from_room_id BIGINT;
    v_new_session_id BIGINT;
BEGIN
    -- Tìm session đang hoạt động [cite: 1142]
    SELECT session_id, room_id INTO v_old_session_id, v_from_room_id
    FROM room_sessions 
    WHERE booking_id = p_booking_id AND session_status = 'active';

    IF v_old_session_id IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy phiên sử dụng nào đang hoạt động cho booking này.';
    END IF;

    -- Kiểm tra phòng mới [cite: 1143-1144]
    IF (SELECT status FROM rooms WHERE room_id = p_to_room_id) <> 'available' THEN
        RAISE EXCEPTION 'Phòng mới không sẵn sàng.';
    END IF;

    -- 1. Đóng session cũ [cite: 1145]
    UPDATE room_sessions 
    SET actual_end_time = CURRENT_TIMESTAMP, session_status = 'transferred'
    WHERE session_id = v_old_session_id;

    -- 2. Tạo session mới [cite: 1146]
    INSERT INTO room_sessions (
        booking_id, room_id, checked_in_by_employee_id,
        actual_start_time, session_status
    ) VALUES (
        p_booking_id, p_to_room_id, p_employee_id,
        CURRENT_TIMESTAMP, 'active'
    ) RETURNING session_id INTO v_new_session_id;

    -- 3. Cập nhật trạng thái các phòng [cite: 1147]
    UPDATE rooms SET status = 'available' WHERE room_id = v_from_room_id;
    UPDATE rooms SET status = 'occupied' WHERE room_id = p_to_room_id;

    -- 4. Ghi nhận lịch sử đổi phòng [cite: 1148]
    INSERT INTO room_transfers (
        booking_id, from_session_id, to_session_id, transfer_time, reason, approved_by_employee_id
    ) VALUES (
        p_booking_id, v_old_session_id, v_new_session_id, CURRENT_TIMESTAMP, p_reason, p_employee_id
    );
END;
$$;

-- 4. Xác nhận đơn gọi món và trừ tồn kho [cite: 1150-1158]
CREATE OR REPLACE PROCEDURE sp_confirm_service_order(p_service_order_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE
    r_item RECORD;
BEGIN
    -- Kiểm tra trạng thái đơn [cite: 1153]
    IF (SELECT order_status FROM service_orders WHERE service_order_id = p_service_order_id) <> 'draft' THEN
        RAISE EXCEPTION 'Đơn đã được xác nhận hoặc đã hủy trước đó.';
    END IF;

    -- Kiểm tra tồn kho cho tất cả các món trong đơn [cite: 1154]
    FOR r_item IN SELECT item_id, quantity FROM service_order_items WHERE service_order_id = p_service_order_id
    LOOP
        IF (SELECT stock_quantity FROM menu_items WHERE item_id = r_item.item_id) < r_item.quantity THEN
            RAISE EXCEPTION 'Món % không đủ số lượng trong kho.', (SELECT item_name FROM menu_items WHERE item_id = r_item.item_id);
        END IF;
    END LOOP;

    -- Thực hiện trừ kho và cập nhật trạng thái đơn [cite: 1155-1156]
    UPDATE menu_items m
    SET stock_quantity = m.stock_quantity - soi.quantity
    FROM service_order_items soi
    WHERE m.item_id = soi.item_id AND soi.service_order_id = p_service_order_id;

    UPDATE service_orders SET order_status = 'confirmed' WHERE service_order_id = p_service_order_id;
END;
$$;

-- 5. Kết thúc sử dụng phòng và lập hóa đơn tạm (Check-out) [cite: 1176-1189]
CREATE OR REPLACE PROCEDURE sp_check_out_booking(
    p_booking_id BIGINT,
    p_employee_id BIGINT,
    p_discount_amount NUMERIC(12,2),
    p_invoice_number VARCHAR(30)
)
LANGUAGE plpgsql AS $$
DECLARE
    v_session_id BIGINT;
    v_room_id BIGINT;
    v_room_charge NUMERIC(12,2);
    v_service_charge NUMERIC(12,2);
    v_total NUMERIC(12,2);
BEGIN
    -- 1. Tìm và đóng session đang active [cite: 1179-1181]
    SELECT session_id, room_id INTO v_session_id, v_room_id
    FROM room_sessions 
    WHERE booking_id = p_booking_id AND session_status = 'active';

    IF v_session_id IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy phiên sử dụng đang hoạt động.';
    END IF;

    UPDATE room_sessions 
    SET actual_end_time = CURRENT_TIMESTAMP, session_status = 'completed'
    WHERE session_id = v_session_id;

    -- 2. Giải phóng phòng [cite: 1182]
    UPDATE rooms SET status = 'available' WHERE room_id = v_room_id;

    -- 3. Tính toán các khoản tiền [cite: 1183-1185]
    v_room_charge := fn_calculate_room_charge(p_booking_id);
    v_service_charge := fn_calculate_service_charge(p_booking_id);
    -- Tổng tạm tính (chưa có phụ thu, phụ thu sẽ cộng sau qua trigger/view)
    v_total := fn_calculate_invoice_total(v_room_charge, v_service_charge, 0, p_discount_amount);

    -- 4. Tạo hóa đơn [cite: 1186-1187]
    INSERT INTO invoices (
        invoice_number, booking_id, created_by_employee_id,
        room_charge, service_charge, discount_amount, total_amount, invoice_status
    ) VALUES (
        p_invoice_number, p_booking_id, p_employee_id,
        v_room_charge, v_service_charge, p_discount_amount, v_total, 'unpaid'
    );

    -- 5. Hoàn thành booking [cite: 1188]
    UPDATE bookings SET status = 'completed' WHERE booking_id = p_booking_id;
END;
$$;

-- 6. Xác nhận thanh toán hóa đơn [cite: 1190-1197]
CREATE OR REPLACE PROCEDURE sp_confirm_payment(
    p_invoice_id BIGINT,
    p_amount_paid NUMERIC(12,2),
    p_method VARCHAR(20),
    p_reference VARCHAR(100),
    p_employee_id BIGINT
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Tạo bản ghi thanh toán [cite: 1195]
    INSERT INTO payments (
        invoice_id, amount_paid, payment_method, transaction_reference,
        received_by_employee_id, payment_status
    ) VALUES (
        p_invoice_id, p_amount_paid, p_method, p_reference,
        p_employee_id, 'successful'
    );

    -- Chốt hóa đơn [cite: 1196]
    UPDATE invoices SET invoice_status = 'paid' WHERE invoice_id = p_invoice_id;
END;
$$;
