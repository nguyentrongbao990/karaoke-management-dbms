-- 05_triggers_FIXED.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tự động hóa và bảo mật dữ liệu ở tầng cao nhất

-- ============================================================================
-- 1. TRIGGER: Tự động cập nhật cột updated_at
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_updated_at_room_types BEFORE UPDATE ON room_types FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_set_updated_at_rooms BEFORE UPDATE ON rooms FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_set_updated_at_customers BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_set_updated_at_employees BEFORE UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_set_updated_at_accounts BEFORE UPDATE ON accounts FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_set_updated_at_menu_items BEFORE UPDATE ON menu_items FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ============================================================================
-- 2. TRIGGER: Kiểm tra tính hợp lệ khi đặt phòng (Sử dụng TIMESTAMP)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_check_booking_valid() RETURNS TRIGGER AS $$
DECLARE
    v_room_status VARCHAR; v_capacity INT; v_overlap_count INT;
BEGIN
    IF NEW.expected_end_time <= NEW.expected_start_time THEN
        RAISE EXCEPTION 'Thời gian kết thúc phải sau thời gian bắt đầu.';
    END IF;

    SELECT status, actual_capacity INTO v_room_status, v_capacity FROM rooms WHERE room_id = NEW.room_id;
    IF v_room_status IN ('maintenance', 'inactive') THEN RAISE EXCEPTION 'Phòng đang bảo trì hoặc ngừng hoạt động.'; END IF;
    IF NEW.guest_count > v_capacity THEN RAISE EXCEPTION 'Số lượng khách vượt quá sức chứa phòng.'; END IF;

    IF NEW.status IN ('pending', 'confirmed', 'checked_in') THEN
        SELECT COUNT(*) INTO v_overlap_count FROM bookings
        WHERE room_id = NEW.room_id AND booking_id IS DISTINCT FROM NEW.booking_id
          AND status IN ('pending', 'confirmed', 'checked_in')
          AND (NEW.expected_start_time < expected_end_time AND NEW.expected_end_time > expected_start_time);
        IF v_overlap_count > 0 THEN RAISE EXCEPTION 'Trùng lịch với một đặt phòng khác.'; END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_booking_valid BEFORE INSERT OR UPDATE ON bookings FOR EACH ROW EXECUTE FUNCTION fn_check_booking_valid();


-- ============================================================================
-- 3 & 4. TRIGGER: Tự động tính thành tiền (line_total)
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_calc_line_total() RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'service_order_items' THEN
        NEW.line_total = NEW.quantity * NEW.unit_price;
    ELSE
        NEW.line_total = NEW.quantity * NEW.unit_amount;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calculate_service_order_item_total BEFORE INSERT OR UPDATE ON service_order_items FOR EACH ROW EXECUTE FUNCTION fn_calc_line_total();
CREATE TRIGGER trg_calculate_surcharge_line_total BEFORE INSERT OR UPDATE ON invoice_surcharges FOR EACH ROW EXECUTE FUNCTION fn_calc_line_total();


-- ============================================================================
-- 5. TRIGGER: Cập nhật tổng hóa đơn & Chống sửa invoice_id phụ thu 
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_refresh_invoice_total() RETURNS TRIGGER AS $$
DECLARE
    v_invoice_id BIGINT; v_status VARCHAR; v_room NUMERIC; v_serv NUMERIC; v_disc NUMERIC; v_sur NUMERIC;
BEGIN
    -- Chống đổi invoice_id của một dòng phụ thu 
    IF TG_OP = 'UPDATE' AND NEW.invoice_id <> OLD.invoice_id THEN
        RAISE EXCEPTION 'Không được phép chuyển phụ thu sang hóa đơn khác. Hãy xóa và tạo mới.';
    END IF;

    v_invoice_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END);

    SELECT invoice_status, room_charge, service_charge, discount_amount 
    INTO v_status, v_room, v_serv, v_disc FROM invoices WHERE invoice_id = v_invoice_id;

    IF v_status IN ('paid', 'cancelled') THEN
        RAISE EXCEPTION 'Hóa đơn đã chốt, không thể thay đổi phụ thu.';
    END IF;

    SELECT COALESCE(SUM(line_total), 0) INTO v_sur FROM invoice_surcharges WHERE invoice_id = v_invoice_id;
    UPDATE invoices SET total_amount = fn_calculate_invoice_total(v_room, v_serv, v_sur, v_disc) WHERE invoice_id = v_invoice_id;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_invoice_total_after_surcharge_change
AFTER INSERT OR UPDATE OR DELETE ON invoice_surcharges FOR EACH ROW EXECUTE FUNCTION fn_refresh_invoice_total();


-- ============================================================================
-- 6, 7, 8, 9. TRIGGER: KHÓA DỮ LIỆU SAU THANH TOÁN (ĐÃ BỔ SUNG INSERT) 
-- ============================================================================

-- A. Khóa bảng Invoices (Chỉ UPDATE/DELETE)
CREATE OR REPLACE FUNCTION fn_prevent_change_paid_invoice() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.invoice_status = 'paid' THEN RAISE EXCEPTION 'Bảo mật: Hóa đơn đã thanh toán, không thể sửa/xóa.'; END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_change_paid_invoice BEFORE UPDATE OR DELETE ON invoices FOR EACH ROW EXECUTE FUNCTION fn_prevent_change_paid_invoice();

-- B. Khóa các bảng nghiệp vụ liên quan (INSERT, UPDATE, DELETE) [cite: 417-419]
CREATE OR REPLACE FUNCTION fn_lock_after_payment() RETURNS TRIGGER AS $$
DECLARE
    v_invoice_id BIGINT; v_session_id BIGINT; v_booking_id BIGINT; v_status VARCHAR;
BEGIN
    -- Tìm invoice_id dựa trên bảng đang bị tác động
    IF TG_TABLE_NAME = 'invoice_surcharges' THEN
        v_invoice_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END);
    ELSIF TG_TABLE_NAME = 'service_orders' THEN
        v_session_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.session_id ELSE NEW.session_id END);
        SELECT i.invoice_id, i.invoice_status INTO v_invoice_id, v_status FROM room_sessions rs JOIN invoices i ON rs.booking_id = i.booking_id WHERE rs.session_id = v_session_id;
    ELSIF TG_TABLE_NAME = 'service_order_items' THEN
        SELECT session_id INTO v_session_id FROM service_orders WHERE service_order_id = (CASE WHEN TG_OP = 'DELETE' THEN OLD.service_order_id ELSE NEW.service_order_id END);
        SELECT i.invoice_id, i.invoice_status INTO v_invoice_id, v_status FROM room_sessions rs JOIN invoices i ON rs.booking_id = i.booking_id WHERE rs.session_id = v_session_id;
    ELSIF TG_TABLE_NAME = 'room_sessions' THEN
        v_booking_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.booking_id ELSE NEW.booking_id END);
        SELECT invoice_id, invoice_status INTO v_invoice_id, v_status FROM invoices WHERE booking_id = v_booking_id;
    END IF;

    -- Nếu chưa có status từ query trên, query lại bằng invoice_id
    IF v_status IS NULL AND v_invoice_id IS NOT NULL THEN
        SELECT invoice_status INTO v_status FROM invoices WHERE invoice_id = v_invoice_id;
    END IF;

    IF v_status = 'paid' THEN
        RAISE EXCEPTION 'Bảo mật: Không thể thêm/sửa/xóa dữ liệu (%) vì hóa đơn liên quan đã thanh toán.', TG_TABLE_NAME;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

-- Áp dụng khóa cho INSERT, UPDATE, DELETE [cite: 418-419]
CREATE TRIGGER trg_lock_surcharges BEFORE INSERT OR UPDATE OR DELETE ON invoice_surcharges FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();
CREATE TRIGGER trg_lock_service_orders BEFORE INSERT OR UPDATE OR DELETE ON service_orders FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();
CREATE TRIGGER trg_lock_service_order_items BEFORE INSERT OR UPDATE OR DELETE ON service_order_items FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();
CREATE TRIGGER trg_lock_room_sessions BEFORE INSERT OR UPDATE OR DELETE ON room_sessions FOR EACH ROW EXECUTE FUNCTION fn_lock_after_payment();
