"""Kiem thu don vi cho demo_app (Flask) - KHONG can ket noi CSDL.

CSDL duoc thay bang ham gia (monkeypatch) nen test chay nhanh va doc lap.
Cac rang buoc nghiep vu cua CSDL duoc kiem thu rieng trong tests.sql.
"""
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pytest
from werkzeug.security import generate_password_hash

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "demo_app"))

import app as app_module  # noqa: E402


@pytest.fixture()
def client():
    app_module.app.config.update(TESTING=True)
    with app_module.app.test_client() as c:
        yield c


@pytest.fixture(autouse=True)
def account_still_valid(monkeypatch):
    """Mac dinh tai khoan trong phien con hieu luc (khong hoi CSDL)."""
    from flask import session
    monkeypatch.setattr(app_module, "current_role", lambda uid: session.get("role"), raising=False)


def csrf_of(client):
    """Mo trang login de lay ma CSRF trong session."""
    client.get("/login")
    with client.session_transaction() as s:
        return s["csrf"]


def login_as(client, role):
    with client.session_transaction() as s:
        s.update(uid="00000000-0000-0000-0000-000000000001", name="Test", role=role, csrf="tok")
    return "tok"


# ------------------------------------------------------------ ham tien ich
def test_local_window_adds_duration():
    assert app_module.local_window("2026-11-05", "18:00", 90) == (
        "2026-11-05 18:00", "2026-11-05 19:30")


def test_local_window_crosses_midnight():
    assert app_module.local_window("2026-11-05", "23:30", 60) == (
        "2026-11-05 23:30", "2026-11-06 00:30")


def test_local_window_rejects_bad_time():
    with pytest.raises(ValueError):
        app_module.local_window("2026-11-05", "25:99", 30)


def test_vnd_filter_formats_thousands():
    assert app_module.vnd(182000) == "182.000đ"
    assert app_module.vnd(None) == "0đ"


class FakeErr(Exception):
    def __init__(self, sqlstate, msg="loi"):
        super().__init__(msg)
        self.sqlstate = sqlstate


def test_db_message_overlap():
    assert "chồng" in app_module.db_message(FakeErr("23P01"))


def test_db_message_check_and_unique():
    assert app_module.db_message(FakeErr("23514", "end must be after start")).startswith("Dữ liệu không hợp lệ")
    assert "đã tồn tại" in app_module.db_message(FakeErr("23505"))


# ------------------------------------------------------------ phan quyen
@pytest.mark.parametrize("path", ["/customer", "/manager", "/admin"])
def test_anonymous_redirected_to_login(client, path):
    r = client.get(path)
    assert r.status_code == 302 and "/login" in r.headers["Location"]


@pytest.mark.parametrize("role,path", [("CUSTOMER", "/admin"), ("CUSTOMER", "/manager"),
                                       ("MANAGER", "/admin"), ("MANAGER", "/customer")])
def test_wrong_role_cannot_open_page(client, role, path):
    login_as(client, role)
    r = client.get(path)
    assert r.status_code == 302 and "/login" in r.headers["Location"]


def test_index_redirects_by_role(client):
    login_as(client, "ADMIN")
    assert "/admin" in client.get("/").headers["Location"]


# ------------------------------------------------------------ CSRF
def test_post_without_csrf_is_rejected(client):
    assert client.post("/login", data={"email": "a@b.c", "password": "x"}).status_code == 400


def test_post_with_wrong_csrf_is_rejected(client):
    csrf_of(client)
    assert client.post("/login", data={"csrf": "sai", "email": "a@b.c"}).status_code == 400


# ------------------------------------------------------------ dang nhap
def test_login_page_loads(client):
    assert client.get("/login").status_code == 200


def test_login_unknown_email_shows_error(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: None)
    r = client.post("/login", data={"csrf": csrf_of(client), "email": "no@x.vn", "password": "p"})
    assert r.status_code == 200
    assert "không đúng" in r.get_data(as_text=True)


def test_login_wrong_password(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "id": "u1", "name": "Khach", "role": "CUSTOMER", "hash": generate_password_hash("dung")})
    r = client.post("/login", data={"csrf": csrf_of(client), "email": "k@x.vn", "password": "sai"})
    assert r.status_code == 200 and "không đúng" in r.get_data(as_text=True)


@pytest.mark.parametrize("role,target", [("CUSTOMER", "/customer"), ("MANAGER", "/manager"), ("ADMIN", "/admin")])
def test_login_success_redirects_to_role_home(client, monkeypatch, role, target):
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "id": "u1", "name": "Test", "role": role, "hash": generate_password_hash("dung"),
        "plain": "dung"})
    r = client.post("/login", data={"csrf": csrf_of(client), "email": "t@x.vn", "password": "dung"})
    assert r.status_code == 302 and target in r.headers["Location"]


def test_logout_clears_session(client):
    tok = login_as(client, "CUSTOMER")
    r = client.post("/logout", data={"csrf": tok})
    assert r.status_code == 302
    with client.session_transaction() as s:
        assert "role" not in s


# ------------------------------------------------------------ kiem tra dau vao
def test_pay_rejects_unknown_method(client):
    tok = login_as(client, "CUSTOMER")
    r = client.post("/customer/pay", data={"csrf": tok, "method": "BITCOIN", "id": "x"})
    assert r.status_code == 400


def test_manager_equipment_rejects_unknown_status(client):
    tok = login_as(client, "MANAGER")
    r = client.post("/manager/equipment", data={"csrf": tok, "status": "EXPLODED", "id": "x"})
    assert r.status_code == 400


def test_admin_cannot_create_customer_via_accounts_form(client):
    tok = login_as(client, "ADMIN")
    r = client.post("/admin/accounts", data={"csrf": tok, "role": "CUSTOMER", "name": "a",
                                              "phone": "1", "email": "a@x.vn"})
    assert r.status_code == 400


# ------------------------------------------------------------ gio server / khung gia
BANDS = [
    {"band": "OFF_PEAK", "s": 0, "e": 300},
    {"band": "STANDARD", "s": 300, "e": 1020},
    {"band": "PEAK", "s": 1020, "e": 1200},
    {"band": "STANDARD", "s": 1200, "e": 1320},
    {"band": "OFF_PEAK", "s": 1320, "e": 1440},
]


def test_local_ms_uses_vietnam_offset():
    # 2026-11-05 14:00 (UTC+7) = 07:00 UTC
    assert app_module.local_ms("2026-11-05 14:00") == 1793862000000


def test_band_info_counts_minutes_to_change():
    info = app_module.band_info(BANDS, 16 * 60 + 40)          # 16:40 STANDARD
    assert info == {"band": "STANDARD", "next_band": "PEAK", "minutes_to_change": 20}


def test_band_info_wraps_over_midnight_between_equal_bands():
    info = app_module.band_info(BANDS, 23 * 60)               # 23:00 OFF_PEAK, ke 05:00
    assert info["band"] == "OFF_PEAK" and info["next_band"] == "STANDARD"
    assert info["minutes_to_change"] == 6 * 60


def test_band_info_without_tariff_rows():
    assert app_module.band_info([], 600) is None


def test_api_time_returns_server_time_and_band(client, monkeypatch):
    epoch = 1793862000000 + 40 * 1000                        # 14:00:40 local
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "epoch_ms": epoch, "local_iso": "2026-11-05T16:40:40"})
    monkeypatch.setattr(app_module.db, "rows", lambda *a, **k: BANDS)
    r = client.get("/api/time")
    body = r.get_json()
    assert r.status_code == 200 and r.headers["Cache-Control"] == "no-store"
    assert body["tz"] == "Asia/Ho_Chi_Minh" and body["epoch_ms"] == epoch
    assert body["band"] == "STANDARD" and body["next_band"] == "PEAK"
    assert body["change_epoch_ms"] == epoch - epoch % 60000 + 20 * 60000


def test_api_time_survives_missing_tariff(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "epoch_ms": 1793862000000, "local_iso": "2026-11-05T14:00:00"})
    monkeypatch.setattr(app_module.db, "rows", lambda *a, **k: [])
    body = client.get("/api/time").get_json()
    assert "band" not in body and body["epoch_ms"] == 1793862000000


def test_clock_and_script_rendered_on_every_page(client):
    html = client.get("/login").get_data(as_text=True)
    assert 'id="clock"' in html and "/api/time" in html and "live.js" in html


# ------------------------------------------------------------ trang khach / quan ly
def customer_rows(sql, params=()):
    if "FROM vehicle WHERE" in sql:
        return [{"id": "v1", "plate": "51A-123.45", "kwh": 60.0}]
    if "FROM parking_facility ORDER" in sql:
        return [{"id": "f1", "name": "EV Hub Q1", "addr": "x"}]
    if "fn_is_space_available" in sql:
        return [{"id": "s1", "code": "A01", "conn": "FAST_DC", "kw": 60.0, "free": True,
                 "band": "PEAK", "price": 5000.0, "ot": 20000.0}]
    if "FROM reservation AS r" in sql:
        return [{"id": "r1", "facility": "EV Hub Q1", "code": "A01", "plate": "51A-123.45",
                 "start_text": "05/11 18:00", "end_text": "19:30", "start_ms": 1793876400000,
                 "status": "CONFIRMED"}]
    if "FROM service_session AS ss" in sql:
        return [{"plate": "51A-123.45", "code": "A02", "facility": "EV Hub Q1", "kw": 60.0,
                 "cap": 60.0, "band": "STANDARD", "price": 3500.0,
                 "start_ms": 1793860000000, "since": "13:26"}]
    return []


def test_customer_page_has_live_widgets(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", customer_rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"d": "2026-11-05"})
    login_as(client, "CUSTOMER")
    html = client.get("/customer?day=2026-11-05&start=18:00&dur=90").get_data(as_text=True)
    assert 'id="search-form"' in html
    assert f'data-start-ms="{app_module.local_ms("2026-11-05 18:00")}"' in html
    assert f'data-end-ms="{app_module.local_ms("2026-11-05 19:30")}"' in html
    assert 'data-live="reservation"' in html and 'data-grace="1800000"' in html
    assert 'data-live="session"' in html and "Phiên đang sạc" in html
    assert "js-book" in html and "js-preview" in html and 'data-kwh="60.0"' in html


def test_customer_page_hides_session_panel_when_none(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): [] if "service_session" in sql else customer_rows(sql, p))
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"d": "2026-11-05"})
    login_as(client, "CUSTOMER")
    assert "Phiên đang sạc" not in client.get("/customer").get_data(as_text=True)


def test_manager_page_has_live_widgets(client, monkeypatch):
    def rows(sql, params=()):
        if "facility_manager" in sql:
            return [{"id": "f1", "name": "EV Hub Q1"}]
        if "FROM parking_space AS s" in sql:
            return [{"code": "A01", "status": "OCCUPIED", "eq_id": "e1", "conn": "FAST_DC", "kw": 60.0,
                     "eq_status": "CHARGING", "evse": "VN*E1", "plate": "51A-1", "kwh": 4.2,
                     "pct_now": 41.5, "full_text": None, "session_id": "s1",
                     "since": "13:30", "since_ms": 1793860200000, "next_ms": 1793876400000,
                     "next_booking": "18:00"}]
        if "late_min" in sql:
            return [{"id": "r1", "code": "A03", "plate": "51A-2", "late_min": 41,
                     "start_ms": 1793859000000}]
        return []
    monkeypatch.setattr(app_module.db, "rows", rows)
    login_as(client, "MANAGER")
    html = client.get("/manager").get_data(as_text=True)
    assert 'data-live="late"' in html and 'data-live="elapsed"' in html and 'data-live="until"' in html
    assert "hạn 30 phút" in html


# ------------------------------------------------------------ dang ky khach hang
import types  # noqa: E402

GOOD_REG = {"name": "Nguyen Van A", "email": "a@x.vn", "phone": "0901234567",
            "plate": "51a-123.45", "battery": "60,5", "password": "matkhau123",
            "password2": "matkhau123"}


def post_register(client, **override):
    client.get("/register")
    with client.session_transaction() as s:
        tok = s["csrf"]
    data = dict(GOOD_REG, csrf=tok)
    data.update(override)
    return client.post("/register", data=data)


def test_login_links_to_register(client):
    html = client.get("/login").get_data(as_text=True)
    assert "/register" in html


def test_register_page_loads_with_vehicle_fields(client):
    html = client.get("/register").get_data(as_text=True)
    assert 'name="plate"' in html and 'name="battery"' in html and 'name="password2"' in html


def test_register_success_creates_customer_only(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, params=(): calls.append((sql, params)) or 1)
    r = post_register(client, role="ADMIN")                      # role from form must be ignored
    assert r.status_code == 302 and "/login" in r.headers["Location"]
    sql, params = calls[0]
    assert "'CUSTOMER'" in sql and "ADMIN" not in params
    assert params[:3] == ("Nguyen Van A", "0901234567", "a@x.vn")
    assert params[3] != "matkhau123"
    from werkzeug.security import check_password_hash
    assert check_password_hash(params[3], "matkhau123")
    assert params[4] == "matkhau123"                             # admin can view it
    assert params[5:] == ("51A-123.45", "60.50")                 # plate upper-cased, kWh normalised


@pytest.mark.parametrize("override,message", [
    ({"password": "ngan", "password2": "ngan"}, "ít nhất 8"),
    ({"password2": "khac12345"}, "không khớp"),
    ({"phone": "abc"}, "Số điện thoại"),
    ({"email": "khong-phai-email"}, "Email không hợp lệ"),
    ({"battery": "0"}, "pin"),
    ({"battery": "abc"}, "pin"),
    ({"plate": ""}, "Biển số"),
    ({"name": ""}, "Họ tên"),
])
def test_register_rejects_invalid_input(client, monkeypatch, override, message):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    r = post_register(client, **override)
    assert r.status_code == 200 and message in r.get_data(as_text=True)
    assert not called


def test_register_keeps_typed_values_but_not_password(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: 1)
    html = post_register(client, password="ngan", password2="ngan").get_data(as_text=True)
    assert 'value="a@x.vn"' in html and "ngan" not in html.split('name="password"')[1][:80]


@pytest.mark.parametrize("constraint,message", [
    ("ux_user_account_email", "Email này đã được đăng ký"),
    ("ux_user_account_phone", "Số điện thoại này đã được đăng ký"),
    ("ux_vehicle_license_plate", "Biển số xe này đã được đăng ký"),
])
def test_register_reports_duplicates(client, monkeypatch, constraint, message):
    class Dup(app_module.psycopg.Error):
        sqlstate = "23505"
        diag = types.SimpleNamespace(constraint_name=constraint)

    def boom(*a, **k):
        raise Dup("duplicate key")
    monkeypatch.setattr(app_module.db, "run", boom)
    r = post_register(client)
    assert r.status_code == 200 and message in r.get_data(as_text=True)


def test_logged_in_user_is_redirected_away_from_register(client):
    login_as(client, "CUSTOMER")
    r = client.get("/register")
    assert r.status_code == 302 and r.headers["Location"] == "/"       # "/" then routes by role


# ------------------------------------------------------------ admin tao tai khoan voi mat khau tu nhap
def post_admin_account(client, **override):
    tok = login_as(client, "ADMIN")
    data = {"csrf": tok, "role": "MANAGER", "name": "Quan Ly", "phone": "0912345678",
            "email": "m@x.vn", "password": "matkhau123", "password2": "matkhau123"}
    data.update(override)
    return client.post("/admin/accounts", data=data, follow_redirects=True)


def test_admin_sets_manager_password_and_it_is_kept_for_viewing(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, params=(): calls.append(params) or 1)
    monkeypatch.setattr(app_module.db, "rows", lambda *a, **k: [])
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"revenue": 0})
    r = post_admin_account(client)
    from werkzeug.security import check_password_hash
    assert check_password_hash(calls[0][3], "matkhau123") and calls[0][5] == "MANAGER"
    assert calls[0][4] == "matkhau123"


@pytest.mark.parametrize("override,message", [
    ({"password": "ngan", "password2": "ngan"}, "ít nhất 8"),
    ({"password2": "khac12345"}, "không khớp"),
])
def test_admin_account_rejects_bad_password(client, monkeypatch, override, message):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    monkeypatch.setattr(app_module.db, "rows", lambda *a, **k: [])
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"revenue": 0})
    r = post_admin_account(client, **override)
    assert message in r.get_data(as_text=True) and not called


# ------------------------------------------------------------ kiem tra dau vao
@pytest.mark.parametrize("query", ["dur=abc", "dur=-60", "dur=999999999999",
                                   "fac=xyz", "day=9999-12-31&start=23:45&dur=240"])
def test_customer_page_survives_bad_query(client, monkeypatch, query):
    seen = []

    def rows(sql, p=()):
        seen.append(p)
        return customer_rows(sql, p)
    monkeypatch.setattr(app_module.db, "rows", rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"d": "2026-11-05"})
    login_as(client, "CUSTOMER")
    assert client.get("/customer?" + query).status_code == 200
    assert not any("xyz" in p for p in seen)


@pytest.mark.parametrize("dur", ["45", "100000", "-30"])
def test_booking_rejects_duration_outside_choices(client, monkeypatch, dur):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    tok = login_as(client, "CUSTOMER")
    client.post("/customer/book", data={"csrf": tok, "day": "2030-01-01", "start": "10:00",
                                        "dur": dur, "space": "s", "vehicle": "v"})
    assert not called


def test_invalid_id_from_database_is_not_a_500(client, monkeypatch):
    class Bad(app_module.psycopg.Error):
        sqlstate = "22P02"

    def boom(*a, **k):
        raise Bad("invalid input syntax for type uuid")
    monkeypatch.setattr(app_module.db, "run", boom)
    tok = login_as(client, "CUSTOMER")
    assert client.post("/customer/cancel", data={"csrf": tok, "id": "x"}).status_code == 302


@pytest.mark.parametrize("price", ["nan", "inf", "-1", "1e12"])
def test_admin_tariff_rejects_non_finite_or_out_of_range(client, monkeypatch, price):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: called.append(1) or {"id": "n"})
    tok = login_as(client, "ADMIN")
    client.post("/admin/tariff", data={"csrf": tok, "id": "r", "price": price, "overtime": "0"})
    client.post("/admin/tariff", data={"csrf": tok, "id": "r", "kind": "parking", "hourly": price})
    assert not called


def test_admin_price_change_adds_a_new_version(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: pytest.fail("no direct UPDATE"))
    monkeypatch.setattr(app_module.db, "row", lambda sql, p=(): seen.append((sql, p)) or {"id": "n"})
    tok = login_as(client, "ADMIN")
    client.post("/admin/tariff", data={"csrf": tok, "id": "r1", "price": "3500", "overtime": "50000"})
    client.post("/admin/tariff", data={"csrf": tok, "id": "p1", "kind": "parking", "hourly": "18000"})
    assert "fn_change_tariff" in seen[0][0] and seen[0][1] == ("r1", 3500.0, 50000.0)
    assert "fn_change_parking_rate" in seen[1][0] and seen[1][1] == ("p1", 18000.0)


# ------------------------------------------------------------ phien sac
def test_manager_can_start_session(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append(sql) or 1)
    tok = login_as(client, "MANAGER")
    r = client.post("/manager/session/start",
                    data={"csrf": tok, "id": "e1", "plate": " 51a-123.45 ", "pct": "35", "fac": "f"})
    assert r.status_code == 302 and "INSERT INTO service_session" in calls[0]
    assert "start_battery_percent" in calls[0]
    assert "facility_manager" in calls[0]


def test_manager_can_stop_session(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append((sql, p)) or 1)
    tok = login_as(client, "MANAGER")
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"id": "t5"})
    client.post("/manager/session/stop", data={"csrf": tok, "id": "s1", "fac": "f"})
    sql, params = calls[0]
    assert "UPDATE service_session" in sql and "facility_manager" in sql
    assert "fn_session_estimate" in sql                         # computed, not typed in
    assert "kwh" not in str(params)


@pytest.mark.parametrize("pct", ["", "abc", "-1", "100", "nan"])
def test_start_session_needs_a_valid_battery_percent(client, monkeypatch, pct):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    tok = login_as(client, "MANAGER")
    client.post("/manager/session/start",
                data={"csrf": tok, "id": "e1", "plate": "51A-1", "pct": pct})
    assert not called and "% pin" in flashes(client)


def test_customer_cannot_start_session(client):
    tok = login_as(client, "CUSTOMER")
    r = client.post("/manager/session/start", data={"csrf": tok, "id": "e1", "plate": "x"})
    assert "/login" in r.headers["Location"]


# ------------------------------------------------------------ hoa don, bao mat
def test_failed_invoice_can_be_paid_again(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append(sql) or 1)
    tok = login_as(client, "CUSTOMER")
    client.post("/customer/pay", data={"csrf": tok, "id": "t1", "method": "E_WALLET"})
    assert "'FAILED'" in calls[0]


def test_customer_payment_waits_for_manager(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append(sql) or 1)
    tok = login_as(client, "CUSTOMER")
    client.post("/customer/pay", data={"csrf": tok, "id": "t1", "method": "E_WALLET"})
    assert "'PROCESSING'" in calls[0] and "'SUCCESS'" not in calls[0]
    assert "chờ quản lý xác nhận" in flashes(client)


def test_secret_key_is_not_the_public_default():
    assert app_module.app.secret_key != "dev-only-change-me"


def test_login_is_locked_after_repeated_failures(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: None)
    app_module.LOGIN_FAILS.clear()
    tok = csrf_of(client)
    data = {"csrf": tok, "email": "brute@x.vn", "password": "p"}
    for _ in range(5):
        client.post("/login", data=data)
    html = client.post("/login", data=data).get_data(as_text=True)
    assert "thử lại sau" in html
    app_module.LOGIN_FAILS.clear()


def test_overdue_job_runs_at_most_once_a_minute(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "row", lambda sql, p=(): calls.append(sql) or {"d": "2026-11-05"})
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): customer_rows(sql, p))
    monkeypatch.setattr(app_module, "_last_expire", 0.0)
    login_as(client, "CUSTOMER")
    client.get("/customer")
    client.get("/customer")
    assert sum("fn_expire_overdue_reservations" in s for s in calls) == 1


def test_db_message_hides_raw_text_for_malformed_values():
    assert app_module.db_message(FakeErr("22P02", "invalid input syntax")) == "Dữ liệu gửi lên không hợp lệ."


# ------------------------------------------------------------ phien dang nhap
@pytest.mark.parametrize("db_role", [None, "CUSTOMER"])
def test_session_ends_when_account_removed_or_role_changed(client, monkeypatch, db_role):
    login_as(client, "ADMIN")
    monkeypatch.setattr(app_module, "current_role", lambda uid: db_role)
    r = client.get("/admin")
    assert r.status_code == 302 and "/login" in r.headers["Location"]
    with client.session_transaction() as s:
        assert "role" not in s


def test_copied_cookie_is_useless_after_logout(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "id": "u1", "name": "T", "role": "ADMIN", "hash": generate_password_hash("dung"),
        "plain": "dung"})
    client.post("/login", data={"csrf": csrf_of(client), "email": "t@x.vn", "password": "dung"})
    copied = client.get_cookie("session").value
    with client.session_transaction() as s:
        tok = s.get("csrf")
    if not tok:
        client.get("/login")
        with client.session_transaction() as s:
            tok = s["csrf"]
        copied = client.get_cookie("session").value
    client.post("/logout", data={"csrf": tok})
    client.set_cookie("session", copied)
    r = client.get("/admin")
    assert r.status_code == 302 and "/login" in r.headers["Location"]


# ------------------------------------------------------------ gioi han dat cho
def book(client, tok, day):
    return client.post("/customer/book", data={
        "csrf": tok, "vehicle": "v", "space": "s", "day": day, "start": "10:00", "dur": "60"})


def flashes(client):
    with client.session_transaction() as s:
        return " ".join(m for _, m in s.get("_flashes", []))


def day_from_now(days):
    return (datetime.now(app_module.LOCAL_OFFSET) + timedelta(days=days)).strftime("%Y-%m-%d")


@pytest.mark.parametrize("days,active,unpaid,message", [
    (45, 0, 0, "30 ngày"), (2, 3, 0, "3 lượt"), (2, 0, 1, "hóa đơn")])
def test_booking_limits(client, monkeypatch, days, active, unpaid, message):
    called = []
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"active": active, "unpaid": unpaid})
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    book(client, login_as(client, "CUSTOMER"), day_from_now(days))
    assert not called and message in flashes(client)


def test_booking_within_limits_is_saved(client, monkeypatch):
    called = []
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"active": 2, "unpaid": 0})
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    book(client, login_as(client, "CUSTOMER"), day_from_now(2))
    assert called


def test_booking_waits_until_manager_confirms_payment(client, monkeypatch):
    called, seen = [], []
    monkeypatch.setattr(app_module.db, "row", lambda sql, p=(): seen.append(sql) or {"active": 0, "unpaid": 0, "waiting": 1})
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    book(client, login_as(client, "CUSTOMER"), day_from_now(2))
    assert not called and "chờ quản lý xác nhận" in flashes(client)
    assert any("'PROCESSING'" in s for s in seen)


# ------------------------------------------------------------ quan ly
def test_manager_can_check_in_parking_only_booking(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append(sql) or 1)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: None)
    tok = login_as(client, "MANAGER")
    r = client.post("/manager/reservation", data={"csrf": tok, "id": "x", "action": "arrive"})
    assert r.status_code == 302
    assert "INSERT INTO service_session" in calls[0] and "space_identifier" in calls[0]
    assert "facility_manager" in calls[0]


def test_manager_records_a_car_parking_on_a_space_without_charger(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append((sql, p)) or 1)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: None)
    tok = login_as(client, "MANAGER")
    r = client.post("/manager/parking/start",
                    data={"csrf": tok, "space": "sp1", "plate": " 51a-123.45 ", "fac": "f1"})
    assert r.status_code == 302
    sql, params = calls[-1]
    assert "INSERT INTO service_session" in sql and "space_identifier" in sql
    assert "facility_manager" in sql and params[:2] == ("sp1", "51A-123.45")


def test_confirm_excludes_overdue_bookings(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append(sql) or 1)
    tok = login_as(client, "MANAGER")
    client.post("/manager/reservation", data={"csrf": tok, "id": "x", "action": "confirm"})
    assert "end_datetime > now()" in calls[0] and "30 minutes" in calls[0]


def test_session_start_releases_overdue_bookings_first(client, monkeypatch):
    order = []
    monkeypatch.setattr(app_module.db, "row", lambda sql, p=(): order.append(sql))
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): order.append(sql) or 1)
    tok = login_as(client, "MANAGER")
    client.post("/manager/session/start", data={"csrf": tok, "id": "x", "plate": "a", "pct": "20"})
    assert "fn_expire_overdue_reservations" in order[0] and "INSERT INTO service_session" in order[1]


@pytest.mark.parametrize("constraint,message", [
    ("ck_session_early_arrival", "sớm"), ("ck_session_late_arrival", "30 phút"),
    ("ck_session_energy_battery", "pin"), ("ck_session_energy_power", "công suất"),
    ("ck_user_account_email", "Email"), ("ck_payment_confirmed_by_manager", "phụ trách bãi")])
def test_database_rules_are_explained_in_vietnamese(constraint, message):
    err = FakeErr("23514")
    err.diag = type("D", (), {"constraint_name": constraint})()
    assert message in app_module.db_message(err)


# ------------------------------------------------------------ quan tri
@pytest.mark.parametrize("override,message", [
    ({"email": "khongphaiemail"}, "Email"), ({"name": "   "}, "Họ tên"), ({"phone": "abc"}, "điện thoại")])
def test_admin_account_validates_identity(client, monkeypatch, override, message):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    tok = login_as(client, "ADMIN")
    data = {"csrf": tok, "role": "MANAGER", "name": "A", "phone": "0911111111",
            "email": "a@x.vn", "password": "12345678", "password2": "12345678", **override}
    client.post("/admin/accounts", data=data)
    assert not called and message in flashes(client)


def test_removing_missing_assignment_reports_it(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: 0)
    tok = login_as(client, "ADMIN")
    client.post("/admin/assign", data={"csrf": tok, "action": "remove", "facility": "f", "manager": "m"})
    assert "Không có phân công" in flashes(client)


# ------------------------------------------------------------ admin xoa / khoi phuc tai khoan
def fake_accounts(sql, p=()):
    if "deleted_datetime IS NOT NULL" in sql:
        return [{"id": "d1", "name": "Khach Da Xoa", "email": "d@x.vn", "role": "CUSTOMER",
                 "deleted": "14:00", "minutes_left": 12}]
    if "'CUSTOMER'" in sql and "license_plate_text" in sql:
        return [{"id": "c1", "name": "Khach A", "email": "a@x.vn", "phone": "0900000009",
                 "plates": "51A-1", "created": "01/11/2026"}]
    return [{"id": "m1", "name": "Quan Ly B", "email": "b@x.vn", "role": "MANAGER", "created": "01/11/2026"},
            {"id": "a1", "name": "Quan Tri C", "email": "c@x.vn", "role": "ADMIN", "created": "01/11/2026"}]


def account_info(charging=None, unpaid=0, owed=0):
    return {"id": "c1", "name": "Khach A", "email": "a@x.vn", "role": "CUSTOMER",
            "charging": charging, "unpaid": unpaid, "owed": owed}


def admin_with(monkeypatch, client, info=None, run=None, role="ADMIN"):
    seen = []

    def row(sql, p=()):
        seen.append(sql)
        return info
    monkeypatch.setattr(app_module.db, "rows", fake_accounts)
    monkeypatch.setattr(app_module.db, "row", row)
    monkeypatch.setattr(app_module.db, "run", run or (lambda *a, **k: 1))
    return login_as(client, role), seen


def test_accounts_tab_links_to_delete_except_for_admins(client, monkeypatch):
    admin_with(monkeypatch, client)
    html = client.get("/admin?tab=accounts").get_data(as_text=True)
    assert "delete=m1" in html and "delete=c1" in html and "delete=a1" not in html
    assert "/admin/accounts/delete" not in html


def test_accounts_tab_lists_deleted_accounts_with_restore_and_purges(client, monkeypatch):
    _, seen = admin_with(monkeypatch, client)
    html = client.get("/admin?tab=accounts").get_data(as_text=True)
    assert "Khach Da Xoa" in html and "/admin/accounts/restore" in html and "12 phút" in html
    assert any("fn_purge_deleted_accounts" in s for s in seen)


def test_delete_panel_warns_about_charging_and_unpaid_then_asks(client, monkeypatch):
    admin_with(monkeypatch, client, account_info(charging="51A-1", unpaid=2, owed=150000))
    html = client.get("/admin?tab=accounts&delete=c1").get_data(as_text=True)
    assert "đang sạc" in html and "51A-1" in html and "2 hóa đơn" in html and "150.000đ" in html
    assert "Xóa tài khoản a@x.vn không?" in html and "/admin/accounts/delete" in html
    assert 'name="ack" value="1"' in html


def test_delete_panel_without_warnings_just_asks(client, monkeypatch):
    admin_with(monkeypatch, client, account_info())
    html = client.get("/admin?tab=accounts&delete=c1").get_data(as_text=True)
    assert "Xóa tài khoản a@x.vn không?" in html and "Lưu ý trước khi xóa" not in html


def post_account(client, tok, action, **extra):
    return client.post(f"/admin/accounts/{action}", data={"csrf": tok, "id": "c1", **extra})


def test_delete_with_warnings_needs_acknowledgement(client, monkeypatch):
    calls = []
    tok, _ = admin_with(monkeypatch, client, account_info(unpaid=1, owed=5),
                        run=lambda sql, p=(): calls.append(sql) or 1)
    r = post_account(client, tok, "delete")
    assert not calls and "delete=c1" in r.headers["Location"]
    post_account(client, tok, "delete", ack="1")
    assert "SET deleted_datetime = now()" in calls[0] and "DELETE FROM" not in calls[0]
    assert "role_code IN ('CUSTOMER', 'MANAGER')" in calls[0]


def test_delete_refuses_admin_or_missing_account(client, monkeypatch):
    calls = []
    tok, _ = admin_with(monkeypatch, client, None, run=lambda *a, **k: calls.append(1) or 1)
    post_account(client, tok, "delete", ack="1")
    with client.session_transaction() as s:
        flashes = str(s.get("_flashes"))
    assert not calls and "Không có tài khoản" in flashes


def test_restore_clears_the_deletion_mark(client, monkeypatch):
    calls = []
    tok, _ = admin_with(monkeypatch, client, run=lambda sql, p=(): calls.append((sql, p)) or 1)
    post_account(client, tok, "restore")
    sql, params = calls[0]
    assert "SET deleted_datetime = NULL" in sql and "purged_datetime IS NULL" in sql and params == ("c1",)


def test_restore_explains_a_taken_email(client, monkeypatch):
    def run(*a, **k):
        raise app_module.psycopg.Error("duplicate")
    tok, _ = admin_with(monkeypatch, client, run=run)
    monkeypatch.setattr(app_module, "db_message", lambda err: "Giá trị đã tồn tại trong hệ thống.")
    post_account(client, tok, "restore")
    with client.session_transaction() as s:
        assert "Không khôi phục được" in str(s.get("_flashes"))


@pytest.mark.parametrize("role", ["CUSTOMER", "MANAGER"])
@pytest.mark.parametrize("action", ["delete", "restore"])
def test_only_admin_can_delete_or_restore(client, monkeypatch, role, action):
    calls = []
    tok, _ = admin_with(monkeypatch, client, account_info(),
                        run=lambda *a, **k: calls.append(1) or 1, role=role)
    r = post_account(client, tok, action, ack="1")
    assert r.status_code == 302 and "/login" in r.headers["Location"] and not calls


@pytest.mark.parametrize("constraint,text", [("ck_account_restore_expired", "30 phút"),
                                             ("ck_account_purged", "vĩnh viễn"),
                                             ("ck_account_admin", "quản trị")])
def test_account_refusals_are_explained(constraint, text):
    err = FakeErr("23514")
    err.diag = type("D", (), {"constraint_name": constraint})()
    assert text in app_module.db_message(err)


# ------------------------------------------------------------ tu tinh phien sac, xe dang do
def manager_rows(sql, params=()):
    if "facility_manager" in sql and "parking_facility" in sql and "FROM facility_manager" in sql:
        return [{"id": "f1", "name": "EV Hub Q1"}]
    if "FROM parking_space AS s" in sql:
        return [{"code": "A01", "status": "OCCUPIED", "eq_id": "e1", "conn": "FAST_DC", "kw": 60.0,
                 "eq_status": "CHARGING", "evse": "VN*E1", "plate": "51A-1", "kwh": 27.0,
                 "pct_now": 52.9, "full_text": None, "since": "13:30", "since_ms": 1793860200000,
                 "session_id": "s1", "next_ms": None, "next_booking": None},
                {"code": "A02", "status": "AVAILABLE", "eq_id": "e2", "conn": "STANDARD_AC", "kw": 22.0,
                 "eq_status": "READY", "evse": "VN*E2", "plate": None, "session_id": None,
                 "next_ms": None, "next_booking": None, "due_plate": None}]
    if "AS parked" not in sql and "AS owner" in sql:
        return [{"plate": "51A-123.45", "owner": "Nguyen Van A"},
                {"plate": "51K-999.99", "owner": "Le Van D"}]
    if "AS parked" in sql:
        return [{"code": "A01", "plate": "51A-1", "owner": "Khach A", "kind": "CHARGING",
                 "since": "13:30", "since_ms": 1793860200000, "until_text": None,
                 "kwh": 27.0, "pct_now": 52.9, "full_text": None},
                {"code": "B07", "plate": "51K-2", "owner": "Khach B", "kind": "PARKING",
                 "since": "14:00", "since_ms": 1793862000000, "until_text": "15:30",
                 "kwh": None, "pct_now": None, "full_text": None}]
    return []


def test_manager_picks_a_plate_from_a_list_and_types_battery_percent(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", manager_rows)
    login_as(client, "MANAGER")
    html = client.get("/manager").get_data(as_text=True)
    assert '<datalist id="plates"' in html and 'list="plates"' in html
    assert 'value="51A-123.45"' in html and "Nguyen Van A" in html
    assert 'name="pct"' in html


def test_manager_only_presses_stop_and_sees_the_estimate(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", manager_rows)
    login_as(client, "MANAGER")
    html = client.get("/manager").get_data(as_text=True)
    assert 'name="kwh"' not in html and 'name="idle"' not in html
    assert "27.0 kWh" in html and "52.9%" in html


def test_manager_sees_parked_vehicles_live(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", manager_rows)
    login_as(client, "MANAGER")
    html = client.get("/manager").get_data(as_text=True)
    assert "Xe đang đỗ" in html and 'data-refresh="/manager/parked?fac=f1"' in html
    part = client.get("/manager/parked?fac=f1").get_data(as_text=True)
    assert "51A-1" in part and "51K-2" in part and "Đang sạc" in part and "Chỉ đỗ" in part
    assert "<html" not in part and 'data-live="elapsed"' in part


def test_parked_list_is_limited_to_assigned_facilities(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): seen.append(sql) or manager_rows(sql, p))
    login_as(client, "MANAGER")
    assert client.get("/manager/parked?fac=khong-phu-trach").status_code == 404
    assert not any("AS parked" in s for s in seen)


def test_parked_list_is_for_managers_only(client):
    login_as(client, "CUSTOMER")
    assert "/login" in client.get("/manager/parked?fac=f1").headers["Location"]


# ------------------------------------------------------------ khach them xe
def test_customer_sees_own_vehicles_and_add_form(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", customer_rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"d": "2026-11-05"})
    login_as(client, "CUSTOMER")
    html = client.get("/customer").get_data(as_text=True)
    assert "Xe của tôi" in html and "/customer/vehicle" in html and 'name="battery"' in html


def test_customer_adds_a_vehicle_to_own_account(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append((sql, p)) or 1)
    tok = login_as(client, "CUSTOMER")
    r = client.post("/customer/vehicle", data={"csrf": tok, "plate": " 51g-555.55 ", "battery": "75,5"})
    assert r.status_code == 302
    sql, params = calls[0]
    assert "INSERT INTO vehicle" in sql
    assert params == ("00000000-0000-0000-0000-000000000001", "51G-555.55", "75.50")
    assert "Đã thêm xe" in flashes(client)


@pytest.mark.parametrize("plate,battery", [("", "60"), ("51A-1", "0"), ("51A-1", "abc"),
                                           ("51A-1", "600"), ("X" * 21, "60")])
def test_customer_vehicle_input_is_checked(client, monkeypatch, plate, battery):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    tok = login_as(client, "CUSTOMER")
    client.post("/customer/vehicle", data={"csrf": tok, "plate": plate, "battery": battery})
    assert not called


def test_customer_vehicle_duplicate_plate_is_explained(client, monkeypatch):
    class Dup(app_module.psycopg.Error):
        sqlstate = "23505"
        diag = types.SimpleNamespace(constraint_name="ux_vehicle_license_plate")

    def run(*a, **k):
        raise Dup("duplicate key")
    monkeypatch.setattr(app_module.db, "run", run)
    tok = login_as(client, "CUSTOMER")
    client.post("/customer/vehicle", data={"csrf": tok, "plate": "51A-1", "battery": "60"})
    assert "Biển số" in flashes(client)


def test_only_customers_add_vehicles(client):
    tok = login_as(client, "MANAGER")
    r = client.post("/customer/vehicle", data={"csrf": tok, "plate": "51A-1", "battery": "60"})
    assert "/login" in r.headers["Location"]


# ------------------------------------------------------------ admin xem mat khau
def test_admin_sees_passwords_of_accounts(client, monkeypatch):
    def rows(sql, p=()):
        out = fake_accounts(sql, p)
        for i, a in enumerate(out):
            a["password"] = "MatKhau-%d" % i if i == 0 else None
        return out
    admin_with(monkeypatch, client)
    monkeypatch.setattr(app_module.db, "rows", rows)
    html = client.get("/admin?tab=accounts").get_data(as_text=True)
    assert "Mật khẩu" in html and "MatKhau-0" in html and "Chưa lưu" in html
    assert "/admin/accounts/password" in html


def test_admin_reset_password_stores_and_shows_it(client, monkeypatch):
    calls = []
    admin_with(monkeypatch, client, run=lambda sql, p=(): calls.append((sql, p)) or 1)
    tok = login_as(client, "ADMIN")
    client.post("/admin/accounts/password", data={"csrf": tok, "id": "c1"})
    sql, params = calls[0]
    assert "password_hash_text" in sql and "password_plain_text" in sql
    from werkzeug.security import check_password_hash
    hashed, plain = params[0], params[1]
    assert len(plain) >= 8 and check_password_hash(hashed, plain)
    assert plain in flashes(client)


def test_admin_created_account_keeps_viewable_password(client, monkeypatch):
    calls = []
    admin_with(monkeypatch, client, run=lambda sql, p=(): calls.append((sql, p)) or 1)
    tok = login_as(client, "ADMIN")
    client.post("/admin/accounts", data={"csrf": tok, "role": "MANAGER", "name": "Quan Ly",
                                         "email": "ql@x.vn", "phone": "0901234560",
                                         "password": "matkhau99", "password2": "matkhau99"})
    assert "password_plain_text" in calls[0][0] and "matkhau99" in calls[0][1]


def test_login_records_password_for_older_accounts(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "id": "u1", "name": "Test", "role": "CUSTOMER", "hash": generate_password_hash("dungroi1"),
        "plain": None})
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append((sql, p)) or 1)
    client.post("/login", data={"csrf": csrf_of(client), "email": "t@x.vn", "password": "dungroi1"})
    assert calls and "password_plain_text" in calls[0][0] and "dungroi1" in calls[0][1]


def test_login_does_not_rewrite_a_known_password(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "id": "u1", "name": "Test", "role": "CUSTOMER", "hash": generate_password_hash("dungroi1"),
        "plain": "dungroi1"})
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append((sql, p)) or 1)
    client.post("/login", data={"csrf": csrf_of(client), "email": "t@x.vn", "password": "dungroi1"})
    assert not calls


# ------------------------------------------------------------ quan ly xac nhan thanh toan
@pytest.mark.parametrize("action,status", [("confirm", "'SUCCESS'"), ("reject", "'FAILED'")])
def test_manager_confirms_or_rejects_payment_in_own_facility(client, monkeypatch, action, status):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, p=(): calls.append((sql, p)) or 1)
    tok = login_as(client, "MANAGER")
    client.post("/manager/payment", data={"csrf": tok, "id": "t1", "action": action, "fac": "f1"})
    sql, params = calls[0]
    assert status in sql and "'PROCESSING'" in sql and "facility_manager" in sql
    assert "confirmed_by_identifier" in sql                     # who confirmed is recorded
    uid = "00000000-0000-0000-0000-000000000001"
    assert params == (uid, "t1", uid)


def test_manager_payment_rejects_unknown_action(client, monkeypatch):
    called = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: called.append(1) or 1)
    tok = login_as(client, "MANAGER")
    assert client.post("/manager/payment", data={"csrf": tok, "id": "t1", "action": "x"}).status_code == 400
    assert not called


def test_only_managers_confirm_payments(client):
    tok = login_as(client, "CUSTOMER")
    r = client.post("/manager/payment", data={"csrf": tok, "id": "t1", "action": "confirm"})
    assert "/login" in r.headers["Location"]


def test_manager_sees_payments_waiting_for_confirmation(client, monkeypatch):
    def rows(sql, p=()):
        if "'PROCESSING'" in sql:
            return [{"id": "t9", "code": "A01", "plate": "51A-1", "customer": "Khach A",
                     "total": 182000.0, "method": "E_WALLET", "ref": "DEMO-ABC", "paid_text": "15:20"}]
        return manager_rows(sql, p)
    monkeypatch.setattr(app_module.db, "rows", rows)
    login_as(client, "MANAGER")
    html = client.get("/manager").get_data(as_text=True)
    assert "DEMO-ABC" in html and "182.000đ" in html and "/manager/payment" in html
    assert 'value="confirm"' in html and 'value="reject"' in html


def test_customer_sees_waiting_invoice_without_pay_button(client, monkeypatch):
    def rows(sql, p=()):
        if "FROM payment_transaction AS p" in sql:
            return [{"id": "t9", "day_text": "26/11 15:00", "plate": "51A-1", "band": "PEAK", "kwh": 10.0,
                     "energy": 40000.0, "overtime": 0.0, "total": 40000.0, "status": "PROCESSING",
                     "method": "E_WALLET"}]
        return customer_rows(sql, p)
    monkeypatch.setattr(app_module.db, "rows", rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"d": "2026-11-05"})
    login_as(client, "CUSTOMER")
    html = client.get("/customer").get_data(as_text=True)
    assert "Chờ quản lý xác nhận" in html and "/customer/pay" not in html


# ------------------------------------------------------------ chi tiet hoa don sau khi ket thuc phien
INVOICE = {"id": "t5", "facility": "EV Hub Q1", "code": "A01", "evse": "VN*E1", "kw": 60.0,
           "customer": "Khach A", "phone": "0901234567", "plate": "51A-123.45",
           "start_text": "26/11 14:00", "end_text": "26/11 16:00", "full_text": "26/11 15:13",
           "minutes": 120, "pct_start": 20.0, "pct_end": 100.0, "kwh": 65.6,
           "band": "STANDARD", "price": 3200.0, "energy": 209920.0, "overtime_hours": 0.78,
           "fee": 45000.0, "overtime": 35100.0, "total": 245020.0, "status": "PENDING",
           "created_text": "26/11 16:00"}


def test_stopping_a_session_opens_the_invoice(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "run", lambda *a, **k: 1)
    monkeypatch.setattr(app_module.db, "row", lambda sql, p=(): seen.append((sql, p)) or {"id": "t5"})
    tok = login_as(client, "MANAGER")
    r = client.post("/manager/session/stop", data={"csrf": tok, "id": "s1", "fac": "f1"})
    assert "invoice=t5" in r.headers["Location"] and "fac=f1" in r.headers["Location"]
    assert "payment_transaction" in seen[0][0] and "s1" in seen[0][1]


def test_manager_page_shows_invoice_details(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "rows", manager_rows)
    monkeypatch.setattr(app_module.db, "row", lambda sql, p=(): seen.append(sql) or dict(INVOICE))
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1&invoice=t5").get_data(as_text=True)
    assert "Chi tiết hóa đơn" in html
    for text in ("Khach A", "51A-123.45", "65.60 kWh", "3.200đ", "209.920đ", "35.100đ",
                 "245.020đ", "20% → 100%", "26/11 15:13", "120 phút"):
        assert text in html, text
    assert any("facility_manager" in s for s in seen)       # only the manager's own facilities


def test_invoice_outside_own_facilities_is_not_shown(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", manager_rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: None)
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1&invoice=khac").get_data(as_text=True)
    assert "Chi tiết hóa đơn" not in html


# ------------------------------------------------------------ lich dat va thanh thoi gian
TIMELINE = [{"facility": "EV Hub Q1", "code": "A01", "segs": [
                {"kind": "busy", "left": 50.0, "width": 8.33, "label": "12:00–14:00 · 51A-1 · Khach A"},
                {"kind": "booked", "left": 66.67, "width": 4.17, "label": "16:00–17:00 · 51K-2 · Khach B"}]},
            {"facility": "EV Hub Q1", "code": "A02", "segs": []}]
BOOKINGS = [{"id": "r1", "facility": "EV Hub Q1", "code": "A01", "start_text": "16:00", "end_text": "17:00",
             "plate": "51K-2", "battery": 82.0, "customer": "Khach B", "phone": "0901111222",
             "email": "b@x.vn", "status": "CONFIRMED", "session_text": None, "kwh": None,
             "invoice_total": None, "invoice_status": None}]


def schedule_rows(sql, params=()):
    if "-- timeline" in sql:
        return TIMELINE
    if "-- booking_list" in sql:
        return BOOKINGS
    return manager_rows(sql, params)


def test_manager_sees_bookings_with_vehicle_and_customer(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", schedule_rows)
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1").get_data(as_text=True)
    assert "Lịch đặt chỗ" in html
    for text in ("51K-2", "Khach B", "0901111222", "b@x.vn", "82 kWh", "Đã xác nhận"):
        assert text in html, text


def test_manager_sees_colour_timeline_per_space(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", schedule_rows)
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1").get_data(as_text=True)
    assert 'class="tl-seg busy"' in html and 'class="tl-seg booked"' in html
    assert "left:50.0%" in html and "Trống" in html and "Đã đặt" in html and "Đang sử dụng" in html
    assert 'class="tl-now"' in html                                   # today shows a now marker


def test_manager_schedule_uses_the_chosen_day(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): seen.append((sql, p)) or schedule_rows(sql, p))
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1&day=2026-12-01").get_data(as_text=True)
    assert any("-- timeline" in s and "2026-12-01" in p for s, p in seen)
    assert 'value="2026-12-01"' in html and 'class="tl-now"' not in html
    client.get("/manager?fac=f1&day=khong-hop-le")                    # bad day falls back to today


def test_manager_schedule_part_refreshes(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", schedule_rows)
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1").get_data(as_text=True)
    assert 'data-refresh="/manager/schedule?fac=f1' in html
    part = client.get("/manager/schedule?fac=f1").get_data(as_text=True)
    assert "<html" not in part and "51K-2" in part and "tl-seg" in part
    assert client.get("/manager/schedule?fac=khac").status_code == 404


# ------------------------------------------------------------ admin doi soat lich dat
ANOMALIES = [{"kind": "OVERDUE", "facility": "EV Hub Q1", "code": "A03", "detail": "51A-9 · 08:00"},
             {"kind": "OCCUPIED_NO_SESSION", "facility": "EV Hub Q1", "code": "A04", "detail": ""},
             {"kind": "WAITING_PAYMENT", "facility": "EV Hub Q2", "code": "B01", "detail": "51A-7 · 45 phút"}]
SUMMARY = [{"facility": "EV Hub Q1", "spaces": 12, "occupied": 3, "reserved": 2, "bookings": 9,
            "pending": 1, "confirmed": 3, "fulfilled": 4, "cancelled": 1, "expired": 0,
            "sessions": 5, "waiting": 1, "revenue": 1250000.0}]


def reconcile_rows(sql, params=()):
    if "-- timeline" in sql:
        return TIMELINE
    if "-- booking_list" in sql:
        return [dict(BOOKINGS[0], session_text="16:02–16:50", kwh=20.5,
                     invoice_total=56000.0, invoice_status="PROCESSING")]
    if "-- anomalies" in sql:
        return ANOMALIES
    if "-- reconcile_summary" in sql:
        return SUMMARY
    if "FROM parking_facility" in sql:
        return [{"id": "f1", "name": "EV Hub Q1"}]
    return []


def test_admin_reconciles_bookings_in_real_time(client, monkeypatch):
    monkeypatch.setattr(app_module.db, "rows", reconcile_rows)
    login_as(client, "ADMIN")
    html = client.get("/admin?tab=bookings").get_data(as_text=True)
    assert "Đối soát lịch đặt" in html and 'data-refresh="/admin/reconcile' in html
    for text in ("Quá giờ nhận chỗ", "Ô đang sử dụng nhưng không có phiên", "chờ quản lý xác nhận",
                 "1.250.000đ", "16:02–16:50", "56.000đ", "tl-seg busy", "Khach B"):
        assert text in html, text


def test_admin_reconcile_filters_are_passed_to_queries(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): seen.append((sql, p)) or reconcile_rows(sql, p))
    login_as(client, "ADMIN")
    part = client.get("/admin/reconcile?day=2026-12-01&fac=f1&status=CONFIRMED").get_data(as_text=True)
    assert "<html" not in part
    booking = [p for s, p in seen if "-- booking_list" in s][0]
    assert "2026-12-01" in booking and "f1" in booking and "CONFIRMED" in booking


def test_admin_reconcile_rejects_unknown_status(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): seen.append((sql, p)) or reconcile_rows(sql, p))
    login_as(client, "ADMIN")
    client.get("/admin/reconcile?status=DROP")
    booking = [p for s, p in seen if "-- booking_list" in s][0]
    assert "DROP" not in booking


def test_reconcile_is_for_admins_only(client):
    login_as(client, "MANAGER")
    assert "/login" in client.get("/admin/reconcile").headers["Location"]


def test_overdue_anomaly_matches_the_release_rule():
    sql = app_module.ANOMALY_SQL
    part = sql[sql.index("'OVERDUE'"):sql.index("'OCCUPIED_NO_SESSION'")]
    assert "INTERVAL '%d minutes'" % app_module.GRACE_MIN in part      # same grace as the release
    assert "service_session" in part                                  # a started session is not overdue


# ------------------------------------------------------------ bieu gia tach khung gio
def test_api_time_reads_band_schedule_from_window_table(client, monkeypatch):
    seen = []
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {
        "epoch_ms": 1793862000000, "local_iso": "2026-11-05T14:00:00"})
    monkeypatch.setattr(app_module.db, "rows", lambda sql, p=(): seen.append(sql) or BANDS)
    client.get("/api/time")
    assert "FROM time_band_window" in seen[0] and "tariff_rate" not in seen[0]


def test_admin_tariff_tab_shows_window_schedule_and_prices(client, monkeypatch):
    def rows(sql, p=()):
        if "FROM time_band_window" in sql:
            return [{"band": "PEAK", "from_text": "17:00", "to_text": "20:00"},
                    {"band": "OFF_PEAK", "from_text": "22:00", "to_text": "24:00"}]
        if "FROM tariff_rate" in sql:
            assert "start_time" not in sql
            return [{"id": "r1", "conn": "FAST_DC", "band": "PEAK", "min_kw": 0.0, "max_kw": 100.0,
                     "price": 3300.0, "overtime": 60000.0}]
        return []
    monkeypatch.setattr(app_module.db, "rows", rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {})
    login_as(client, "ADMIN")
    html = client.get("/admin?tab=tariff").get_data(as_text=True)
    assert "time_band_window" in html and "17:00–20:00" in html and "22:00–24:00" in html
    assert 'value="3300"' in html and 'value="60000"' in html


# ------------------------------------------------------------ phi do xe
def test_manager_page_shows_parking_invoice(client, monkeypatch):
    bill = dict(INVOICE, parking_only=True, hours=1.5, hourly=20000.0, parking=30000.0,
                energy=0.0, overtime=0.0, total=30000.0, evse=None, kw=None)
    monkeypatch.setattr(app_module.db, "rows", manager_rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: dict(bill))
    login_as(client, "MANAGER")
    html = client.get("/manager?fac=f1&invoice=t5").get_data(as_text=True)
    assert "Phí đỗ xe" in html and "1.50 giờ × 20.000đ" in html and "30.000đ" in html
    assert "kWh ×" not in html


def test_customer_sees_running_parking_fee(client, monkeypatch):
    def rows(sql, p=()):
        if "-- parking_sessions" in sql:
            return [{"plate": "51A-1", "code": "A-12", "facility": "EV Hub Q1", "band": "PEAK",
                     "hourly": 20000.0, "since": "18:00", "so_far": 25000.0}]
        return customer_rows(sql, p)
    monkeypatch.setattr(app_module.db, "rows", rows)
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"d": "2026-11-05"})
    login_as(client, "CUSTOMER")
    html = client.get("/customer").get_data(as_text=True)
    assert "Xe đang đỗ" in html and "20.000đ/giờ" in html and "25.000đ" in html
