-- 05_triggers.sql
-- Hệ thống quản lý Karaoke
-- Mục đích: Tự động tính toán, cập nhật và bảo vệ tính toàn vẹn dữ liệu

-- ============================================================================
-- 1. TRIGGER: Tự động cập nhật cột updated_at [cite: 1202-1212]
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_set_updated_at() 
RETURNS TRIGGER AS $$
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
-- 2. TRIGGER: Kiểm tra tính hợp lệ khi đặt phòng [cite: 1213-1222]
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_check_booking_valid() 
RETURNS TRIGGER AS $$
DECLARE
    v_room_status VARCHAR;
    v_capacity INT;
    v_overlap_count INT;
BEGIN
    -- 1. Kiểm tra thời gian
    IF NEW.expected_end_time <= NEW.expected_start_time THEN
        RAISE EXCEPTION 'Thời gian kết thúc phải sau thời gian bắt đầu.';
    END IF;

    -- 2. Kiểm tra sức chứa và trạng thái phòng
    SELECT status, actual_capacity INTO v_room_status, v_capacity 
    FROM rooms WHERE room_id = NEW.room_id;
    
    IF v_room_status IN ('maintenance', 'inactive') THEN
        RAISE EXCEPTION 'Phòng đang bảo trì hoặc ngừng hoạt động.';
    END IF;
    
    IF NEW.guest_count > v_capacity THEN
        RAISE EXCEPTION 'Số lượng khách vượt quá sức chứa tối đa của phòng.';
    END IF;

    -- 3. Kiểm tra trùng lịch (Chỉ xét các booking chưa bị hủy/hoàn thành)
    IF NEW.status IN ('pending', 'confirmed', 'checked_in') THEN
        SELECT COUNT(*) INTO v_overlap_count
        FROM bookings
        WHERE room_id = NEW.room_id
          AND booking_id IS DISTINCT FROM NEW.booking_id
          AND status IN ('pending', 'confirmed', 'checked_in')
          AND (NEW.expected_start_time < expected_end_time AND NEW.expected_end_time > expected_start_time);
          
        IF v_overlap_count > 0 THEN
            RAISE EXCEPTION 'Trùng lịch với một đặt phòng khác.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_booking_valid
BEFORE INSERT OR UPDATE ON bookings
FOR EACH ROW EXECUTE FUNCTION fn_check_booking_valid();


-- ============================================================================
-- 3 & 4. TRIGGER: Tự động tính thành tiền (line_total) [cite: 1223-1234]
-- ============================================================================
-- Cho gọi món
CREATE OR REPLACE FUNCTION fn_calc_so_item_total() RETURNS TRIGGER AS $$
BEGIN
    NEW.line_total = NEW.quantity * NEW.unit_price;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calculate_service_order_item_total
BEFORE INSERT OR UPDATE ON service_order_items
FOR EACH ROW EXECUTE FUNCTION fn_calc_so_item_total();

-- Cho phụ thu
CREATE OR REPLACE FUNCTION fn_calc_surcharge_line_total() RETURNS TRIGGER AS $$
BEGIN
    NEW.line_total = NEW.quantity * NEW.unit_amount;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calculate_surcharge_line_total
BEFORE INSERT OR UPDATE ON invoice_surcharges
FOR EACH ROW EXECUTE FUNCTION fn_calc_surcharge_line_total();


-- ============================================================================
-- 5. TRIGGER: Phi chuẩn hóa - Cập nhật tổng hóa đơn khi có phụ thu [cite: 1235-1244]
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_refresh_invoice_total() 
RETURNS TRIGGER AS $$
DECLARE
    v_invoice_id BIGINT;
    v_status VARCHAR;
    v_room_charge NUMERIC(12,2);
    v_service_charge NUMERIC(12,2);
    v_discount NUMERIC(12,2);
    v_surcharge_total NUMERIC(12,2);
    v_new_total NUMERIC(12,2);
BEGIN
    -- Lấy ID hóa đơn đang bị tác động
    IF TG_OP = 'DELETE' THEN
        v_invoice_id := OLD.invoice_id;
    ELSE
        v_invoice_id := NEW.invoice_id;
    END IF;

    -- Kiểm tra trạng thái hóa đơn
    SELECT invoice_status, room_charge, service_charge, discount_amount 
    INTO v_status, v_room_charge, v_service_charge, v_discount
    FROM invoices WHERE invoice_id = v_invoice_id;

    -- Chặn thay đổi nếu hóa đơn đã chốt
    IF v_status IN ('paid', 'cancelled') THEN
        RAISE EXCEPTION 'Không thể tính lại tổng vì hóa đơn đã thanh toán hoặc hủy.';
    END IF;

    -- Tính toán lại tổng phụ thu (Bỏ qua dòng đang bị xóa/sửa)
    SELECT COALESCE(SUM(line_total), 0) INTO v_surcharge_total
    FROM invoice_surcharges WHERE invoice_id = v_invoice_id;

    -- Tính lại tổng thanh toán cuối cùng
    v_new_total := GREATEST(0, v_room_charge + v_service_charge + v_surcharge_total - v_discount);

    -- Cập nhật vào bảng invoices
    UPDATE invoices SET total_amount = v_new_total WHERE invoice_id = v_invoice_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_refresh_invoice_total_after_surcharge_change
AFTER INSERT OR UPDATE OR DELETE ON invoice_surcharges
FOR EACH ROW EXECUTE FUNCTION fn_refresh_invoice_total();


-- ============================================================================
-- 6, 7, 8, 9. TRIGGER: Khóa chặt dữ liệu khi hóa đơn đã thanh toán 
-- ============================================================================
-- Khóa bảng Invoices
CREATE OR REPLACE FUNCTION fn_prevent_update_paid_invoice() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.invoice_status = 'paid' THEN
        RAISE EXCEPTION 'Bảo mật: Không thể sửa hoặc xóa hóa đơn đã thanh toán.';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_update_paid_invoice
BEFORE UPDATE OR DELETE ON invoices
FOR EACH ROW EXECUTE FUNCTION fn_prevent_update_paid_invoice();

-- Khóa bảng Phụ thu (invoice_surcharges)
CREATE OR REPLACE FUNCTION fn_prevent_change_paid_invoice_details() RETURNS TRIGGER AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT invoice_status INTO v_status FROM invoices 
    WHERE invoice_id = (CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END);
    
    IF v_status = 'paid' THEN
        RAISE EXCEPTION 'Bảo mật: Không thể thay đổi chi tiết phụ thu của hóa đơn đã thanh toán.';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_change_paid_invoice_details
BEFORE INSERT OR UPDATE OR DELETE ON invoice_surcharges
FOR EACH ROW EXECUTE FUNCTION fn_prevent_change_paid_invoice_details();

-- Khóa bảng Gọi món (service_orders & service_order_items)
CREATE OR REPLACE FUNCTION fn_prevent_change_paid_invoice_orders() RETURNS TRIGGER AS $$
DECLARE
    v_paid_count INT;
    v_session_id BIGINT;
    v_order_id BIGINT;
BEGIN
    -- Tìm session_id liên quan
    IF TG_TABLE_NAME = 'service_orders' THEN
        v_session_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.session_id ELSE NEW.session_id END);
    ELSIF TG_TABLE_NAME = 'service_order_items' THEN
        v_order_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.service_order_id ELSE NEW.service_order_id END);
        SELECT session_id INTO v_session_id FROM service_orders WHERE service_order_id = v_order_id;
    END IF;

    -- Kiểm tra hóa đơn
    SELECT COUNT(*) INTO v_paid_count
    FROM room_sessions rs
    JOIN invoices i ON rs.booking_id = i.booking_id
    WHERE rs.session_id = v_session_id AND i.invoice_status = 'paid';

    IF v_paid_count > 0 THEN
        RAISE EXCEPTION 'Bảo mật: Không thể thay đổi đơn gọi món vì hóa đơn tổng đã thanh toán.';
    END IF;
    
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_change_paid_invoice_so
BEFORE UPDATE OR DELETE ON service_orders
FOR EACH ROW EXECUTE FUNCTION fn_prevent_change_paid_invoice_orders();

CREATE TRIGGER trg_prevent_change_paid_invoice_soi
BEFORE UPDATE OR DELETE ON service_order_items
FOR EACH ROW EXECUTE FUNCTION fn_prevent_change_paid_invoice_orders();

-- Khóa bảng Phiên sử dụng phòng (room_sessions)
CREATE OR REPLACE FUNCTION fn_prevent_change_paid_invoice_sessions() RETURNS TRIGGER AS $$
DECLARE
    v_paid_count INT;
    v_booking_id BIGINT;
BEGIN
    v_booking_id := (CASE WHEN TG_OP = 'DELETE' THEN OLD.booking_id ELSE NEW.booking_id END);
    
    SELECT COUNT(*) INTO v_paid_count
    FROM invoices WHERE booking_id = v_booking_id AND invoice_status = 'paid';

    IF v_paid_count > 0 THEN
        RAISE EXCEPTION 'Bảo mật: Không thể sửa giờ hát/phòng vì hóa đơn đã thanh toán.';
    END IF;
    
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_change_paid_invoice_sessions
BEFORE UPDATE OR DELETE ON room_sessions
FOR EACH ROW EXECUTE FUNCTION fn_prevent_change_paid_invoice_sessions();
