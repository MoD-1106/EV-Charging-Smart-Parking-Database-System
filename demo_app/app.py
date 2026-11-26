"""Smart City EV Charging & Parking - demo web app (Flask + PostgreSQL).

Roles come from user_account.role_code: CUSTOMER, MANAGER, ADMIN.
Run:  DATABASE_URL=postgresql://user:pass@localhost:5432/evt flask --app app run
"""
import functools
import math
import os
import re
import secrets
import time
from datetime import datetime, timedelta, timezone

import psycopg
from flask import (Flask, abort, flash, jsonify, redirect, render_template,
                   request, session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

import db

app = Flask(__name__)
# Without SECRET_KEY a random key is used, so everyone is logged out on restart.
app.secret_key = os.environ.get("SECRET_KEY") or secrets.token_hex(32)
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")

TZ = "Asia/Ho_Chi_Minh"
LOCAL_OFFSET = timezone(timedelta(hours=7))  # Asia/Ho_Chi_Minh has no DST
MIN_PASSWORD = 8
PHONE_RE = re.compile(r"^\+?[0-9]{8,14}$")   # same rule as ck_user_account_phone
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
DUPLICATE_MESSAGE = {
    "ux_user_account_email": "Email này đã được đăng ký.",
    "ux_user_account_phone": "Số điện thoại này đã được đăng ký.",
    "ux_vehicle_license_plate": "Biển số xe này đã được đăng ký.",
}
GRACE_MIN = 30  # reservation is released this long after its start (business rule)
DURATIONS = (30, 60, 90, 120, 180, 240)   # booking lengths offered, in minutes
MAX_PRICE = 1_000_000                     # VND, sanity limit for tariff input
MAX_SESSION_KWH = 500
MAX_LOGIN_FAILS, LOCK_SECONDS = 5, 300
LOGIN_FAILS = {}   # (address, email) -> (failures, time of last one); per process
REVOKED = set()    # session ids that were logged out; per process
MAX_ACTIVE_BOOKINGS, MAX_ADVANCE_DAYS = 3, 30
_last_expire = 0.0
CONSTRAINT_MESSAGE = {
    "ux_service_session_open_vehicle": "Xe này đang sạc ở một trụ khác.",
    "ux_service_session_open_equipment": "Trụ này đang có xe sạc.",
    "ex_reservation_vehicle_no_overlap": "Xe này đã có lịch đặt chồng khung giờ.",
    "ck_session_early_arrival": "Xe này có lượt đặt ở ô này: chỉ nhận xe sớm tối đa 15 phút.",
    "ck_session_late_arrival": "Lượt đặt đã trễ quá 30 phút nên không dùng được nữa.",
    "ck_session_energy_battery": "Số kWh lớn hơn dung lượng pin của xe (cho phép hao hụt 10%).",
    "ck_session_energy_power": "Số kWh vượt quá công suất trụ nhân thời gian đã sạc.",
    "ck_user_account_email": "Email không hợp lệ.",
    "ck_user_account_name": "Họ tên không được để trống.",
}
HOME = {"CUSTOMER": "customer", "MANAGER": "manager", "ADMIN": "admin"}
BAND_NAME = {"PEAK": "Cao điểm", "STANDARD": "Bình thường", "OFF_PEAK": "Thấp điểm"}
STATUS_NAME = {"AVAILABLE": "Trống", "RESERVED": "Đã giữ chỗ", "OCCUPIED": "Đang sử dụng",
               "OUTOFSERVICE": "Ngừng hoạt động"}
RES_NAME = {"PENDING": "Chờ xác nhận", "CONFIRMED": "Đã xác nhận", "FULFILLED": "Đã sử dụng",
            "CANCELLED": "Đã hủy", "EXPIRED": "Hết hạn"}
PAY_NAME = {"PENDING": "Chờ thanh toán", "SUCCESS": "Đã thanh toán", "FAILED": "Thất bại",
            "REFUNDED": "Hoàn tiền"}
METHODS = {"E_WALLET": "Ví điện tử", "CREDIT_CARD": "Thẻ", "BANK_TRANSFER": "Chuyển khoản"}


# ---------------------------------------------------------------- helpers
@app.template_filter("vnd")
def vnd(value):
    return f"{int(round(float(value or 0))):,}".replace(",", ".") + "đ"


@app.context_processor
def inject():
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(16)
    return dict(csrf=session["csrf"], BAND_NAME=BAND_NAME, STATUS_NAME=STATUS_NAME,
                RES_NAME=RES_NAME, PAY_NAME=PAY_NAME, METHODS=METHODS, tz=TZ, GRACE_MIN=GRACE_MIN,
                user=session.get("name"), role=session.get("role"))


@app.before_request
def check_csrf():
    if request.method == "POST":
        token = session.get("csrf")
        if not token or request.form.get("csrf") != token:   # no session token = reject
            abort(400, "Phiên làm việc không hợp lệ, hãy tải lại trang.")


@app.before_request
def expire_overdue():
    """Release overdue reservations (stands in for pg_cron), at most once a minute."""
    global _last_expire
    if (request.method != "GET" or request.endpoint not in ("customer", "manager", "admin")
            or not session.get("role")):
        return
    now = time.monotonic()
    if _last_expire and now - _last_expire < 60:
        return
    _last_expire = now
    release_overdue()


@app.errorhandler(psycopg.Error)
def bad_input(err):
    """A malformed id or number (SQLSTATE class 22) is a bad request, not a crash."""
    if not str(getattr(err, "sqlstate", "") or "").startswith("22"):
        raise err
    flash("Dữ liệu gửi lên không hợp lệ.", "err")
    return redirect(url_for("index"))


def current_role(uid):
    """Role of a still active account, or None."""
    found = db.row("SELECT role_code AS role FROM user_account "
                   "WHERE account_identifier = %s::uuid AND deleted_datetime IS NULL", (uid,))
    return found["role"] if found else None


@app.before_request
def check_session():
    """A signed cookie alone is not enough: the session must not have been logged
    out, and the account must still exist with the same role."""
    if request.endpoint == "static" or not session.get("role"):
        return
    if session.get("sid") in REVOKED or current_role(session.get("uid")) != session["role"]:
        session.clear()
        flash("Phiên đăng nhập đã hết hiệu lực, hãy đăng nhập lại.", "err")
        return redirect(url_for("login"))


def release_overdue():
    try:
        db.row("SELECT fn_expire_overdue_reservations()")
    except psycopg.Error:
        app.logger.warning("could not expire overdue reservations", exc_info=True)


def role_required(*roles):
    def deco(fn):
        @functools.wraps(fn)
        def wrapper(*a, **kw):
            if session.get("role") not in roles:
                return redirect(url_for("login"))
            return fn(*a, **kw)
        return wrapper
    return deco


def db_message(err):
    """Translate constraint / trigger errors into readable Vietnamese text."""
    code = getattr(err, "sqlstate", None)
    constraint = getattr(getattr(err, "diag", None), "constraint_name", None)
    if constraint in CONSTRAINT_MESSAGE:
        return CONSTRAINT_MESSAGE[constraint]
    if str(code or "").startswith("22"):
        return "Dữ liệu gửi lên không hợp lệ."
    if code == "23P01":
        return "Khung giờ này đã có người đặt hoặc bị chồng lịch."
    if code == "23514":
        text = str(err).splitlines()[0]
        return "Dữ liệu không hợp lệ: " + text
    if code == "23505":
        return "Giá trị đã tồn tại trong hệ thống."
    return str(err).splitlines()[0]


def local_window(day, start, minutes):
    begin = datetime.strptime(f"{day} {start}", "%Y-%m-%d %H:%M")
    end = begin + timedelta(minutes=minutes)
    return begin.strftime("%Y-%m-%d %H:%M"), end.strftime("%Y-%m-%d %H:%M")


def local_ms(text):
    """Epoch milliseconds of a local 'YYYY-MM-DD HH:MM' string (Asia/Ho_Chi_Minh)."""
    parsed = datetime.strptime(text, "%Y-%m-%d %H:%M").replace(tzinfo=LOCAL_OFFSET)
    return int(parsed.timestamp() * 1000)


def band_at(bands, minute):
    """Tariff band covering a minute of the day, or None."""
    for b in sorted(bands, key=lambda x: x["s"]):
        if b["s"] <= minute < b["e"]:
            return b["band"]
    return None


def band_info(bands, minute):
    """Current band and how many minutes until a different band applies."""
    current = band_at(bands, minute)
    if current is None:
        return None
    for step in range(1, 1441):
        nxt = band_at(bands, (minute + step) % 1440)
        if nxt != current:
            return {"band": current, "next_band": nxt, "minutes_to_change": step}
    return {"band": current, "next_band": None, "minutes_to_change": None}


# ---------------------------------------------------------------- auth
@app.route("/")
def index():
    return redirect(url_for(HOME.get(session.get("role"), "login")))


@app.get("/api/time")
def api_time():
    """Server clock (database now()) plus the tariff band in force."""
    found = db.row(
        """SELECT (extract(epoch FROM now()) * 1000)::bigint AS epoch_ms,
                  to_char(now() AT TIME ZONE %s, 'YYYY-MM-DD"T"HH24:MI:SS') AS local_iso""",
        (TZ,))
    epoch_ms = int(found["epoch_ms"])
    payload = {"epoch_ms": epoch_ms, "local_iso": found["local_iso"], "tz": TZ}
    try:
        bands = db.rows(
            """SELECT DISTINCT time_band_code AS band,
                      (extract(epoch FROM start_time) / 60)::int AS s,
                      (extract(epoch FROM end_time) / 60)::int AS e
               FROM tariff_rate""")
    except psycopg.Error:
        bands = []
    hour, minute = int(found["local_iso"][11:13]), int(found["local_iso"][14:16])
    info = band_info(bands, hour * 60 + minute)
    if info:
        payload.update(band=info["band"], band_name=BAND_NAME[info["band"]])
        if info["minutes_to_change"] is not None:
            payload.update(
                next_band=info["next_band"],
                next_band_name=BAND_NAME.get(info["next_band"], "ngoài biểu giá"),
                change_epoch_ms=epoch_ms - epoch_ms % 60000 + info["minutes_to_change"] * 60000)
    resp = jsonify(payload)
    resp.headers["Cache-Control"] = "no-store"
    return resp


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        key = (request.remote_addr, request.form.get("email", "").strip().lower())
        fails, last = LOGIN_FAILS.get(key, (0, 0.0))
        if fails and time.monotonic() - last >= LOCK_SECONDS:
            fails = 0
        if fails >= MAX_LOGIN_FAILS:
            flash("Sai mật khẩu quá nhiều lần, hãy thử lại sau vài phút.", "err")
            return render_template("login.html")
        found = db.row(
            """SELECT account_identifier::text AS id, full_name_text AS name,
                      role_code AS role, password_hash_text AS hash
               FROM user_account
               WHERE lower(email_address) = lower(%s) AND deleted_datetime IS NULL""",
            (request.form.get("email", "").strip(),))
        ok = False
        if found:
            try:
                ok = check_password_hash(found["hash"], request.form.get("password", ""))
            except ValueError:
                ok = False
        if ok:
            LOGIN_FAILS.pop(key, None)
            session.clear()
            session.update(uid=found["id"], name=found["name"], role=found["role"],
                           sid=secrets.token_urlsafe(16))
            return redirect(url_for(HOME[found["role"]]))
        LOGIN_FAILS[key] = (fails + 1, time.monotonic())
        flash("Email hoặc mật khẩu không đúng.", "err")
    return render_template("login.html")


def validate_registration(f, password, confirm):
    """Return (error_message, cleaned_values). error_message is None when valid."""
    v = {
        "name": f.get("name", "").strip(),
        "email": f.get("email", "").strip(),
        "phone": f.get("phone", "").strip(),
        "plate": f.get("plate", "").strip().upper(),
        "battery": f.get("battery", "").strip().replace(",", "."),
    }
    if not 1 <= len(v["name"]) <= 100:
        return "Họ tên phải từ 1 đến 100 ký tự.", v
    if len(v["email"]) > 255 or not EMAIL_RE.match(v["email"]):
        return "Email không hợp lệ.", v
    if not PHONE_RE.match(v["phone"]):
        return "Số điện thoại gồm 8 đến 14 chữ số, có thể bắt đầu bằng +.", v
    if not 1 <= len(v["plate"]) <= 20:
        return "Biển số xe phải từ 1 đến 20 ký tự.", v
    try:
        battery = float(v["battery"])
    except ValueError:
        return "Dung lượng pin phải là số (kWh).", v
    if not 0 < battery <= 500:
        return "Dung lượng pin phải lớn hơn 0 và không quá 500 kWh.", v
    if len(password) < MIN_PASSWORD:
        return f"Mật khẩu phải có ít nhất {MIN_PASSWORD} ký tự.", v
    if password != confirm:
        return "Hai mật khẩu không khớp.", v
    v["battery"] = f"{battery:.2f}"
    return None, v


@app.route("/register", methods=["GET", "POST"])
def register():
    """Public sign-up. The role is always CUSTOMER; the first vehicle is created
    in the same statement so a new customer can book straight away."""
    if session.get("role"):
        return redirect(url_for("index"))
    values = {}
    if request.method == "POST":
        error, values = validate_registration(
            request.form, request.form.get("password", ""), request.form.get("password2", ""))
        if error:
            flash(error, "err")
        else:
            try:
                db.run(
                    """WITH new_user AS (
                           INSERT INTO user_account (full_name_text, contact_phone_number,
                                                     email_address, password_hash_text, role_code)
                           VALUES (%s, %s, %s, %s, 'CUSTOMER')
                           RETURNING account_identifier)
                       INSERT INTO vehicle (account_identifier, license_plate_text,
                                            battery_capacity_kwh)
                       SELECT account_identifier, %s, %s::numeric FROM new_user""",
                    (values["name"], values["phone"], values["email"],
                     generate_password_hash(request.form["password"]),
                     values["plate"], values["battery"]))
                flash("Đăng ký thành công. Hãy đăng nhập để đặt chỗ.", "ok")
                return redirect(url_for("login"))
            except psycopg.Error as err:
                constraint = getattr(getattr(err, "diag", None), "constraint_name", None)
                flash(DUPLICATE_MESSAGE.get(constraint) or db_message(err), "err")
    return render_template("register.html", form=values)


@app.post("/logout")
def logout():
    if session.get("sid"):
        REVOKED.add(session["sid"])
    session.clear()
    return redirect(url_for("login"))


# ---------------------------------------------------------------- customer
@app.route("/customer")
@role_required("CUSTOMER")
def customer():
    uid = session["uid"]
    vehicles = db.rows(
        """SELECT vehicle_identifier::text AS id, license_plate_text AS plate,
                  battery_capacity_kwh::float AS kwh
           FROM vehicle WHERE account_identifier = %s::uuid AND deleted_datetime IS NULL
           ORDER BY license_plate_text""", (uid,))
    facilities = db.rows(
        """SELECT facility_identifier::text AS id, facility_name_text AS name,
                  address_text AS addr FROM parking_facility ORDER BY facility_name_text""")
    fac_id = request.args.get("fac")
    if fac_id not in [f["id"] for f in facilities]:
        fac_id = facilities[0]["id"] if facilities else None
    day = request.args.get("day") or db.row(
        "SELECT to_char(now() AT TIME ZONE %s, 'YYYY-MM-DD') AS d", (TZ,))["d"]
    start = request.args.get("start", "18:00")
    minutes = request.args.get("dur", 90, type=int)   # non-numbers fall back to 90
    if minutes not in DURATIONS:
        minutes = 90
    spaces, window = [], None
    start_ms = end_ms = None
    try:
        window = local_window(day, start, minutes)
        start_ms, end_ms = local_ms(window[0]), local_ms(window[1])
    except (ValueError, OverflowError):
        window = None
        flash("Giờ bắt đầu không hợp lệ.", "err")
    if fac_id and window:
        spaces = db.rows(
            """SELECT s.space_identifier::text AS id, s.space_code AS code,
                      ce.connector_type_code AS conn, ce.max_power_kw::float AS kw,
                      fn_is_space_available(s.space_identifier, w.s, w.e) AS free,
                      t.time_band_code AS band, t.price_per_kwh_value::float AS price,
                      t.overtime_fee_per_hour_value::float AS ot
               FROM parking_space AS s
               CROSS JOIN (SELECT (%s::timestamp AT TIME ZONE %s) AS s,
                                  (%s::timestamp AT TIME ZONE %s) AS e) AS w
               LEFT JOIN charging_equipment AS ce
                      ON ce.space_identifier = s.space_identifier AND ce.deleted_datetime IS NULL
               LEFT JOIN tariff_rate AS t
                      ON t.rate_identifier = fn_select_tariff(ce.equipment_identifier, w.s)
               WHERE s.facility_identifier = %s::uuid AND s.deleted_datetime IS NULL
               ORDER BY s.space_code""", (window[0], TZ, window[1], TZ, fac_id))
    reservations = db.rows(
        """SELECT r.reservation_identifier::text AS id, f.facility_name_text AS facility,
                  s.space_code AS code, v.license_plate_text AS plate,
                  to_char(r.start_datetime AT TIME ZONE %s, 'DD/MM HH24:MI') AS start_text,
                  to_char(r.end_datetime AT TIME ZONE %s, 'HH24:MI') AS end_text,
                  (extract(epoch FROM r.start_datetime) * 1000)::bigint AS start_ms,
                  r.reservation_status_code AS status
           FROM reservation AS r
           JOIN vehicle AS v ON v.vehicle_identifier = r.vehicle_identifier
           JOIN parking_space AS s ON s.space_identifier = r.space_identifier
           JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
           WHERE v.account_identifier = %s::uuid AND r.deleted_datetime IS NULL
           ORDER BY r.start_datetime DESC LIMIT 8""", (TZ, TZ, uid))
    invoices = db.rows(
        """SELECT p.transaction_identifier::text AS id,
                  to_char(ss.start_datetime AT TIME ZONE %s, 'DD/MM HH24:MI') AS day_text,
                  v.license_plate_text AS plate, t.time_band_code AS band,
                  ss.consumed_energy_kwh::float AS kwh,
                  p.energy_amount_value::float AS energy,
                  p.overtime_amount_value::float AS overtime,
                  p.transaction_amount_value::float AS total,
                  p.transaction_status_code AS status, p.payment_method_code AS method
           FROM payment_transaction AS p
           JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
           JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
           JOIN tariff_rate AS t ON t.rate_identifier = p.rate_identifier
           WHERE v.account_identifier = %s::uuid
           ORDER BY (p.transaction_status_code IN ('PENDING', 'FAILED')) DESC,
                    ss.start_datetime DESC LIMIT 20""", (TZ, uid))
    sessions = db.rows(
        """SELECT v.license_plate_text AS plate, s.space_code AS code,
                  f.facility_name_text AS facility, ce.max_power_kw::float AS kw,
                  v.battery_capacity_kwh::float AS cap, t.time_band_code AS band,
                  coalesce(ss.applied_price_per_kwh_value, t.price_per_kwh_value)::float AS price,
                  (extract(epoch FROM ss.start_datetime) * 1000)::bigint AS start_ms,
                  to_char(ss.start_datetime AT TIME ZONE %s, 'HH24:MI') AS since
           FROM service_session AS ss
           JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
           JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
           JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
           JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
           LEFT JOIN tariff_rate AS t
                  ON t.rate_identifier = fn_select_tariff(ce.equipment_identifier, ss.start_datetime)
           WHERE v.account_identifier = %s::uuid AND ss.end_datetime IS NULL
           ORDER BY ss.start_datetime""", (TZ, uid))
    return render_template("customer.html", vehicles=vehicles, facilities=facilities,
                           fac_id=fac_id, day=day, start=start, minutes=minutes,
                           start_ms=start_ms, end_ms=end_ms, sessions=sessions,
                           last_day=(datetime.now(LOCAL_OFFSET)
                                     + timedelta(days=MAX_ADVANCE_DAYS)).strftime("%Y-%m-%d"),
                           spaces=spaces, reservations=reservations, invoices=invoices,
                           durations=DURATIONS)


def booking_problem(uid, begin):
    """Why this customer may not book right now, or None."""
    latest = datetime.now(LOCAL_OFFSET) + timedelta(days=MAX_ADVANCE_DAYS)
    if datetime.strptime(begin, "%Y-%m-%d %H:%M").replace(tzinfo=LOCAL_OFFSET) > latest:
        return f"Chỉ đặt trước tối đa {MAX_ADVANCE_DAYS} ngày."
    found = db.row(
        """SELECT (SELECT count(*) FROM reservation AS r
                     JOIN vehicle AS v ON v.vehicle_identifier = r.vehicle_identifier
                    WHERE v.account_identifier = %s::uuid AND r.deleted_datetime IS NULL
                      AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                      AND r.end_datetime > now()) AS active,
                  (SELECT count(*) FROM payment_transaction AS p
                     JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
                     JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
                    WHERE v.account_identifier = %s::uuid
                      AND p.transaction_status_code IN ('PENDING', 'FAILED')) AS unpaid""",
        (uid, uid)) or {}
    if found.get("unpaid"):
        return "Bạn còn hóa đơn chưa thanh toán. Hãy thanh toán rồi đặt chỗ."
    if found.get("active", 0) >= MAX_ACTIVE_BOOKINGS:
        return f"Mỗi khách giữ tối đa {MAX_ACTIVE_BOOKINGS} lượt đặt cùng lúc."
    return None


@app.post("/customer/book")
@role_required("CUSTOMER")
def customer_book():
    f = request.form
    try:
        minutes = int(f["dur"])
        if minutes not in DURATIONS:
            raise ValueError("duration")
        begin, end = local_window(f["day"], f["start"], minutes)
        problem = booking_problem(session["uid"], begin)
        if problem:
            flash(problem, "err")
            return redirect(url_for("customer", fac=f.get("fac"), day=f.get("day"),
                                    start=f.get("start"), dur=f.get("dur")))
        count = db.run(
            """INSERT INTO reservation (vehicle_identifier, space_identifier,
                                        start_datetime, end_datetime)
               SELECT v.vehicle_identifier, %s::uuid,
                      %s::timestamp AT TIME ZONE %s, %s::timestamp AT TIME ZONE %s
               FROM vehicle AS v
               WHERE v.vehicle_identifier = %s::uuid AND v.account_identifier = %s::uuid
                 AND v.deleted_datetime IS NULL
                 AND (%s::timestamp AT TIME ZONE %s) > now()""",
            (f["space"], begin, TZ, end, TZ, f["vehicle"], session["uid"], begin, TZ))
        flash("Đã gửi đặt chỗ, chờ xác nhận." if count else
              "Không đặt được: kiểm tra xe và giờ bắt đầu (phải ở tương lai).",
              "ok" if count else "err")
    except (ValueError, KeyError, OverflowError):
        flash("Dữ liệu đặt chỗ không hợp lệ.", "err")
    except psycopg.Error as err:
        flash(db_message(err), "err")
    return redirect(url_for("customer", fac=f.get("fac"), day=f.get("day"),
                            start=f.get("start"), dur=f.get("dur")))


@app.post("/customer/cancel")
@role_required("CUSTOMER")
def customer_cancel():
    count = db.run(
        """UPDATE reservation SET reservation_status_code = 'CANCELLED'
           WHERE reservation_identifier = %s::uuid
             AND reservation_status_code IN ('PENDING', 'CONFIRMED')
             AND vehicle_identifier IN (SELECT vehicle_identifier FROM vehicle
                                        WHERE account_identifier = %s::uuid)""",
        (request.form["id"], session["uid"]))
    flash("Đã hủy đặt chỗ, khung giờ được trả lại." if count else "Không hủy được.",
          "ok" if count else "err")
    return redirect(url_for("customer"))


@app.post("/customer/pay")
@role_required("CUSTOMER")
def customer_pay():
    method = request.form.get("method")
    if method not in METHODS:
        abort(400)
    # Demo gateway: a real integration would confirm with the payment provider first.
    count = db.run(
        """UPDATE payment_transaction AS p
           SET payment_method_code = %s,
               gateway_reference_identifier = 'DEMO-' || upper(substr(md5(random()::text), 1, 10)),
               transaction_status_code = 'SUCCESS'
           WHERE p.transaction_identifier = %s::uuid AND p.transaction_status_code IN ('PENDING', 'FAILED')
             AND p.session_identifier IN (
                 SELECT ss.session_identifier FROM service_session AS ss
                 JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
                 WHERE v.account_identifier = %s::uuid)""",
        (method, request.form["id"], session["uid"]))
    flash("Thanh toán thành công (cổng thanh toán mô phỏng)." if count else
          "Không thanh toán được.", "ok" if count else "err")
    return redirect(url_for("customer"))


# ---------------------------------------------------------------- manager
def managed_facilities():
    return db.rows(
        """SELECT f.facility_identifier::text AS id, f.facility_name_text AS name
           FROM facility_manager AS fm
           JOIN parking_facility AS f ON f.facility_identifier = fm.facility_identifier
           WHERE fm.manager_identifier = %s::uuid ORDER BY f.facility_name_text""",
        (session["uid"],))


@app.route("/manager")
@role_required("MANAGER")
def manager():
    facilities = managed_facilities()
    ids = [f["id"] for f in facilities]
    fac_id = request.args.get("fac") if request.args.get("fac") in ids else (ids[0] if ids else None)
    spaces, alerts, pending, arrivals, counts = [], [], [], [], {}
    if fac_id:
        spaces = db.rows(
            """SELECT s.space_code AS code, s.availability_status_code AS status,
                      ce.equipment_identifier::text AS eq_id, ce.connector_type_code AS conn,
                      ce.max_power_kw::float AS kw, ce.equipment_status_code AS eq_status,
                      ce.evse_identifier AS evse, v.license_plate_text AS plate,
                      ss.consumed_energy_kwh::float AS kwh,
                      ss.session_identifier::text AS session_id,
                      (SELECT dv.license_plate_text
                         FROM reservation AS r
                         JOIN vehicle AS dv ON dv.vehicle_identifier = r.vehicle_identifier
                        WHERE r.space_identifier = s.space_identifier AND r.deleted_datetime IS NULL
                          AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                          AND now() >= r.start_datetime - INTERVAL '15 minutes'
                          AND now() <= r.start_datetime + INTERVAL '30 minutes'
                          AND now() < r.end_datetime
                        ORDER BY r.start_datetime LIMIT 1) AS due_plate,
                      to_char(ss.start_datetime AT TIME ZONE %s, 'HH24:MI') AS since,
                      (extract(epoch FROM ss.start_datetime) * 1000)::bigint AS since_ms,
                      (SELECT (extract(epoch FROM min(r.start_datetime)) * 1000)::bigint
                         FROM reservation AS r
                        WHERE r.space_identifier = s.space_identifier AND r.deleted_datetime IS NULL
                          AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                          AND r.start_datetime > now()) AS next_ms,
                      (SELECT to_char(min(r.start_datetime) AT TIME ZONE %s, 'HH24:MI')
                         FROM reservation AS r
                        WHERE r.space_identifier = s.space_identifier AND r.deleted_datetime IS NULL
                          AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                          AND r.start_datetime > now()) AS next_booking
               FROM parking_space AS s
               LEFT JOIN charging_equipment AS ce
                      ON ce.space_identifier = s.space_identifier AND ce.deleted_datetime IS NULL
               LEFT JOIN service_session AS ss
                      ON ss.equipment_identifier = ce.equipment_identifier AND ss.end_datetime IS NULL
               LEFT JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
               WHERE s.facility_identifier = %s::uuid AND s.deleted_datetime IS NULL
               ORDER BY s.space_code""", (TZ, TZ, fac_id))
        for sp in spaces:
            counts[sp["status"]] = counts.get(sp["status"], 0) + 1
        alerts = db.rows(
            """SELECT r.reservation_identifier::text AS id, s.space_code AS code,
                      v.license_plate_text AS plate,
                      (extract(epoch FROM r.start_datetime) * 1000)::bigint AS start_ms,
                      round(extract(epoch FROM (now() - r.start_datetime)) / 60)::int AS late_min
               FROM reservation AS r
               JOIN parking_space AS s ON s.space_identifier = r.space_identifier
               JOIN vehicle AS v ON v.vehicle_identifier = r.vehicle_identifier
               WHERE s.facility_identifier = %s::uuid AND r.deleted_datetime IS NULL
                 AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                 AND r.start_datetime + make_interval(mins => %s) < now()
               ORDER BY r.start_datetime""", (fac_id, GRACE_MIN))
        pending = db.rows(
            """SELECT r.reservation_identifier::text AS id, s.space_code AS code,
                      v.license_plate_text AS plate,
                      to_char(r.start_datetime AT TIME ZONE %s, 'DD/MM HH24:MI') AS start_text,
                      to_char(r.end_datetime AT TIME ZONE %s, 'HH24:MI') AS end_text
               FROM reservation AS r
               JOIN parking_space AS s ON s.space_identifier = r.space_identifier
               JOIN vehicle AS v ON v.vehicle_identifier = r.vehicle_identifier
               WHERE s.facility_identifier = %s::uuid AND r.deleted_datetime IS NULL
                 AND r.reservation_status_code = 'PENDING' AND r.end_datetime > now()
               ORDER BY r.start_datetime LIMIT 10""", (TZ, TZ, fac_id))
        arrivals = db.rows(
            """SELECT r.reservation_identifier::text AS id, s.space_code AS code,
                      v.license_plate_text AS plate,
                      to_char(r.start_datetime AT TIME ZONE %s, 'HH24:MI') AS start_text
               FROM reservation AS r
               JOIN parking_space AS s ON s.space_identifier = r.space_identifier
               JOIN vehicle AS v ON v.vehicle_identifier = r.vehicle_identifier
               WHERE s.facility_identifier = %s::uuid AND r.deleted_datetime IS NULL
                 AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                 AND now() >= r.start_datetime - INTERVAL '15 minutes'
                 AND now() <= r.start_datetime + INTERVAL '30 minutes'
                 AND now() < r.end_datetime
                 AND NOT EXISTS (SELECT 1 FROM charging_equipment AS ce
                                  WHERE ce.space_identifier = r.space_identifier
                                    AND ce.deleted_datetime IS NULL)
               ORDER BY r.start_datetime""", (TZ, fac_id))
    return render_template("manager.html", facilities=facilities, fac_id=fac_id,
                           spaces=spaces, alerts=alerts, pending=pending,
                           arrivals=arrivals, counts=counts)


MANAGED_SPACES = """space_identifier IN (
    SELECT s.space_identifier FROM parking_space AS s
    JOIN facility_manager AS fm ON fm.facility_identifier = s.facility_identifier
    WHERE fm.manager_identifier = %s::uuid)"""


@app.post("/manager/equipment")
@role_required("MANAGER")
def manager_equipment():
    status = request.form.get("status")
    if status not in ("READY", "FAULT", "MAINTENANCE"):
        abort(400)
    count = db.run(
        "UPDATE charging_equipment SET equipment_status_code = %s "
        "WHERE equipment_identifier = %s::uuid AND equipment_status_code <> 'CHARGING' AND "
        + MANAGED_SPACES, (status, request.form["id"], session["uid"]))
    flash("Đã cập nhật thiết bị; trạng thái ô đỗ tự đồng bộ." if count else
          "Không đổi được (thiết bị đang sạc hoặc ngoài phạm vi phụ trách).",
          "ok" if count else "err")
    return redirect(url_for("manager", fac=request.form.get("fac")))


@app.post("/manager/reservation")
@role_required("MANAGER")
def manager_reservation():
    action = request.form.get("action")
    if action == "confirm":
        sql = ("UPDATE reservation SET reservation_status_code = 'CONFIRMED' "
               "WHERE reservation_identifier = %s::uuid AND reservation_status_code = 'PENDING' "
               "AND end_datetime > now() AND start_datetime + INTERVAL '30 minutes' >= now() AND ")
    elif action == "arrive":   # parking-only space: no charging session to start
        sql = ("UPDATE reservation SET reservation_status_code = 'FULFILLED' "
               "WHERE reservation_identifier = %s::uuid "
               "AND reservation_status_code IN ('PENDING', 'CONFIRMED') "
               "AND now() >= start_datetime - INTERVAL '15 minutes' "
               "AND now() <= start_datetime + INTERVAL '30 minutes' AND now() < end_datetime "
               "AND NOT EXISTS (SELECT 1 FROM charging_equipment AS ce "
               "WHERE ce.space_identifier = reservation.space_identifier "
               "AND ce.deleted_datetime IS NULL) AND ")
    elif action == "expire":
        sql = ("UPDATE reservation SET reservation_status_code = 'EXPIRED' "
               "WHERE reservation_identifier = %s::uuid "
               "AND reservation_status_code IN ('PENDING', 'CONFIRMED') "
               "AND start_datetime + INTERVAL '30 minutes' < now() "
               "AND NOT EXISTS (SELECT 1 FROM service_session AS ss "
               "WHERE ss.reservation_identifier = reservation.reservation_identifier) AND ")
    else:
        abort(400)
    count = db.run(sql + MANAGED_SPACES, (request.form["id"], session["uid"]))
    if count and action == "expire":
        db.row("SELECT fn_refresh_reserved_spaces()")
    flash("Đã cập nhật đặt chỗ." if count else "Không cập nhật được.", "ok" if count else "err")
    return redirect(url_for("manager", fac=request.form.get("fac")))


@app.post("/manager/session/start")
@role_required("MANAGER")
def manager_session_start():
    """Plug a vehicle in. A reservation of this vehicle on this space is linked
    automatically; without one it is a walk-in. Triggers enforce the rules."""
    plate = request.form.get("plate", "").strip().upper()
    release_overdue()   # an overdue booking must not keep the space
    try:
        count = db.run(
            """INSERT INTO service_session (reservation_identifier, vehicle_identifier,
                                            equipment_identifier)
               SELECT (SELECT r.reservation_identifier FROM reservation AS r
                        WHERE r.vehicle_identifier = v.vehicle_identifier
                          AND r.space_identifier = ce.space_identifier
                          AND r.reservation_status_code IN ('PENDING', 'CONFIRMED')
                          AND r.deleted_datetime IS NULL
                          AND now() >= r.start_datetime - INTERVAL '15 minutes'
                          AND now() <= r.start_datetime + INTERVAL '30 minutes'
                          AND now() < r.end_datetime
                        ORDER BY r.start_datetime LIMIT 1),
                      v.vehicle_identifier, ce.equipment_identifier
               FROM vehicle AS v
               JOIN charging_equipment AS ce ON ce.equipment_identifier = %s::uuid
               WHERE upper(v.license_plate_text) = %s AND v.deleted_datetime IS NULL
                 AND ce.deleted_datetime IS NULL AND ce.""" + MANAGED_SPACES,
            (request.form.get("id"), plate, session["uid"]))
        flash("Đã bắt đầu phiên sạc." if count else
              "Không bắt đầu được: kiểm tra biển số và trụ phụ trách.",
              "ok" if count else "err")
    except psycopg.Error as err:
        flash(db_message(err), "err")
    return redirect(url_for("manager", fac=request.form.get("fac")))


@app.post("/manager/session/stop")
@role_required("MANAGER")
def manager_session_stop():
    """Unplug. The database trigger then issues the invoice."""
    try:
        kwh = float(request.form["kwh"].strip().replace(",", "."))
        idle = int(request.form.get("idle") or 0)   # minutes since fully charged
        if not (math.isfinite(kwh) and 0 <= kwh <= MAX_SESSION_KWH and 0 <= idle <= 1440):
            raise ValueError("range")
    except (ValueError, KeyError):
        flash(f"Số kWh phải từ 0 đến {MAX_SESSION_KWH}, số phút chờ từ 0 đến 1440.", "err")
        return redirect(url_for("manager", fac=request.form.get("fac")))
    try:
        count = db.run(
            """UPDATE service_session AS ss
               SET end_datetime = now(), consumed_energy_kwh = %s,
                   fully_charged_datetime = CASE WHEN %s::int > 0
                       THEN greatest(ss.start_datetime, now() - make_interval(mins => %s::int))
                   END
               WHERE ss.session_identifier = %s::uuid AND ss.end_datetime IS NULL
                 AND ss.equipment_identifier IN (
                     SELECT equipment_identifier FROM charging_equipment WHERE """
            + MANAGED_SPACES + ")",
            (kwh, idle, idle, request.form.get("id"), session["uid"]))
        flash("Đã kết thúc phiên và lập hóa đơn." if count else "Không kết thúc được phiên.",
              "ok" if count else "err")
    except psycopg.Error as err:
        flash(db_message(err), "err")
    return redirect(url_for("manager", fac=request.form.get("fac")))


# ---------------------------------------------------------------- admin
@app.route("/admin")
@role_required("ADMIN")
def admin():
    tab = request.args.get("tab", "overview")
    ctx = dict(tab=tab)
    if tab == "overview":
        ctx["revenue"] = db.rows(
            """SELECT f.facility_name_text AS facility, t.time_band_code AS band,
                      count(*) AS invoices, sum(p.transaction_amount_value)::float AS revenue
               FROM payment_transaction AS p
               JOIN tariff_rate AS t ON t.rate_identifier = p.rate_identifier
               JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
               JOIN charging_equipment AS ce ON ce.equipment_identifier = ss.equipment_identifier
               JOIN parking_space AS s ON s.space_identifier = ce.space_identifier
               JOIN parking_facility AS f ON f.facility_identifier = s.facility_identifier
               WHERE p.transaction_status_code = 'SUCCESS'
                 AND p.created_datetime >= now() - INTERVAL '30 days'
               GROUP BY f.facility_name_text, t.time_band_code
               ORDER BY f.facility_name_text, revenue DESC""")
        ctx["kpi"] = db.row(
            """SELECT
                 (SELECT coalesce(sum(transaction_amount_value), 0)::float FROM payment_transaction
                   WHERE transaction_status_code = 'SUCCESS'
                     AND created_datetime >= now() - INTERVAL '30 days') AS revenue,
                 (SELECT count(*) FROM service_session
                   WHERE start_datetime >= now() - INTERVAL '30 days') AS sessions,
                 (SELECT count(*) FROM payment_transaction
                   WHERE transaction_status_code = 'PENDING') AS pending_invoices,
                 (SELECT count(*) FROM reservation
                   WHERE reservation_status_code = 'EXPIRED'
                     AND created_datetime >= now() - INTERVAL '30 days') AS no_shows""")
    elif tab == "tariff":
        ctx["tariffs"] = db.rows(
            """SELECT rate_identifier::text AS id, connector_type_code AS conn,
                      time_band_code AS band, to_char(start_time, 'HH24:MI') AS from_text,
                      CASE WHEN end_time = TIME '24:00' THEN '24:00'
                           ELSE to_char(end_time, 'HH24:MI') END AS to_text,
                      min_power_kw::float AS min_kw, max_power_kw::float AS max_kw,
                      price_per_kwh_value::float AS price,
                      overtime_fee_per_hour_value::float AS overtime
               FROM tariff_rate ORDER BY connector_type_code, min_power_kw, start_time""")
    elif tab == "facilities":
        ctx["facilities"] = db.rows(
            """SELECT f.facility_identifier::text AS id, f.facility_name_text AS name,
                      f.total_capacity_count AS capacity,
                      (SELECT count(*) FROM parking_space AS s
                        WHERE s.facility_identifier = f.facility_identifier
                          AND s.deleted_datetime IS NULL) AS spaces,
                      coalesce((SELECT json_agg(json_build_object('id', u.account_identifier::text,
                                                                  'name', u.full_name_text)
                                                ORDER BY u.full_name_text)
                                FROM facility_manager AS fm
                                JOIN user_account AS u ON u.account_identifier = fm.manager_identifier
                               WHERE fm.facility_identifier = f.facility_identifier), '[]'::json) AS managers
               FROM parking_facility AS f ORDER BY f.facility_name_text""")
        ctx["managers"] = db.rows(
            """SELECT account_identifier::text AS id, full_name_text AS name FROM user_account
               WHERE role_code = 'MANAGER' AND deleted_datetime IS NULL ORDER BY full_name_text""")
    elif tab == "accounts":
        ctx["accounts"] = db.rows(
            """SELECT full_name_text AS name, email_address AS email, role_code AS role,
                      to_char(created_datetime AT TIME ZONE %s, 'DD/MM/YYYY') AS created
               FROM user_account WHERE role_code <> 'CUSTOMER' AND deleted_datetime IS NULL
               ORDER BY role_code, full_name_text""", (TZ,))
    else:
        ctx["tab"] = "invoices"
        ctx["invoices"] = db.rows(
            """SELECT p.transaction_identifier::text AS id,
                      to_char(p.created_datetime AT TIME ZONE %s, 'DD/MM HH24:MI') AS day_text,
                      u.full_name_text AS customer, v.license_plate_text AS plate,
                      t.time_band_code AS band,
                      p.energy_amount_value::float AS energy,
                      p.overtime_amount_value::float AS overtime,
                      p.transaction_amount_value::float AS total,
                      p.transaction_status_code AS status
               FROM payment_transaction AS p
               JOIN service_session AS ss ON ss.session_identifier = p.session_identifier
               JOIN vehicle AS v ON v.vehicle_identifier = ss.vehicle_identifier
               JOIN user_account AS u ON u.account_identifier = v.account_identifier
               JOIN tariff_rate AS t ON t.rate_identifier = p.rate_identifier
               ORDER BY p.created_datetime DESC LIMIT 25""", (TZ,))
    return render_template("admin.html", **ctx)


@app.post("/admin/tariff")
@role_required("ADMIN")
def admin_tariff():
    try:
        price, overtime = float(request.form["price"]), float(request.form["overtime"])
        if not all(math.isfinite(x) and 0 <= x <= MAX_PRICE for x in (price, overtime)):
            raise ValueError("range")
        count = db.run(
            """UPDATE tariff_rate SET price_per_kwh_value = %s, overtime_fee_per_hour_value = %s
               WHERE rate_identifier = %s::uuid""", (price, overtime, request.form["id"]))
        flash("Đã lưu biểu giá. Phiên đang sạc và hóa đơn cũ giữ giá đã chốt." if count else
              "Không tìm thấy dòng giá.", "ok" if count else "err")
    except (ValueError, KeyError):
        flash(f"Giá phải là số từ 0 đến {MAX_PRICE:,}.".replace(",", "."), "err")
    except psycopg.Error as err:
        flash(db_message(err), "err")
    return redirect(url_for("admin", tab="tariff"))


@app.post("/admin/assign")
@role_required("ADMIN")
def admin_assign():
    try:
        if request.form.get("action") == "remove":
            count = db.run("DELETE FROM facility_manager WHERE facility_identifier = %s::uuid "
                           "AND manager_identifier = %s::uuid",
                           (request.form["facility"], request.form["manager"]))
            flash("Đã thu hồi phân công." if count else "Không có phân công nào để thu hồi.",
                  "ok" if count else "err")
        else:
            db.run("INSERT INTO facility_manager (manager_identifier, facility_identifier) "
                   "VALUES (%s::uuid, %s::uuid) ON CONFLICT DO NOTHING",
                   (request.form["manager"], request.form["facility"]))
            flash("Đã phân công quản lý.", "ok")
    except (KeyError, psycopg.Error) as err:
        flash(db_message(err) if isinstance(err, psycopg.Error) else "Thiếu dữ liệu.", "err")
    return redirect(url_for("admin", tab="facilities"))


@app.post("/admin/accounts")
@role_required("ADMIN")
def admin_accounts():
    f = request.form
    if f.get("role") not in ("MANAGER", "ADMIN"):
        abort(400)
    name, email = f.get("name", "").strip(), f.get("email", "").strip()
    phone = f.get("phone", "").strip()
    problem = None
    if not 1 <= len(name) <= 100:
        problem = "Họ tên phải từ 1 đến 100 ký tự."
    elif len(email) > 255 or not EMAIL_RE.match(email):
        problem = "Email không hợp lệ."
    elif not PHONE_RE.match(phone):
        problem = "Số điện thoại gồm 8 đến 14 chữ số, có thể bắt đầu bằng +."
    if problem:
        flash(problem, "err")
        return redirect(url_for("admin", tab="accounts"))
    password = f.get("password", "")
    if len(password) < MIN_PASSWORD:
        flash(f"Mật khẩu phải có ít nhất {MIN_PASSWORD} ký tự.", "err")
        return redirect(url_for("admin", tab="accounts"))
    if password != f.get("password2", ""):
        flash("Hai mật khẩu không khớp.", "err")
        return redirect(url_for("admin", tab="accounts"))
    try:
        db.run(
            """INSERT INTO user_account (full_name_text, contact_phone_number, email_address,
                                         password_hash_text, role_code)
               VALUES (%s, %s, %s, %s, %s)""",
            (name, phone, email, generate_password_hash(password), f["role"]))
        flash(f"Đã tạo tài khoản {f['role']} {f['email'].strip()} với mật khẩu do bạn nhập.", "ok")
    except (KeyError, psycopg.Error) as err:
        flash("Không tạo được: " + (db_message(err) if isinstance(err, psycopg.Error)
                                    else "thiếu dữ liệu."), "err")
    return redirect(url_for("admin", tab="accounts"))


if __name__ == "__main__":
    app.run(debug=False)
