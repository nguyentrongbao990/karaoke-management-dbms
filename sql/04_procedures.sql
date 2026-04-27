-- 04_procedures.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Định nghĩa các procedure xử lý nghiệp vụ nhiều bước

-- ============================================================================
-- 1. Tạo phiếu đặt phòng mới
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_create_booking(
    p_booking_code VARCHAR(30),
    p_customer_id BIGINT,
    p_room_id BIGINT,
    p_employee_id BIGINT,
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    p_guest_count INT,
    p_note TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_capacity INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = p_customer_id) THEN
        RAISE EXCEPTION 'Khách hàng % không tồn tại.', p_customer_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Nhân viên % không tồn tại.', p_employee_id;
    END IF;

    SELECT actual_capacity
    INTO v_capacity
    FROM rooms
    WHERE room_id = p_room_id
      AND status NOT IN ('maintenance', 'inactive');

    IF v_capacity IS NULL THEN
        RAISE EXCEPTION 'Phòng không tồn tại hoặc đang bảo trì/ngừng hoạt động.';
    END IF;

    IF p_guest_count IS NULL OR p_guest_count <= 0 THEN
        RAISE EXCEPTION 'Số khách phải lớn hơn 0.';
    END IF;

    IF p_guest_count > v_capacity THEN
        RAISE EXCEPTION 'Số khách (%) vượt quá sức chứa phòng (%).', p_guest_count, v_capacity;
    END IF;

    IF NOT fn_is_room_available(p_room_id, p_start_time, p_end_time) THEN
        RAISE EXCEPTION 'Phòng không khả dụng trong khung giờ đã chọn.';
    END IF;

    INSERT INTO bookings (
        booking_code,
        customer_id,
        room_id,
        created_by_employee_id,
        expected_start_time,
        expected_end_time,
        guest_count,
        status,
        note
    )
    VALUES (
        p_booking_code,
        p_customer_id,
        p_room_id,
        p_employee_id,
        p_start_time,
        p_end_time,
        p_guest_count,
        'confirmed',
        p_note
    );
END;
$$;


-- ============================================================================
-- 2. Hủy phiếu đặt phòng
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_cancel_booking(
    p_booking_id BIGINT,
    p_note TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_room_id BIGINT;
BEGIN
    SELECT status, room_id
    INTO v_status, v_room_id
    FROM bookings
    WHERE booking_id = p_booking_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Booking % không tồn tại.', p_booking_id;
    END IF;

    IF v_status NOT IN ('pending', 'confirmed') THEN
        RAISE EXCEPTION 'Chỉ có thể hủy booking ở trạng thái pending hoặc confirmed.';
    END IF;

    UPDATE bookings
    SET status = 'cancelled',
        note = TRIM(BOTH ' ' FROM COALESCE(note, '') || ' | Hủy: ' || COALESCE(p_note, 'Không ghi chú'))
    WHERE booking_id = p_booking_id;

    IF EXISTS (
        SELECT 1
        FROM rooms
        WHERE room_id = v_room_id
          AND status = 'reserved'
    ) THEN
        UPDATE rooms
        SET status = 'available'
        WHERE room_id = v_room_id;
    END IF;
END;
$$;


-- ============================================================================
-- 3. Check-in booking
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_check_in_booking(
    p_booking_id BIGINT,
    p_employee_id BIGINT,
    p_guest_count_actual INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_room_id BIGINT;
    v_capacity INT;
    v_room_status VARCHAR;
    v_booking_status VARCHAR;
BEGIN
    IF p_guest_count_actual IS NULL OR p_guest_count_actual <= 0 THEN
        RAISE EXCEPTION 'Số khách thực tế phải lớn hơn 0.';
    END IF;

    SELECT room_id, status
    INTO v_room_id, v_booking_status
    FROM bookings
    WHERE booking_id = p_booking_id;

    IF v_room_id IS NULL THEN
        RAISE EXCEPTION 'Booking % không tồn tại.', p_booking_id;
    END IF;

    IF v_booking_status <> 'confirmed' THEN
        RAISE EXCEPTION 'Chỉ booking đã xác nhận mới được check-in.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Nhân viên % không tồn tại.', p_employee_id;
    END IF;

    SELECT status, actual_capacity
    INTO v_room_status, v_capacity
    FROM rooms
    WHERE room_id = v_room_id;

    IF v_room_status IS NULL THEN
        RAISE EXCEPTION 'Phòng của booking không tồn tại.';
    END IF;

    IF v_room_status NOT IN ('available', 'reserved') THEN
        RAISE EXCEPTION 'Phòng không sẵn sàng để check-in. Trạng thái hiện tại: %.', v_room_status;
    END IF;

    IF p_guest_count_actual > v_capacity THEN
        RAISE EXCEPTION 'Số khách thực tế (%) vượt sức chứa phòng (%).', p_guest_count_actual, v_capacity;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM room_sessions
        WHERE booking_id = p_booking_id
          AND session_status = 'active'
    ) THEN
        RAISE EXCEPTION 'Booking này đã có session đang hoạt động.';
    END IF;

    INSERT INTO room_sessions (
        booking_id,
        room_id,
        checked_in_by_employee_id,
        actual_start_time,
        guest_count_actual,
        session_status
    )
    VALUES (
        p_booking_id,
        v_room_id,
        p_employee_id,
        CURRENT_TIMESTAMP,
        p_guest_count_actual,
        'active'
    );

    UPDATE bookings
    SET status = 'checked_in'
    WHERE booking_id = p_booking_id;

    UPDATE rooms
    SET status = 'occupied'
    WHERE room_id = v_room_id;
END;
$$;


-- ============================================================================
-- 4. Đổi phòng
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_transfer_room(
    p_booking_id BIGINT,
    p_to_room_id BIGINT,
    p_employee_id BIGINT,
    p_reason TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_session_id BIGINT;
    v_from_room_id BIGINT;
    v_guest_count INT;
    v_new_room_status VARCHAR;
    v_new_capacity INT;
    v_new_session_id BIGINT;
BEGIN
    SELECT session_id, room_id, guest_count_actual
    INTO v_old_session_id, v_from_room_id, v_guest_count
    FROM room_sessions
    WHERE booking_id = p_booking_id
      AND session_status = 'active';

    IF v_old_session_id IS NULL THEN
        RAISE EXCEPTION 'Không có phiên hát active cho booking %.', p_booking_id;
    END IF;

    IF v_from_room_id = p_to_room_id THEN
        RAISE EXCEPTION 'Không thể đổi sang chính phòng hiện tại.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Nhân viên % không tồn tại.', p_employee_id;
    END IF;

    SELECT status, actual_capacity
    INTO v_new_room_status, v_new_capacity
    FROM rooms
    WHERE room_id = p_to_room_id;

    IF v_new_room_status IS NULL THEN
        RAISE EXCEPTION 'Phòng mới % không tồn tại.', p_to_room_id;
    END IF;

    IF v_new_room_status <> 'available' THEN
        RAISE EXCEPTION 'Phòng mới không trống. Trạng thái hiện tại: %.', v_new_room_status;
    END IF;

    IF v_guest_count > v_new_capacity THEN
        RAISE EXCEPTION 'Phòng mới không đủ sức chứa cho % khách.', v_guest_count;
    END IF;

    UPDATE room_sessions
    SET actual_end_time = CURRENT_TIMESTAMP,
        session_status = 'transferred'
    WHERE session_id = v_old_session_id;

    INSERT INTO room_sessions (
        booking_id,
        room_id,
        checked_in_by_employee_id,
        actual_start_time,
        guest_count_actual,
        session_status
    )
    VALUES (
        p_booking_id,
        p_to_room_id,
        p_employee_id,
        CURRENT_TIMESTAMP,
        v_guest_count,
        'active'
    )
    RETURNING session_id INTO v_new_session_id;

    UPDATE rooms
    SET status = 'available'
    WHERE room_id = v_from_room_id;

    UPDATE rooms
    SET status = 'occupied'
    WHERE room_id = p_to_room_id;

    INSERT INTO room_transfers (
        booking_id,
        from_session_id,
        to_session_id,
        transfer_time,
        reason,
        approved_by_employee_id
    )
    VALUES (
        p_booking_id,
        v_old_session_id,
        v_new_session_id,
        CURRENT_TIMESTAMP,
        p_reason,
        p_employee_id
    );
END;
$$;


-- ============================================================================
-- 5. Xác nhận đơn gọi món
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_confirm_service_order(
    p_service_order_id BIGINT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_session_status VARCHAR;
    r_item RECORD;
BEGIN
    SELECT so.order_status, rs.session_status
    INTO v_status, v_session_status
    FROM service_orders so
    JOIN room_sessions rs ON so.session_id = rs.session_id
    WHERE so.service_order_id = p_service_order_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Đơn gọi món % không tồn tại.', p_service_order_id;
    END IF;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Chỉ có thể xác nhận đơn gọi món ở trạng thái draft.';
    END IF;

    IF v_session_status <> 'active' THEN
        RAISE EXCEPTION 'Chỉ được xác nhận đơn gọi món cho session đang active.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM service_order_items
        WHERE service_order_id = p_service_order_id
    ) THEN
        RAISE EXCEPTION 'Không thể xác nhận đơn gọi món rỗng.';
    END IF;

    FOR r_item IN
        SELECT soi.item_id, soi.quantity, mi.stock_quantity, mi.is_active, mi.item_name
        FROM service_order_items soi
        JOIN menu_items mi ON soi.item_id = mi.item_id
        WHERE soi.service_order_id = p_service_order_id
    LOOP
        IF NOT r_item.is_active THEN
            RAISE EXCEPTION 'Món % hiện không còn kinh doanh.', r_item.item_name;
        END IF;

        IF r_item.stock_quantity < r_item.quantity THEN
            RAISE EXCEPTION 'Món % không đủ tồn kho. Còn %, cần %.',
                r_item.item_name, r_item.stock_quantity, r_item.quantity;
        END IF;
    END LOOP;

    UPDATE menu_items mi
    SET stock_quantity = mi.stock_quantity - soi.quantity
    FROM service_order_items soi
    WHERE mi.item_id = soi.item_id
      AND soi.service_order_id = p_service_order_id;

    UPDATE service_orders
    SET order_status = 'confirmed'
    WHERE service_order_id = p_service_order_id;
END;
$$;


-- ============================================================================
-- 6. Hủy đơn gọi món
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_cancel_service_order(
    p_service_order_id BIGINT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT order_status
    INTO v_status
    FROM service_orders
    WHERE service_order_id = p_service_order_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Đơn gọi món % không tồn tại.', p_service_order_id;
    END IF;

    IF v_status = 'cancelled' THEN
        RAISE EXCEPTION 'Đơn gọi món đã bị hủy trước đó.';
    END IF;

    IF v_status = 'confirmed' THEN
        UPDATE menu_items mi
        SET stock_quantity = mi.stock_quantity + soi.quantity
        FROM service_order_items soi
        WHERE mi.item_id = soi.item_id
          AND soi.service_order_id = p_service_order_id;
    END IF;

    UPDATE service_orders
    SET order_status = 'cancelled'
    WHERE service_order_id = p_service_order_id;
END;
$$;


-- ============================================================================
-- 7. Thêm phụ thu vào hóa đơn
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_add_invoice_surcharge(
    p_invoice_id BIGINT,
    p_surcharge_type_id BIGINT,
    p_quantity INT,
    p_employee_id BIGINT,
    p_note TEXT DEFAULT NULL,
    p_unit_amount NUMERIC(12,2) DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_invoice_status VARCHAR;
    v_default_amount NUMERIC(12,2);
    v_unit_amount NUMERIC(12,2);
BEGIN
    SELECT invoice_status
    INTO v_invoice_status
    FROM invoices
    WHERE invoice_id = p_invoice_id;

    IF v_invoice_status IS NULL THEN
        RAISE EXCEPTION 'Hóa đơn % không tồn tại.', p_invoice_id;
    END IF;

    IF v_invoice_status NOT IN ('draft', 'unpaid') THEN
        RAISE EXCEPTION 'Chỉ có thể thêm phụ thu cho hóa đơn draft hoặc unpaid.';
    END IF;

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Số lượng phụ thu phải lớn hơn 0.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Nhân viên % không tồn tại.', p_employee_id;
    END IF;

    SELECT default_amount
    INTO v_default_amount
    FROM surcharge_types
    WHERE surcharge_type_id = p_surcharge_type_id
      AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loại phụ thu % không tồn tại hoặc đã ngừng áp dụng.', p_surcharge_type_id;
    END IF;

    v_unit_amount := COALESCE(p_unit_amount, v_default_amount);

    IF v_unit_amount IS NULL THEN
        RAISE EXCEPTION 'Loại phụ thu này chưa có mức phí mặc định. Vui lòng truyền p_unit_amount.';
    END IF;

    IF v_unit_amount < 0 THEN
        RAISE EXCEPTION 'Đơn giá phụ thu không được âm.';
    END IF;

    INSERT INTO invoice_surcharges (
        invoice_id,
        surcharge_type_id,
        quantity,
        unit_amount,
        recorded_by_employee_id,
        note
    )
    VALUES (
        p_invoice_id,
        p_surcharge_type_id,
        p_quantity,
        v_unit_amount,
        p_employee_id,
        p_note
    );
END;
$$;


-- ============================================================================
-- 8. Check-out và lập hóa đơn
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_check_out_booking(
    p_booking_id BIGINT,
    p_employee_id BIGINT,
    p_discount_amount NUMERIC(12,2),
    p_invoice_number VARCHAR(30)
)
LANGUAGE plpgsql AS $$
DECLARE
    v_booking_status VARCHAR;
    v_session_id BIGINT;
    v_room_id BIGINT;
    v_room_charge NUMERIC(12,2);
    v_service_charge NUMERIC(12,2);
    v_total NUMERIC(12,2);
BEGIN
    SELECT status
    INTO v_booking_status
    FROM bookings
    WHERE booking_id = p_booking_id;

    IF v_booking_status IS NULL THEN
        RAISE EXCEPTION 'Booking % không tồn tại.', p_booking_id;
    END IF;

    IF v_booking_status <> 'checked_in' THEN
        RAISE EXCEPTION 'Chỉ booking đang checked_in mới được check-out.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Nhân viên % không tồn tại.', p_employee_id;
    END IF;

    IF p_discount_amount IS NULL OR p_discount_amount < 0 THEN
        RAISE EXCEPTION 'Giảm giá không được NULL hoặc âm.';
    END IF;

    IF EXISTS (SELECT 1 FROM invoices WHERE booking_id = p_booking_id) THEN
        RAISE EXCEPTION 'Booking này đã có hóa đơn.';
    END IF;

    SELECT session_id, room_id
    INTO v_session_id, v_room_id
    FROM room_sessions
    WHERE booking_id = p_booking_id
      AND session_status = 'active';

    IF v_session_id IS NULL THEN
        RAISE EXCEPTION 'Không có session active để check-out.';
    END IF;

    UPDATE room_sessions
    SET actual_end_time = CURRENT_TIMESTAMP,
        checked_out_by_employee_id = p_employee_id,
        session_status = 'completed'
    WHERE session_id = v_session_id;

    UPDATE rooms
    SET status = 'available'
    WHERE room_id = v_room_id;

    v_room_charge := fn_calculate_room_charge(p_booking_id);
    v_service_charge := fn_calculate_service_charge(p_booking_id);
    v_total := fn_calculate_invoice_total(v_room_charge, v_service_charge, 0, p_discount_amount);

    INSERT INTO invoices (
        invoice_number,
        booking_id,
        created_by_employee_id,
        room_charge,
        service_charge,
        discount_amount,
        total_amount,
        invoice_status
    )
    VALUES (
        p_invoice_number,
        p_booking_id,
        p_employee_id,
        v_room_charge,
        v_service_charge,
        p_discount_amount,
        v_total,
        'unpaid'
    );

    UPDATE bookings
    SET status = 'completed'
    WHERE booking_id = p_booking_id;
END;
$$;


-- ============================================================================
-- 9. Xác nhận thanh toán
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_confirm_payment(
    p_invoice_id BIGINT,
    p_amount_paid NUMERIC(12,2),
    p_method VARCHAR(20),
    p_reference VARCHAR(100),
    p_employee_id BIGINT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
    v_total NUMERIC(12,2);
BEGIN
    SELECT invoice_status, total_amount
    INTO v_status, v_total
    FROM invoices
    WHERE invoice_id = p_invoice_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Hóa đơn % không tồn tại.', p_invoice_id;
    END IF;

    IF v_status <> 'unpaid' THEN
        RAISE EXCEPTION 'Chỉ hóa đơn unpaid mới được thanh toán.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION 'Nhân viên % không tồn tại.', p_employee_id;
    END IF;

    IF p_amount_paid IS NULL OR p_amount_paid <> v_total THEN
        RAISE EXCEPTION 'Số tiền thanh toán (%) phải đúng bằng tổng hóa đơn (%).', p_amount_paid, v_total;
    END IF;

    INSERT INTO payments (
        invoice_id,
        amount_paid,
        payment_method,
        transaction_reference,
        received_by_employee_id,
        payment_status
    )
    VALUES (
        p_invoice_id,
        p_amount_paid,
        p_method,
        p_reference,
        p_employee_id,
        'successful'
    );

    UPDATE invoices
    SET invoice_status = 'paid'
    WHERE invoice_id = p_invoice_id;
END;
$$;
