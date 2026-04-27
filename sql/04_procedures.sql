-- 04_procedures_FIXED_V2.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Thực hiện các nghiệp vụ thay đổi dữ liệu với kiểm tra bảo mật nghiêm ngặt

-- 1. Tạo phiếu đặt phòng mới
CREATE OR REPLACE PROCEDURE sp_create_booking(
    p_booking_code VARCHAR(30),
    p_customer_id BIGINT,
    p_room_id BIGINT,
    p_employee_id BIGINT,
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    p_guest_count INT,
    p_note TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT fn_is_room_available(p_room_id, p_start_time, p_end_time) THEN
        RAISE EXCEPTION 'Phòng không khả dụng hoặc đang bảo trì.';
    END IF;

    IF p_guest_count > (SELECT actual_capacity FROM rooms WHERE room_id = p_room_id) THEN
        RAISE EXCEPTION 'Số khách vượt quá sức chứa của phòng.';
    END IF;

    INSERT INTO bookings (
        booking_code, customer_id, room_id, created_by_employee_id,
        expected_start_time, expected_end_time, guest_count, status, note
    ) VALUES (
        p_booking_code, p_customer_id, p_room_id, p_employee_id,
        p_start_time, p_end_time, p_guest_count, 'confirmed', p_note
    );
END;
$$;

-- 2. Hủy đặt phòng
CREATE OR REPLACE PROCEDURE sp_cancel_booking(p_booking_id BIGINT, p_note TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT status FROM bookings WHERE booking_id = p_booking_id) NOT IN ('pending', 'confirmed') THEN
        RAISE EXCEPTION 'Chỉ có thể hủy đặt phòng ở trạng thái chờ hoặc đã xác nhận.';
    END IF;

    UPDATE bookings SET status = 'cancelled', note = COALESCE(note, '') || ' | Hủy: ' || p_note 
    WHERE booking_id = p_booking_id;
END;
$$;

-- 3. Xử lý khách nhận phòng (Check-in)
CREATE OR REPLACE PROCEDURE sp_check_in_booking(
    p_booking_id BIGINT,
    p_employee_id BIGINT,
    p_guest_count_actual INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_room_id BIGINT;
    v_capacity INT;
    v_status VARCHAR;
    v_booking_status VARCHAR;
BEGIN
    SELECT room_id, status INTO v_room_id, v_booking_status FROM bookings WHERE booking_id = p_booking_id;
    IF v_room_id IS NULL THEN RAISE EXCEPTION 'Booking không tồn tại.'; END IF;
    IF v_booking_status <> 'confirmed' THEN RAISE EXCEPTION 'Chỉ booking đã xác nhận mới được check-in.'; END IF;

    SELECT status, actual_capacity INTO v_status, v_capacity FROM rooms WHERE room_id = v_room_id;
    IF v_status <> 'available' AND v_status <> 'reserved' THEN RAISE EXCEPTION 'Phòng không sẵn sàng (Đang có khách hoặc bảo trì).'; END IF;
    IF p_guest_count_actual > v_capacity THEN RAISE EXCEPTION 'Số khách thực tế (%) vượt sức chứa phòng (%).', p_guest_count_actual, v_capacity; END IF;

    INSERT INTO room_sessions (booking_id, room_id, checked_in_by_employee_id, actual_start_time, guest_count_actual, session_status)
    VALUES (p_booking_id, v_room_id, p_employee_id, CURRENT_TIMESTAMP, p_guest_count_actual, 'active');

    UPDATE bookings SET status = 'checked_in' WHERE booking_id = p_booking_id;
    UPDATE rooms SET status = 'occupied' WHERE room_id = v_room_id;
END;
$$;

-- 4. Đổi phòng khi đang sử dụng (ĐÃ FIX LỖI KHAI BÁO BIẾN v_status)
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
    v_guest_count INT;
    v_status VARCHAR; -- BỔ SUNG BIẾN NÀY ĐỂ FIX LỖI
    v_new_capacity INT;
    v_new_session_id BIGINT;
BEGIN
    SELECT session_id, room_id, guest_count_actual INTO v_old_session_id, v_from_room_id, v_guest_count
    FROM room_sessions WHERE booking_id = p_booking_id AND session_status = 'active';

    IF v_old_session_id IS NULL THEN RAISE EXCEPTION 'Không có phiên hát nào đang hoạt động.'; END IF;
    IF v_from_room_id = p_to_room_id THEN RAISE EXCEPTION 'Không thể đổi sang chính phòng hiện tại.'; END IF;

    -- Kiểm tra phòng mới
    SELECT status, actual_capacity INTO v_status, v_new_capacity FROM rooms WHERE room_id = p_to_room_id;
    IF v_status <> 'available' THEN RAISE EXCEPTION 'Phòng mới không trống.'; END IF;
    IF v_guest_count > v_new_capacity THEN RAISE EXCEPTION 'Phòng mới không đủ sức chứa cho % khách.', v_guest_count; END IF;

    UPDATE room_sessions SET actual_end_time = CURRENT_TIMESTAMP, session_status = 'transferred' WHERE session_id = v_old_session_id;

    INSERT INTO room_sessions (booking_id, room_id, checked_in_by_employee_id, actual_start_time, guest_count_actual, session_status)
    VALUES (p_booking_id, p_to_room_id, p_employee_id, CURRENT_TIMESTAMP, v_guest_count, 'active')
    RETURNING session_id INTO v_new_session_id;

    UPDATE rooms SET status = 'available' WHERE room_id = v_from_room_id;
    UPDATE rooms SET status = 'occupied' WHERE room_id = p_to_room_id;

    INSERT INTO room_transfers (booking_id, from_session_id, to_session_id, transfer_time, reason, approved_by_employee_id)
    VALUES (p_booking_id, v_old_session_id, v_new_session_id, CURRENT_TIMESTAMP, p_reason, p_employee_id);
END;
$$;

-- 5. Xác nhận đơn gọi món (Trừ kho)
CREATE OR REPLACE PROCEDURE sp_confirm_service_order(p_service_order_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE r_item RECORD;
BEGIN
    IF (SELECT order_status FROM service_orders WHERE service_order_id = p_service_order_id) <> 'draft' THEN
        RAISE EXCEPTION 'Đơn đã xác nhận hoặc đã hủy.';
    END IF;

    FOR r_item IN SELECT item_id, quantity FROM service_order_items WHERE service_order_id = p_service_order_id LOOP
        IF (SELECT stock_quantity FROM menu_items WHERE item_id = r_item.item_id) < r_item.quantity THEN
            RAISE EXCEPTION 'Hết hàng.';
        END IF;
    END LOOP;

    UPDATE menu_items m SET stock_quantity = m.stock_quantity - soi.quantity
    FROM service_order_items soi WHERE m.item_id = soi.item_id AND soi.service_order_id = p_service_order_id;

    UPDATE service_orders SET order_status = 'confirmed' WHERE service_order_id = p_service_order_id;
END;
$$;

-- 6. Hủy đơn gọi món (Hoàn kho)
CREATE OR REPLACE PROCEDURE sp_cancel_service_order(p_service_order_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
BEGIN
    SELECT order_status INTO v_status FROM service_orders WHERE service_order_id = p_service_order_id;
    
    IF v_status = 'confirmed' THEN
        UPDATE menu_items m SET stock_quantity = m.stock_quantity + soi.quantity
        FROM service_order_items soi WHERE m.item_id = soi.item_id AND soi.service_order_id = p_service_order_id;
    END IF;

    UPDATE service_orders SET order_status = 'cancelled' WHERE service_order_id = p_service_order_id;
END;
$$;

-- 7. Thêm phụ thu và tự động cập nhật tổng tiền
CREATE OR REPLACE PROCEDURE sp_add_invoice_surcharge(
    p_invoice_id BIGINT,
    p_surcharge_type_id BIGINT,
    p_quantity INT,
    p_employee_id BIGINT,
    p_note TEXT
)
LANGUAGE plpgsql AS $$
DECLARE v_unit_price NUMERIC;
BEGIN
    IF (SELECT invoice_status FROM invoices WHERE invoice_id = p_invoice_id) <> 'unpaid' THEN
        RAISE EXCEPTION 'Hóa đơn đã thanh toán hoặc đã hủy, không thể thêm phụ thu.';
    END IF;

    SELECT default_amount INTO v_unit_price FROM surcharge_types WHERE surcharge_type_id = p_surcharge_type_id;

    INSERT INTO invoice_surcharges (invoice_id, surcharge_type_id, quantity, unit_amount, recorded_by_employee_id, note)
    VALUES (p_invoice_id, p_surcharge_type_id, p_quantity, v_unit_price, p_employee_id, p_note);
END;
$$;

-- 8. Check-out và lập hóa đơn
CREATE OR REPLACE PROCEDURE sp_check_out_booking(
    p_booking_id BIGINT,
    p_employee_id BIGINT,
    p_discount_amount NUMERIC(12,2),
    p_invoice_number VARCHAR(30)
)
LANGUAGE plpgsql AS $$
DECLARE
    v_session_id BIGINT; v_room_id BIGINT;
    v_room_charge NUMERIC; v_service_charge NUMERIC; v_total NUMERIC;
BEGIN
    SELECT session_id, room_id INTO v_session_id, v_room_id
    FROM room_sessions WHERE booking_id = p_booking_id AND session_status = 'active';

    IF v_session_id IS NULL THEN RAISE EXCEPTION 'Không có session active.'; END IF;

    UPDATE room_sessions SET actual_end_time = CURRENT_TIMESTAMP, session_status = 'completed' WHERE session_id = v_session_id;
    UPDATE rooms SET status = 'available' WHERE room_id = v_room_id;

    v_room_charge := fn_calculate_room_charge(p_booking_id);
    v_service_charge := fn_calculate_service_charge(p_booking_id);
    v_total := fn_calculate_invoice_total(v_room_charge, v_service_charge, 0, p_discount_amount);

    INSERT INTO invoices (invoice_number, booking_id, created_by_employee_id, room_charge, service_charge, discount_amount, total_amount, invoice_status)
    VALUES (p_invoice_number, p_booking_id, p_employee_id, v_room_charge, v_service_charge, p_discount_amount, v_total, 'unpaid');

    UPDATE bookings SET status = 'completed' WHERE booking_id = p_booking_id;
END;
$$;

-- 9. Xác nhận thanh toán (Kiểm tra nghiêm ngặt)
CREATE OR REPLACE PROCEDURE sp_confirm_payment(
    p_invoice_id BIGINT,
    p_amount_paid NUMERIC(12,2),
    p_method VARCHAR(20),
    p_reference VARCHAR(100),
    p_employee_id BIGINT
)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR; v_total NUMERIC;
BEGIN
    SELECT invoice_status, total_amount INTO v_status, v_total FROM invoices WHERE invoice_id = p_invoice_id;
    
    IF v_status IS NULL THEN RAISE EXCEPTION 'Hóa đơn không tồn tại.'; END IF;
    IF v_status <> 'unpaid' THEN RAISE EXCEPTION 'Hóa đơn đã được thanh toán hoặc bị hủy.'; END IF;
    IF p_amount_paid < v_total THEN RAISE EXCEPTION 'Số tiền thanh toán (%) không đủ (Cần %).', p_amount_paid, v_total; END IF;

    INSERT INTO payments (invoice_id, amount_paid, payment_method, transaction_reference, received_by_employee_id, payment_status)
    VALUES (p_invoice_id, p_amount_paid, p_method, p_reference, p_employee_id, 'successful');

    UPDATE invoices SET invoice_status = 'paid' WHERE invoice_id = p_invoice_id;
END;
$$;
