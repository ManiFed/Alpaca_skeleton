/* ============================================================
   Boundless Skies — marketing site
   Pulls live data from the cloud API; falls back gracefully when
   the API is unreachable so the page is never broken.
   ============================================================ */
(function () {
  "use strict";

  var API = "http://" + (location.hostname || "localhost") + ":8800";

  function getJSON(path) {
    return fetch(API + path, { mode: "cors" })
      .then(function (r) { return r.ok ? r.json() : null; })
      .catch(function () { return null; });
  }
  var $ = function (id) { return document.getElementById(id); };
  function hhmmss(iso) {
    try { return new Date(iso).toISOString().slice(11, 19); } catch (e) { return "--:--:--"; }
  }

  /* =========================================================
     1. PLATE-SOLVING STARFIELD  (distinctive hero animation)
     A slowly drifting star field; targeting reticles acquire
     real catalogue targets one by one — mirroring what the
     pipeline actually does (plate-solve → identify → measure).
     ========================================================= */
  function skyfield(initialTargets) {
    var c = $("skyfield");
    if (!c) return { setTargets: function () {} };
    var targets = initialTargets;
    var ctx = c.getContext("2d");
    var W, H, DPR = Math.min(devicePixelRatio || 1, 2);
    var stars = [], links = [];

    function resize() {
      var r = c.getBoundingClientRect();
      W = c.width = r.width * DPR; H = c.height = r.height * DPR;
      var n = Math.min(260, Math.floor((r.width * r.height) / 5200));
      stars = [];
      for (var i = 0; i < n; i++) {
        stars.push({
          x: Math.random() * W, y: Math.random() * H,
          r: (Math.random() * 1.3 + 0.3) * DPR,
          a: 0.25 + Math.random() * 0.6,
          tw: 0.4 + Math.random() * 1.6, ph: Math.random() * 6.28,
          col: Math.random() < 0.12 ? "150,175,255" : (Math.random() < 0.12 ? "232,200,150" : "255,255,255")
        });
      }
      // faint constellation: link a handful of brighter stars
      links = [];
      var bright = stars.filter(function (s) { return s.a > 0.7; }).slice(0, 9);
      for (var k = 0; k < bright.length - 1; k++) {
        if (Math.random() < 0.6) links.push([bright[k], bright[k + 1]]);
      }
    }

    // reticle acquisition targets — anchored to bright stars, labelled with real data
    var anchors = [];
    function placeAnchors() {
      anchors = [];
      var pool = stars.slice().sort(function (a, b) { return b.a - a.a; }).slice(0, 18);
      for (var i = 0; i < targets.length && i < 6; i++) {
        var s = pool[(i * 3) % pool.length];
        anchors.push({ x: s.x, y: s.y, name: targets[i].name, mag: targets[i].mag });
      }
    }

    var idx = 0, phase = "scan", t0 = 0;
    var DUR = { scan: 700, acquire: 800, lock: 2400, release: 500 };

    function reticle(x, y, p, locked, label) {
      var R = (locked ? 17 : (46 - 29 * p)) * DPR;   // ring contracts while acquiring
      var col = locked ? "232,169,58" : "150,175,255";
      ctx.strokeStyle = "rgba(" + col + "," + (locked ? 0.9 : 0.5 + 0.4 * p) + ")";
      ctx.lineWidth = 1 * DPR;
      // ring
      ctx.beginPath(); ctx.arc(x, y, R * 0.72, 0, 6.2832); ctx.stroke();
      // corner brackets
      var b = R, g = R * 0.55;
      [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (d) {
        ctx.beginPath();
        ctx.moveTo(x + d[0] * b, y + d[1] * g);
        ctx.lineTo(x + d[0] * b, y + d[1] * b);
        ctx.lineTo(x + d[0] * g, y + d[1] * b);
        ctx.stroke();
      });
      // crosshair with central gap
      ctx.beginPath();
      ctx.moveTo(x - R, y); ctx.lineTo(x - R * 0.35, y);
      ctx.moveTo(x + R * 0.35, y); ctx.lineTo(x + R, y);
      ctx.moveTo(x, y - R); ctx.lineTo(x, y - R * 0.35);
      ctx.moveTo(x, y + R * 0.35); ctx.lineTo(x, y + R);
      ctx.stroke();
      // label (typed in while locked)
      if (locked && label) {
        var full = label.name + "  " + label.mag.toFixed(1) + " mag";
        var chars = Math.min(full.length, Math.floor(full.length * Math.min(1, p * 1.6)));
        ctx.fillStyle = "rgba(232,169,58,0.92)";
        ctx.font = (11 * DPR) + "px JetBrains Mono, monospace";
        ctx.textBaseline = "top";
        ctx.fillText(full.slice(0, chars), x + R + 6 * DPR, y - R);
      }
    }

    var last = performance.now();
    function frame(now) {
      var dt = now - last; last = now;
      ctx.clearRect(0, 0, W, H);

      // drift (sidereal-ish) + wrap
      var dx = 0.004 * DPR * dt, dy = 0.0016 * DPR * dt;
      // constellation links
      ctx.strokeStyle = "rgba(150,175,255,0.10)"; ctx.lineWidth = 0.6 * DPR;
      links.forEach(function (l) {
        ctx.beginPath(); ctx.moveTo(l[0].x, l[0].y); ctx.lineTo(l[1].x, l[1].y); ctx.stroke();
      });
      // stars
      for (var i = 0; i < stars.length; i++) {
        var s = stars[i];
        s.x += dx; s.y += dy;
        if (s.x > W) s.x -= W; if (s.y > H) s.y -= H;
        s.ph += dt * 0.001 * s.tw;
        var a = s.a * (0.7 + 0.3 * Math.sin(s.ph));
        ctx.beginPath(); ctx.arc(s.x, s.y, s.r, 0, 6.2832);
        ctx.fillStyle = "rgba(" + s.col + "," + a + ")"; ctx.fill();
      }
      // reticle state machine
      if (anchors.length) {
        t0 += dt;
        var a0 = anchors[idx % anchors.length];
        if (phase === "scan" && t0 > DUR.scan) { phase = "acquire"; t0 = 0; }
        else if (phase === "acquire" && t0 > DUR.acquire) { phase = "lock"; t0 = 0; }
        else if (phase === "lock" && t0 > DUR.lock) { phase = "release"; t0 = 0; }
        else if (phase === "release" && t0 > DUR.release) { phase = "scan"; t0 = 0; idx++; }

        if (phase === "acquire") reticle(a0.x, a0.y, t0 / DUR.acquire, false, a0);
        else if (phase === "lock") reticle(a0.x, a0.y, t0 / DUR.lock, true, a0);
        else if (phase === "release") reticle(a0.x, a0.y, 1, true, a0);
      }
      requestAnimationFrame(frame);
    }

    resize();
    placeAnchors();
    window.addEventListener("resize", function () { resize(); placeAnchors(); });
    requestAnimationFrame(frame);

    return {
      setTargets: function (t) { if (t && t.length) { targets = t; idx = 0; placeAnchors(); } }
    };
  }

  /* =========================================================
     2. LIGHT CURVES
     ========================================================= */
  function drawCurve(canvas, pts, progress, opts) {
    opts = opts || {};
    var ctx = canvas.getContext("2d"), W = canvas.width, H = canvas.height;
    var pad = H * 0.14;
    var mags = pts.map(function (p) { return p.m; });
    var lo = Math.min.apply(null, mags), hi = Math.max.apply(null, mags);
    if (hi - lo < 0.5) { hi += 0.5; lo -= 0.5; }
    // astronomical convention: brighter (smaller mag) sits higher
    var xy = function (i) {
      var x = (i / (pts.length - 1)) * W;
      var y = pad + ((pts[i].m - lo) / (hi - lo)) * (H - pad * 2);
      return [x, y];
    };
    ctx.clearRect(0, 0, W, H);
    if (opts.grid) {
      ctx.strokeStyle = "rgba(255,255,255,0.04)"; ctx.lineWidth = 1;
      for (var g = pad; g < H; g += (H - pad) / 4) { ctx.beginPath(); ctx.moveTo(0, g); ctx.lineTo(W, g); ctx.stroke(); }
    }
    var lim = Math.floor(progress * pts.length);
    ctx.beginPath(); ctx.strokeStyle = "rgba(79,139,255,0.45)"; ctx.lineWidth = opts.thin ? 1.1 : 1.6;
    for (var i = 0; i < lim; i++) { var p = xy(i); i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1]); }
    ctx.stroke();
    for (var j = 0; j < lim; j++) {
      var q = xy(j);
      ctx.beginPath(); ctx.arc(q[0], q[1], opts.thin ? 1.7 : 2.6, 0, 6.2832);
      ctx.fillStyle = pts[j].ok ? "#E8A93A" : "rgba(240,101,95,0.6)"; ctx.fill();
    }
    if (lim > 0) {
      var e = xy(lim - 1);
      ctx.beginPath(); ctx.arc(e[0], e[1], opts.thin ? 3 : 5, 0, 6.2832); ctx.fillStyle = "rgba(79,139,255,0.3)"; ctx.fill();
      ctx.beginPath(); ctx.arc(e[0], e[1], opts.thin ? 2 : 3, 0, 6.2832); ctx.fillStyle = "#4F8BFF"; ctx.fill();
    }
  }

  function animateCurve(canvas, pts, opts, dur) {
    if (!canvas || !pts || !pts.length) return;
    var start = null;
    function step(ts) {
      if (!start) start = ts;
      var p = Math.min((ts - start) / dur, 1);
      drawCurve(canvas, pts, p, opts);
      if (p < 1) requestAnimationFrame(step);
    }
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { requestAnimationFrame(step); io.disconnect(); } });
    }, { threshold: 0.25 });
    io.observe(canvas);
  }

  /* =========================================================
     3. RELIABILITY GAUGE
     ========================================================= */
  function drawGauge(value) {
    var c = $("gauge"); if (!c) return;
    var ctx = c.getContext("2d"), W = c.width, H = c.height, cx = W / 2, cy = H - 8, rad = 70;
    ctx.clearRect(0, 0, W, H); ctx.lineWidth = 9; ctx.lineCap = "round";
    ctx.beginPath(); ctx.arc(cx, cy, rad, Math.PI, 2 * Math.PI); ctx.strokeStyle = "rgba(255,255,255,0.08)"; ctx.stroke();
    var col = value >= 0.85 ? "#54D98C" : value >= 0.65 ? "#4F8BFF" : "#E8A93A";
    ctx.beginPath(); ctx.arc(cx, cy, rad, Math.PI, Math.PI + value * Math.PI); ctx.strokeStyle = col; ctx.stroke();
  }

  /* =========================================================
     4. NODE BUILDER (Mac-mini-style configurator)
     ========================================================= */
  function builder() {
    var FLOOR = 0.50;
    var relVal = $("rel-val"), relFill = $("rel-fill"), multVal = $("mult-val"),
        tierName = $("tier-name"), unlocks = $("unlocks");
    if (!relVal) return;
    var TIERS = {
      "1": { name: "ZWO Seestar S50 · Tier 1", rel: 0.0, chips: ["variable stars", "novae"] },
      "2": { name: "Filtered BVRI rig · Tier 2", rel: 0.05, chips: ["variable stars", "novae", "multi-band BVRI", "supernovae"] },
      "3": { name: "Spectroscopy rig · Tier 3", rel: 0.08, chips: ["variable stars", "novae", "BVRI", "supernovae", "transient classification"] }
    };
    function recompute() {
      var tier = document.querySelector('input[name="tier"]:checked').value;
      var rel = FLOOR + TIERS[tier].rel;
      $("g-filter").style.opacity = (tier !== "1") ? "1" : "0";
      document.querySelectorAll('input[name="auto"]').forEach(function (cb) {
        var g = $(cb.dataset.target); if (g) g.style.opacity = cb.checked ? "1" : "0";
        if (cb.checked) rel += parseFloat(cb.dataset.rel);
      });
      rel = Math.min(1, rel);
      var mult = 0.5 + 0.5 * rel;
      relVal.textContent = rel.toFixed(2);
      relFill.style.width = (rel * 100).toFixed(0) + "%";
      relFill.style.background = rel >= 0.85 ? "#54D98C" : rel >= 0.65 ? "#4F8BFF" : "#E8A93A";
      multVal.textContent = "×" + mult.toFixed(2);
      tierName.textContent = TIERS[tier].name;
      relVal.style.color = rel >= 0.85 ? "#54D98C" : rel >= 0.65 ? "#4F8BFF" : "#E8A93A";
      unlocks.innerHTML = TIERS[tier].chips.map(function (c) { return '<span class="chip">' + c + "</span>"; }).join("");
    }
    document.querySelectorAll('input[name="tier"], input[name="auto"]').forEach(function (el) {
      el.addEventListener("change", recompute);
    });
    recompute();
  }

  /* =========================================================
     5. SCROLL REVEAL + COUNT-UP + MOBILE NAV
     ========================================================= */
  function reveals() {
    var els = document.querySelectorAll(".reveal");
    if (!("IntersectionObserver" in window)) {
      els.forEach(function (el) { el.classList.add("in"); });
      return;
    }
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { threshold: 0.15 });
    els.forEach(function (el) { io.observe(el); });
  }
  function countUp(el, target, dur, suffix) {
    if (!el) return;
    suffix = suffix || "";
    var final = Math.round(target).toLocaleString() + suffix, start = null;
    function step(ts) {
      if (!start) start = ts;
      var p = Math.min((ts - start) / dur, 1), e = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.floor(target * e).toLocaleString() + suffix;
      if (p < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
    // guarantee the final value even when rAF is throttled (background/preview)
    setTimeout(function () { el.textContent = final; }, dur + 150);
  }
  function mobileNav() {
    var btn = document.querySelector(".nav-toggle"), links = document.querySelector(".nav-links");
    if (!btn || !links) return;
    btn.addEventListener("click", function () {
      var open = links.style.display === "flex";
      if (open) { links.style.display = ""; return; }
      links.style.cssText = "display:flex;position:absolute;flex-direction:column;top:64px;right:28px;background:var(--bg-elev);padding:16px 20px;border-radius:12px;border:0.5px solid var(--line);gap:14px";
    });
  }

  /* =========================================================
     6. LIVE DATA WIRING
     ========================================================= */
  var DEFAULT_TARGETS = [
    { name: "SS Cyg", mag: 8.4 }, { name: "T CrB", mag: 9.9 },
    { name: "R Leo", mag: 6.8 }, { name: "Z UMa", mag: 7.9 }, { name: "SS Aur", mag: 12.0 }
  ];

  function fillConsole(points) {
    var grid = $("obs-grid"); if (!grid || !points.length) return;
    var recent = points.slice(-4).reverse();
    recent.forEach(function (p, i) {
      var row = document.createElement("div"); row.className = "obs-row";
      var status = p.aavso_submitted ? '<span class="c-ok">accepted</span>'
        : (i === 0 ? '<span class="c-busy">observing…</span>' : '<span class="c-busy">queued</span>');
      row.innerHTML =
        '<span class="c-node">' + p.node_id + '</span>' +
        '<span class="c-tgt">SS Cyg</span>' +
        '<span class="c-time">' + hhmmss(p.received_at) + '</span>' +
        '<span class="c-mag">' + p.magnitude.toFixed(2) + '</span>' + status;
      grid.appendChild(row);
    });
  }

  function placeMap(nodes) {
    var box = $("mapbox"); if (!box) return;
    nodes.forEach(function (n, i) {
      if (typeof n.longitude !== "number") return;
      var x = (n.longitude + 180) / 360 * 100;
      var y = (90 - n.latitude) / 180 * 100;
      var d = document.createElement("div");
      d.className = "ndot"; d.style.left = x + "%"; d.style.top = y + "%";
      d.style.animationDelay = (i * 0.12) + "s";
      if (!n.online) { d.style.background = "#5a5e6b"; d.style.opacity = "0.7"; }
      d.title = (n.city || "node") + (n.country ? ", " + n.country : "");
      box.appendChild(d);
    });
  }

  function boot() {
    builder(); reveals(); mobileNav();

    // start the hero animation immediately; re-seed with real targets once loaded
    var sky = skyfield(DEFAULT_TARGETS);

    // ---- network status ----
    getJSON("/api/v1/network/status").then(function (s) {
      if (!s) {
        // offline fallback: keep page sensible
        $("badge-text").textContent = "nodes observing right now";
        $("stat-subs").textContent = "—"; $("stat-nodes").textContent = "—";
        $("stat-accept").textContent = "—"; $("stat-countries").textContent = "—";
        $("gauge-num").textContent = "—";
        return;
      }
      var accept = s.measurements_total ? Math.round(s.aavso_submitted / s.measurements_total * 100) : 0;
      var countries = {}; (s.nodes || []).forEach(function (n) { if (n.country) countries[n.country] = 1; });
      var nCountries = Object.keys(countries).length;

      $("badge-text").textContent = s.nodes_online + " nodes observing right now";
      countUp($("stat-subs"), s.aavso_submitted, 1600);
      countUp($("stat-nodes"), s.nodes_online, 1200);
      countUp($("stat-accept"), accept, 1400, "%");
      countUp($("stat-countries"), nCountries, 1200);
      $("network-heading").textContent = s.nodes_total + " nodes. " + nCountries + " countries. One sky.";

      // best node drives the hero gauge
      var best = (s.nodes || []).slice().sort(function (a, b) {
        return (b.reliability_score || 0) - (a.reliability_score || 0);
      })[0];
      if (best) {
        var rel = best.reliability_score || 0.5, mult = 0.5 + 0.5 * rel;
        drawGauge(rel);
        $("gauge-node").textContent = best.node_id + " · reliability";
        $("gauge-num").textContent = rel.toFixed(2);
        $("gauge-num").style.color = rel >= 0.85 ? "#54D98C" : rel >= 0.65 ? "#4F8BFF" : "#E8A93A";
        $("gauge-lbl").textContent = (rel >= 0.85 ? "proven node" : "active node") + " · ×" + mult.toFixed(2);
      }
      placeMap(s.nodes || []);
    });

    // ---- SS Cyg light curve (hero mini + full section) ----
    getJSON("/api/v1/lightcurves/SS%20Cyg?days=30").then(function (lc) {
      if (!lc || !lc.points || !lc.points.length) return;
      var pts = lc.points.map(function (p) { return { m: p.magnitude, ok: !!p.aavso_submitted }; });
      var nodes = {}, ok = 0;
      lc.points.forEach(function (p) { nodes[p.node_id] = 1; if (p.aavso_submitted) ok++; });
      var pct = Math.round(ok / lc.points.length * 100);

      $("curve-target").textContent = "SS Cyg — light curve";
      $("curve-meta").textContent = "RA 21ʰ42ᵐ42.8ˢ · Dec +43°35′10″ · CV filter · " +
        Object.keys(nodes).length + " nodes · " + lc.points.length + " points";
      $("curve-badge").textContent = pct + "% AAVSO accepted";

      animateCurve($("lightcurve"), pts, { grid: true }, 2600);
      animateCurve($("minicurve"), pts, { thin: true }, 2000);
      fillConsole(lc.points);
    });

    // ---- targets → label the hero reticles with real catalogue objects ----
    getJSON("/api/v1/targets").then(function (t) {
      if (!t || !t.targets || !t.targets.length) return;
      var real = t.targets.filter(function (x) { return typeof x.mag === "number"; })
        .slice(0, 6).map(function (x) { return { name: x.name, mag: x.mag }; });
      if (real.length && sky) { sky.setTargets(real); }   // re-seed with real targets
    });
  }

  document.addEventListener("DOMContentLoaded", boot);
})();
