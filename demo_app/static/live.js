/* Server-synced clock and live time widgets for the EV Charge demo.
 *
 * The browser only displays and guides. Whether a booking is valid is always
 * decided by the database (now(), EXCLUDE constraint, triggers).
 *
 * Markup contract:
 *   #clock[data-api][data-tz]            on-screen clock + current tariff band
 *   [data-live="elapsed"  data-ms]       time since an instant (HH:MM:SS)
 *   [data-live="until"    data-ms]       time until an instant
 *   [data-live="late"     data-ms]       whole minutes since an instant
 *   [data-live="reservation" data-ms data-grace]   countdown to pickup + grace
 *   [data-refresh="url"]                 replaced by the HTML at url every 15 s
 *   [data-live="session" data-ms data-kw data-price data-cap data-pct]  running estimate,
 *        with children [data-out="energy"] and [data-out="cost"]
 *   #search-form[data-start-ms data-end-ms data-minutes]  booking window guards
 */
(function () {
  "use strict";

  var clockEl = document.getElementById("clock");
  var TZ = (clockEl && clockEl.dataset.tz) || "Asia/Ho_Chi_Minh";
  var API = clockEl && clockEl.dataset.api;
  var offset = 0;      // server time minus browser time, in ms
  var info = null;     // last band information from the API

  var fmtTime = new Intl.DateTimeFormat("vi-VN", {timeZone: TZ, hour12: false,
    hour: "2-digit", minute: "2-digit", second: "2-digit"});
  var fmtHM = new Intl.DateTimeFormat("vi-VN", {timeZone: TZ, hour12: false,
    hour: "2-digit", minute: "2-digit"});
  var fmtDate = new Intl.DateTimeFormat("vi-VN", {timeZone: TZ,
    weekday: "short", day: "2-digit", month: "2-digit", year: "numeric"});
  var fmtISO = new Intl.DateTimeFormat("en-CA", {timeZone: TZ,
    year: "numeric", month: "2-digit", day: "2-digit"});

  function now() { return Date.now() + offset; }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function vnd(x) { return Math.round(x).toLocaleString("vi-VN") + "đ"; }

  /* "1g 05p" for long spans, "mm:ss" for short ones. */
  function dur(ms) {
    var s = Math.max(0, Math.floor(ms / 1000));
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    if (h >= 24) { return Math.floor(h / 24) + " ngày " + (h % 24) + "g"; }
    if (h > 0) { return h + "g " + pad(m) + "p"; }
    return pad(m) + ":" + pad(s % 60);
  }
  function hms(ms) {
    var s = Math.max(0, Math.floor(ms / 1000));
    return pad(Math.floor(s / 3600)) + ":" + pad(Math.floor((s % 3600) / 60)) + ":" + pad(s % 60);
  }
  function setClass(el, name) {
    el.classList.remove("live-warn", "live-bad");
    if (name) { el.classList.add(name); }
  }

  window.ServerClock = {now: now, tz: TZ, vnd: vnd};

  /* ---------------------------------------------------------- clock + band */
  function renderClock() {
    if (!clockEl) { return; }
    var d = new Date(now());
    document.getElementById("clock-time").textContent = fmtTime.format(d);
    document.getElementById("clock-date").textContent = fmtDate.format(d);
    var bandEl = document.getElementById("clock-band");
    var nextEl = document.getElementById("clock-next");
    if (!info || !info.band) { bandEl.hidden = true; nextEl.hidden = true; return; }
    bandEl.hidden = false;
    bandEl.className = "pill " + info.band;
    bandEl.textContent = info.band_name;
    if (info.change_epoch_ms) {
      var left = info.change_epoch_ms - now();
      nextEl.hidden = false;
      if (left > 0) {
        nextEl.textContent = "còn " + dur(left) + " nữa sang " + info.next_band_name.toLowerCase();
      } else {
        nextEl.textContent = "đang đổi khung giá…";
        sync();
      }
    } else {
      nextEl.hidden = true;
    }
  }

  var syncing = false;
  function sync() {
    if (!API || syncing) { return; }
    syncing = true;
    var t0 = Date.now();
    fetch(API, {cache: "no-store"})
      .then(function (r) { if (!r.ok) { throw new Error(r.status); } return r.json(); })
      .then(function (d) {
        var t1 = Date.now();
        offset = d.epoch_ms + (t1 - t0) / 2 - t1;   // compensate half the round trip
        info = d;
        renderClock();
      })
      .catch(function () { /* keep last offset: falls back to the local clock */ })
      .then(function () { syncing = false; });
  }

  /* ----------------------------------------------------------- live fields */
  function tickLive() {
    var t = now();
    var nodes = document.querySelectorAll("[data-live]");
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i], kind = el.dataset.live, ms = +el.dataset.ms;
      if (kind === "elapsed") {
        el.textContent = hms(t - ms);
      } else if (kind === "until") {
        el.textContent = ms > t ? "sau " + dur(ms - t) : "đã đến giờ";
      } else if (kind === "late") {
        el.textContent = Math.max(0, Math.round((t - ms) / 60000));
      } else if (kind === "reservation") {
        var grace = +el.dataset.grace;
        if (t < ms) {
          el.textContent = "còn " + dur(ms - t) + " tới giờ nhận chỗ";
          setClass(el, null);
        } else if (t < ms + grace) {
          el.textContent = "hạn nhận chỗ còn " + dur(ms + grace - t);
          setClass(el, "live-warn");
        } else {
          el.textContent = "quá hạn nhận chỗ";
          setClass(el, "live-bad");
        }
      } else if (kind === "session") {
        var hours = Math.max(0, (t - ms) / 3600000);
        var kwh = (+el.dataset.kw) * 0.9 * hours, cap = +el.dataset.cap;
        var pct = el.dataset.pct === undefined ? 20 : +el.dataset.pct;
        if (cap > 0) { kwh = Math.min(kwh, cap * (100 - pct) / 100); }
        var e = el.querySelector('[data-out="energy"]'), c = el.querySelector('[data-out="cost"]');
        if (e) { e.textContent = kwh.toFixed(1) + " kWh"; }
        if (c) { c.textContent = vnd(kwh * (+el.dataset.price)); }
      }
    }
  }

  /* ------------------------------------------------- booking form guards */
  var form = document.getElementById("search-form");
  var dayEl = document.getElementById("day"), startEl = document.getElementById("start");

  function localParts(ms) {
    var hm = fmtHM.format(new Date(ms)).split(":");
    return {iso: fmtISO.format(new Date(ms)), mins: (+hm[0]) * 60 + (+hm[1])};
  }
  function ceil15(mins) { return Math.ceil(mins / 15) * 15; }
  function hhmm(mins) { return pad(Math.floor(mins / 60)) + ":" + pad(mins % 60); }

  function guardInputs(first) {
    if (!form || !dayEl || !startEl) { return; }
    var p = localParts(now());
    dayEl.min = p.iso;
    if (first && dayEl.value && dayEl.value < p.iso) { dayEl.value = p.iso; }
    if (dayEl.value === p.iso) {
      var min = ceil15(p.mins + 1);          // strictly in the future
      if (min >= 1440) {
        startEl.removeAttribute("min");
      } else {
        startEl.min = hhmm(min);
        if (first && startEl.value && startEl.value < startEl.min) { startEl.value = startEl.min; }
      }
    } else {
      startEl.removeAttribute("min");
    }
  }

  function guardBookButtons() {
    if (!form) { return; }
    var startMs = +form.dataset.startMs;
    var past = !isFinite(startMs) || startMs <= now();
    var btns = document.querySelectorAll(".js-book");
    for (var i = 0; i < btns.length; i++) {
      btns[i].disabled = past;
      btns[i].title = past ? "Giờ bắt đầu đã qua, hãy chọn giờ trong tương lai" : "";
    }
  }

  function renderPreviews() {
    if (!form) { return; }
    var startMs = +form.dataset.startMs, endMs = +form.dataset.endMs;
    var minutes = +form.dataset.minutes;
    var nodes = document.querySelectorAll(".js-preview");
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i], card = el.closest(".sp");
      var sel = card && card.querySelector("select[name=vehicle]");
      var opt = sel && sel.options[sel.selectedIndex];
      var cap = opt ? +opt.dataset.kwh : 0;
      var kw = +el.dataset.kw, price = +el.dataset.price;
      var text = "Kết thúc " + fmtHM.format(new Date(endMs)) + " · " + minutes + " phút";
      if (kw > 0 && isFinite(price)) {
        var kwh = kw * minutes / 60;
        if (cap > 0) { kwh = Math.min(kwh, cap); }
        text += " · ước tính ≤ " + kwh.toFixed(1) + " kWh ≈ " + vnd(kwh * price);
      }
      el.textContent = text;
    }
  }

  /* ----------------------------------------------------------------- boot */
  function boot() {
    guardInputs(true);
    renderPreviews();
    var selects = document.querySelectorAll(".sp select[name=vehicle]");
    for (var i = 0; i < selects.length; i++) {
      selects[i].addEventListener("change", renderPreviews);
    }
    if (dayEl) { dayEl.addEventListener("change", function () { guardInputs(false); }); }
    function everySecond() {
      renderClock();
      tickLive();
      guardBookButtons();
    }
    everySecond();
    sync();
    setInterval(everySecond, 1000);
    setInterval(function () { guardInputs(false); }, 30000);
    setInterval(sync, 60000);
    setInterval(refreshParts, 15000);
  }

  /* ----------------------------------------- parts reloaded from the server */
  function refreshParts() {
    var parts = document.querySelectorAll("[data-refresh]");
    Array.prototype.forEach.call(parts, function (el) {
      fetch(el.dataset.refresh, {credentials: "same-origin", redirect: "manual"})
        .then(function (r) {
          // a redirect means the login expired: keep the last rows
          if (!r.ok || r.type === "opaqueredirect") { throw new Error("skip"); }
          return r.text();
        })
        .then(function (html) { el.innerHTML = html; tickLive(); })
        .catch(function () { /* keep the last rows */ });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
