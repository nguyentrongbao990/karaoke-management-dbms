-- 05_triggers.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tự động hóa và bảo vệ dữ liệu ở tầng CSDL

-- ============================================================================
-- 1. Tự động cập nhật updated_at
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_updated_at_room_types ON room_types;
CREATE TRIGGER trg_set_updated_at_room_types
BEFORE UPDATE ON room_types
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_set_updated_at_rooms ON rooms;
CREATE TRIGGER trg_set_updated_at_rooms
BEFORE UPDATE ON rooms
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_set_updated_at_customers ON customers;
CREATE TRIGGER trg_set_updated_at_customers
BEFORE UPDATE ON customers
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_set_updated_at_employees ON employees;
CREATE TRIGGER trg_set_updated_at_employees
BEFORE UPDATE ON employees
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_set_updated_at_accounts ON accounts;
CREATE TRIGGER trg_set_updated_at_accounts
BEFORE UPDATE ON accounts
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_set_updated_at_menu_items ON menu_items;
CREATE TRIGGER trg_set_updated_at_menu_items
BEFORE UPDATE ON menu_items
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 2. Kiểm tra tính hợp lệ của booking
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_check_booking_valid()
RETURNS TRIGGER AS $$
DECLARE
    v_room_status VARCHAR;
    v_capacity INT;
    v_overlap_count INT;
BEGIN
    IF NEW.expected_end_time <= NEW.expected_start_time THEN
        RAISE EXCEPTION 'Thời gian kết thúc phải sau thời gian bắt đầu.';
    END IF;

    SELECT status, actual_capacity
    INTO v_room_status, v_capacity
    FROM rooms
    WHERE room_id = NEW.room_id;

    IF v_room_status IS NULL THEN
        RAISE EXCEPTION 'Phòng % không tồn tại.', NEW.room_id;
    END IF;

    IF v_room_status IN ('maintenance', 'inactive') THEN
        RAISE EXCEPTION 'Phòng đang bảo trì hoặc ngừng hoạt động.';
    END IF;

    IF NEW.guest_count IS NULL OR NEW.guest_count <= 0 THEN
        RAISE EXCEPTION 'Số khách phải lớn hơn 0.';
    END IF;

    IF NEW.guest_count > v_capacity THEN
        RAISE EXCEPTION 'Số lượng khách vượt quá sức chứa phòng.';
    END IF;

    IF NEW.status IN ('pending', 'confirmed', 'checked_in') THEN
        SELECT COUNT(*)
        INTO v_overlap_count
        FROM bookings
        WHERE room_id = NEW.room_id
          AND booking_id IS DISTINCT FROM NEW.booking_id
          AND status IN ('pending', 'confirmed', 'checked_in')
          AND NEW.expected_start_time < expected_end_time
          AND NEW.expected_end_time > expected_start_time;

        IF v_overlap_count > 0 THEN
            RAISE EXCEPTION 'Trùng lịch với một đặt phòng khác.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_booking_valid ON bookings;
CREATE TRIGGER trg_check_booking_valid
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW EXECUTE FUNCTION fn_check_booking_valid();


-- ============================================================================
-- 3. Tự động tính line_total của service_order_items
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_service_order_item_line_total()
RETURNS TRIGGER AS $$
BEGIN
    NEW.line_total = NEW.quantity * NEW.unit_price;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_calculate_service_order_item_total ON service_order_items;
CREATE TRIGGER trg_calculate_service_order_item_total
BEFORE INSERT OR UPDATE ON service_order_items
FOR EACH ROW EXECUTE FUNCTION fn_calculate_service_order_item_line_total();


-- ============================================================================
-- 4. Tự động tính line_total của invoice_surcharges
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_calculate_surcharge_line_total()
RETURNS TRIGGER AS $$
BEGIN
    NEW.line_total = NEW.quantity * NEW.unit_amount;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_calculate_surcharge_line_total ON invoice_surcharges;
CREATE TRIGGER trg_calculate_surcharge_line_total
BEFORE INSERT OR UPDATE ON invoice_surcharges
FOR EACH ROW EXECUTE FUNCTION fn_calculate_surcharge_line_total();


-- ============================================================================
-- 5. Cập nhật tổng hóa đơn khi phụ thu thay đổi
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_refresh_invoice_total()
RETURNS TRIGGER AS $$
DECLARE
    v_invoice_id BIGINT;
    v_status VARCHAR;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.invoice_id <> OLD.invoice_id THEN
        RAISE EXCEPTION 'Không được chuyển phụ thu sang hóa đơn khác. Hãy xóa và tạo mới.';
    END IF;

    v_invoice_id := CASE
        WHEN TG_OP = 'DELETE' THEN OLD.invoice_id
        ELSE NEW.invoice_id
    END;

    SELECT invoice_status
    INTO v_status
    FROM invoices
    WHERE invoice_id = v_invoice_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Hóa đơn % không tồn tại.', v_invoice_id;
    END IF;

    IF v_status IN ('paid', 'cancelled') THEN
        RAISE EXCEPTION 'Hóa đơn đã chốt, không thể thay đổi phụ thu.';
    END IF;

    UPDATE invoices
    SET total_amount = fn_calculate_invoice_total(v_invoice_id)
    WHERE invoice_id = v_invoice_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_refresh_invoice_total_after_surcharge_change ON invoice_surcharges;
CREATE TRIGGER trg_refresh_invoice_total_after_surcharge_change
AFTER INSERT OR UPDATE OR DELETE ON invoice_surcharges
FOR EACH ROW EXECUTE FUNCTION fn_refresh_invoice_total();


-- ============================================================================
-- 6. Không cho sửa/xóa hóa đơn đã thanh toán
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_prevent_change_paid_invoice()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.invoice_status = 'paid' THEN
        RAISE EXCEPTION 'Hóa đơn đã thanh toán, không thể sửa/xóa.';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_update_paid_invoice ON invoices;
CREATE TRIGGER trg_prevent_update_paid_invoice
BEFORE UPDATE OR DELETE ON invoices
FOR EACH ROW EXECUTE FUNCTION fn_prevent_change_paid_invoice();


-- ============================================================================
-- 7, 8, 9. Khóa dữ liệu nghiệp vụ liên quan sau thanh toán
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_lock_after_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_invoice_id BIGINT;
    v_session_id BIGINT;
    v_booking_id BIGINT;
    v_status VARCHAR;
BEGIN
    IF TG_TABLE_NAME = 'invoice_surcharges' THEN
        v_invoice_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;

    ELSIF TG_TABLE_NAME = 'service_orders' THEN
        v_session_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.session_id ELSE NEW.session_id END;

        SELECT i.invoice_id, i.invoice_status
        INTO v_invoice_id, v_status
        FROM room_sessions rs
        JOIN invoices i ON rs.booking_id = i.booking_id
        WHERE rs.session_id = v_session_id;

    ELSIF TG_TABLE_NAME = 'service_order_items' THEN
        SELECT session_id
        INTO v_session_id
        FROM service_orders
        WHERE service_order_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.service_order_id ELSE NEW.service_order_id END;

        SELECT i.invoice_id, i.invoice_status
        INTO v_invoice_id, v_status
        FROM room_sessions rs
        JOIN invoices i ON rs.booking_id = i.booking_id
        WHERE rs.session_id = v_session_id;

    ELSIF TG_TABLE_NAME = 'room_sessions' THEN
        v_booking_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.booking_id ELSE NEW.booking_id END;

        SELECT invoice_id, invoice_status
        INTO v_invoice_id, v_status
        FROM invoices
        WHERE booking_id = v_booking_id;
    END IF;

    IF v_status IS NULL AND v_invoice_id IS NOT NULL THEN
        SELECT invoice_status
        INTO v_status
        FROM invoices
        WHERE invoice_id = v_invoice_id;
    END IF;

    IF v_status IN ('paid', 'cancelled') THEN
        RAISE EXCEPTION 'Không thể thêm/sửa/xóa dữ liệu ở bảng % vì hóa đơn liên quan đã chốt.', TG_TABLE_NAME;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_change_paid_invoice_details ON invoice_surcharges;
CREATE TRIGGER trg_prevent_change_paid_invoice_details
BEFORE INSERT OR UPDATE OR DELETE ON invoice_surcharges
FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();

DROP TRIGGER IF EXISTS trg_prevent_change_paid_invoice_orders ON service_orders;
CREATE TRIGGER trg_prevent_change_paid_invoice_orders
BEFORE INSERT OR UPDATE OR DELETE ON service_orders
FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();

DROP TRIGGER IF EXISTS trg_prevent_change_paid_invoice_order_items ON service_order_items;
CREATE TRIGGER trg_prevent_change_paid_invoice_order_items
BEFORE INSERT OR UPDATE OR DELETE ON service_order_items
FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();

DROP TRIGGER IF EXISTS trg_prevent_change_paid_invoice_sessions ON room_sessions;
CREATE TRIGGER trg_prevent_change_paid_invoice_sessions
BEFORE INSERT OR UPDATE OR DELETE ON room_sessions
FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();
