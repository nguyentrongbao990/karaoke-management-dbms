-- 03_functions_FIXED.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Định nghĩa các hàm tính toán và kiểm tra nghiệp vụ

-- 1. fn_is_room_available: Kiểm tra phòng có trống không
CREATE OR REPLACE FUNCTION fn_is_room_available(
    p_room_id BIGINT,
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP
) 
RETURNS BOOLEAN AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM bookings
    WHERE room_id = p_room_id
      AND status IN ('pending', 'confirmed', 'checked_in')
      AND (
          (p_start_time >= expected_start_time AND p_start_time < expected_end_time) OR
          (p_end_time > expected_start_time AND p_end_time <= expected_end_time) OR
          (p_start_time <= expected_start_time AND p_end_time >= expected_end_time)
      );

    IF v_count > 0 THEN RETURN FALSE; END IF;

    SELECT COUNT(*) INTO v_count
    FROM rooms
    WHERE room_id = p_room_id AND status IN ('maintenance', 'inactive');

    IF v_count > 0 THEN RETURN FALSE; END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- 2. fn_get_available_rooms: Lấy danh sách phòng trống (Đã bổ sung)
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
    SELECT r.room_id, r.room_code, r.room_name, r.actual_capacity, rt.hourly_rate
    FROM rooms r
    JOIN room_types rt ON r.room_type_id = rt.room_type_id
    WHERE r.actual_capacity >= p_min_capacity
      AND fn_is_room_available(r.room_id, p_start_time, p_end_time) = TRUE;
END;
$$ LANGUAGE plpgsql;

-- 3. fn_calculate_session_duration: Tính thời lượng sử dụng (phút)
CREATE OR REPLACE FUNCTION fn_calculate_session_duration(
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP
) 
RETURNS INTEGER AS $$
BEGIN
    IF p_end_time IS NULL THEN RETURN 0; END IF;
    RETURN CEIL(EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 60);
END;
$$ LANGUAGE plpgsql;

-- 4. fn_calculate_room_charge: Tính tổng tiền phòng (ĐÃ FIX LỖI TRANSFERRED)
CREATE OR REPLACE FUNCTION fn_calculate_room_charge(p_booking_id BIGINT) 
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_total_room_charge NUMERIC(12,2) := 0;
BEGIN
    SELECT SUM(
        fn_calculate_session_duration(rs.actual_start_time, rs.actual_end_time) / 60.0 * rt.hourly_rate
    ) INTO v_total_room_charge
    FROM room_sessions rs
    JOIN rooms r ON rs.room_id = r.room_id
    JOIN room_types rt ON r.room_type_id = rt.room_type_id
    WHERE rs.booking_id = p_booking_id
      AND rs.session_status IN ('completed', 'transferred'); -- Fix lỗi tính rớt tiền khi đổi phòng

    RETURN COALESCE(v_total_room_charge, 0);
END;
$$ LANGUAGE plpgsql;

-- 5. fn_calculate_service_charge: Tính tổng tiền dịch vụ
CREATE OR REPLACE FUNCTION fn_calculate_service_charge(p_booking_id BIGINT) 
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_total_service_charge NUMERIC(12,2) := 0;
BEGIN
    SELECT SUM(soi.line_total) INTO v_total_service_charge
    FROM service_order_items soi
    JOIN service_orders so ON soi.service_order_id = so.service_order_id
    JOIN room_sessions rs ON so.session_id = rs.session_id
    WHERE rs.booking_id = p_booking_id
      AND so.order_status = 'confirmed';

    RETURN COALESCE(v_total_service_charge, 0);
END;
$$ LANGUAGE plpgsql;

-- 6. fn_calculate_surcharge_total: Tính tổng phụ thu
CREATE OR REPLACE FUNCTION fn_calculate_surcharge_total(p_invoice_id BIGINT) 
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_total_surcharge NUMERIC(12,2) := 0;
BEGIN
    SELECT SUM(line_total) INTO v_total_surcharge
    FROM invoice_surcharges
    WHERE invoice_id = p_invoice_id;

    RETURN COALESCE(v_total_surcharge, 0);
END;
$$ LANGUAGE plpgsql;

-- 7. fn_calculate_invoice_total: Tính tổng thanh toán cuối cùng
CREATE OR REPLACE FUNCTION fn_calculate_invoice_total(
    p_room_charge NUMERIC(12,2),
    p_service_charge NUMERIC(12,2),
    p_surcharge_total NUMERIC(12,2),
    p_discount_amount NUMERIC(12,2)
) 
RETURNS NUMERIC(12,2) AS $$
BEGIN
    RETURN GREATEST(0, (p_room_charge + p_service_charge + p_surcharge_total - p_discount_amount));
END;
$$ LANGUAGE plpgsql;
