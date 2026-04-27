-- 03_functions.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Định nghĩa các hàm kiểm tra và tính toán nghiệp vụ

-- ============================================================================
-- 1. Kiểm tra phòng có trống trong một khoảng thời gian hay không
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_is_room_available(
    p_room_id BIGINT,
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    p_ignore_booking_id BIGINT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_overlap_count INTEGER;
BEGIN
    IF p_start_time IS NULL OR p_end_time IS NULL OR p_end_time <= p_start_time THEN
        RETURN FALSE;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM rooms
        WHERE room_id = p_room_id
          AND status NOT IN ('maintenance', 'inactive')
    ) THEN
        RETURN FALSE;
    END IF;

    SELECT COUNT(*)
    INTO v_overlap_count
    FROM bookings
    WHERE room_id = p_room_id
      AND status IN ('pending', 'confirmed', 'checked_in')
      AND (p_ignore_booking_id IS NULL OR booking_id <> p_ignore_booking_id)
      AND p_start_time < expected_end_time
      AND p_end_time > expected_start_time;

    RETURN v_overlap_count = 0;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 2. Lấy danh sách phòng khả dụng theo thời gian và sức chứa
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_get_available_rooms(
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    p_min_capacity INT DEFAULT 1
)
RETURNS TABLE (
    room_id BIGINT,
    room_code VARCHAR,
    room_name VARCHAR,
    capacity INT,
    hourly_rate NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.room_id,
        r.room_code,
        r.room_name,
        r.actual_capacity AS capacity,
        rt.hourly_rate
    FROM rooms r
    JOIN room_types rt ON r.room_type_id = rt.room_type_id
    WHERE r.actual_capacity >= p_min_capacity
      AND r.status NOT IN ('maintenance', 'inactive')
      AND fn_is_room_available(r.room_id, p_start_time, p_end_time);
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 3. Tính thời lượng sử dụng của một session theo phút
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_session_duration(
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP
)
RETURNS INTEGER AS $$
BEGIN
    IF p_start_time IS NULL OR p_end_time IS NULL OR p_end_time <= p_start_time THEN
        RETURN 0;
    END IF;

    RETURN CEIL(EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 60.0)::INT;
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 4. Tính tổng tiền phòng của một booking
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_room_charge(
    p_booking_id BIGINT
)
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_total_room_charge NUMERIC(12,2) := 0;
BEGIN
    SELECT SUM(
        fn_calculate_session_duration(rs.actual_start_time, rs.actual_end_time) / 60.0 * rt.hourly_rate
    )
    INTO v_total_room_charge
    FROM room_sessions rs
    JOIN rooms r ON rs.room_id = r.room_id
    JOIN room_types rt ON r.room_type_id = rt.room_type_id
    WHERE rs.booking_id = p_booking_id
      AND rs.session_status IN ('completed', 'transferred');

    RETURN COALESCE(v_total_room_charge, 0);
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 5. Tính tổng tiền dịch vụ/món bán của một booking
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_service_charge(
    p_booking_id BIGINT
)
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_total_service_charge NUMERIC(12,2) := 0;
BEGIN
    SELECT SUM(soi.line_total)
    INTO v_total_service_charge
    FROM service_order_items soi
    JOIN service_orders so ON soi.service_order_id = so.service_order_id
    JOIN room_sessions rs ON so.session_id = rs.session_id
    WHERE rs.booking_id = p_booking_id
      AND so.order_status = 'confirmed';

    RETURN COALESCE(v_total_service_charge, 0);
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 6. Tính tổng phụ thu của một hóa đơn
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_surcharge_total(
    p_invoice_id BIGINT
)
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_total_surcharge NUMERIC(12,2) := 0;
BEGIN
    SELECT SUM(line_total)
    INTO v_total_surcharge
    FROM invoice_surcharges
    WHERE invoice_id = p_invoice_id;

    RETURN COALESCE(v_total_surcharge, 0);
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 7A. Tính tổng hóa đơn từ các thành phần tiền
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_invoice_total(
    p_room_charge NUMERIC(12,2),
    p_service_charge NUMERIC(12,2),
    p_surcharge_total NUMERIC(12,2),
    p_discount_amount NUMERIC(12,2)
)
RETURNS NUMERIC(12,2) AS $$
BEGIN
    RETURN GREATEST(
        0,
        COALESCE(p_room_charge, 0)
        + COALESCE(p_service_charge, 0)
        + COALESCE(p_surcharge_total, 0)
        - COALESCE(p_discount_amount, 0)
    );
END;
$$ LANGUAGE plpgsql;


-- ============================================================================
-- 7B. Tính tổng hóa đơn theo invoice_id
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_invoice_total(
    p_invoice_id BIGINT
)
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_room_charge NUMERIC(12,2);
    v_service_charge NUMERIC(12,2);
    v_discount_amount NUMERIC(12,2);
    v_surcharge_total NUMERIC(12,2);
BEGIN
    SELECT room_charge, service_charge, discount_amount
    INTO v_room_charge, v_service_charge, v_discount_amount
    FROM invoices
    WHERE invoice_id = p_invoice_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Hóa đơn % không tồn tại.', p_invoice_id;
    END IF;

    v_surcharge_total := fn_calculate_surcharge_total(p_invoice_id);

    RETURN fn_calculate_invoice_total(
        v_room_charge,
        v_service_charge,
        v_surcharge_total,
        v_discount_amount
    );
END;
$$ LANGUAGE plpgsql;
