"""Kiem thu don vi cho demo_app (Flask) - KHONG can ket noi CSDL.

CSDL duoc thay bang ham gia (monkeypatch) nen test chay nhanh va doc lap.
Cac rang buoc nghiep vu cua CSDL duoc kiem thu rieng trong tests.sql.
"""
import sys
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
        "id": "u1", "name": "Test", "role": role, "hash": generate_password_hash("dung")})
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
    assert params[4:] == ("51A-123.45", "60.50")                 # plate upper-cased, kWh normalised


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


def test_admin_sets_manager_password_and_it_is_not_echoed(client, monkeypatch):
    calls = []
    monkeypatch.setattr(app_module.db, "run", lambda sql, params=(): calls.append(params) or 1)
    monkeypatch.setattr(app_module.db, "rows", lambda *a, **k: [])
    monkeypatch.setattr(app_module.db, "row", lambda *a, **k: {"revenue": 0})
    r = post_admin_account(client)
    from werkzeug.security import check_password_hash
    assert check_password_hash(calls[0][3], "matkhau123") and calls[0][4] == "MANAGER"
    assert "matkhau123" not in r.get_data(as_text=True)


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
