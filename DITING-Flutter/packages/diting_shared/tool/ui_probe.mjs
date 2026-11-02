// On-device UI audit: drives a debug build over the Dart VM Service, walks every
// route, captures a screencap plus the real global rects of all texts/containers,
// then turns layout problems into reviewable numbers.
//
// Usage:
//   node tool/ui_probe.mjs launch                 # launch app, connect to VM Service
//   node tool/ui_probe.mjs one /settings          # single page: go + screenshot + audit
//   node tool/ui_probe.mjs all [limit]            # every route in tool/routes.txt
//   node tool/ui_probe.mjs scroll /settings 3     # scroll 3 screens, audit each
//   node tool/ui_probe.mjs tap 120 300            # tap at logical coords (scaled to px)
//   node tool/ui_probe.mjs sheet /logs 205 430 Title  # open a sheet, then audit
//   node tool/ui_probe.mjs shot /settings name    # screenshot only
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const SERIAL = process.env.DITING_SERIAL || '';
const OUT = path.resolve('tool/uiprobe');
const ROUTES_FILE = process.env.DITING_ROUTES
  ? path.resolve(process.env.DITING_ROUTES)
  : path.resolve('tool/routes.txt');
const adb = (...a) => execFileSync('adb', [...(SERIAL ? ['-s', SERIAL] : []), ...a], { maxBuffer: 1 << 28 });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let ws = null;
let nextId = 1;
let isolateId = null;
let dpr = 3.25;
const pending = new Map();

function send(method, params = {}) {
  const id = nextId++;
  ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} 超时`));
    }, 15000);
    pending.set(id, {
      resolve: (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      reject: (e) => {
        clearTimeout(timer);
        reject(e);
      },
    });
  });
}

async function openSocket(url) {
  for (let attempt = 0; attempt < 15; attempt++) {
    try {
      const s = new WebSocket(url);
      await new Promise((res, rej) => {
        const t = setTimeout(() => rej(new Error('ws timeout')), 4000);
        s.onopen = () => {
          clearTimeout(t);
          res();
        };
        s.onerror = (e) => {
          clearTimeout(t);
          rej(new Error(`ws error: ${e.type || e.message}`));
        };
      });
      return s;
    } catch {
      await sleep(600);
    }
  }
  throw new Error(`无法连接 VM Service: ${url}`);
}

async function connect({ attach = false } = {}) {
  if (!attach) {
    adb('logcat', '-c');
    adb('shell', 'am', 'force-stop', 'com.haoze.diting');
    await sleep(300);
    adb('shell', 'am', 'start', '-n', 'com.haoze.diting/.MainActivity');
  }
  let uri = null;
  for (let i = 0; i < 40 && !uri; i++) {
    // Attach mode reads existing logs only: `-c` would wipe the "service
    // listening" line, leaving nothing to match.
    const log = adb('logcat', '-d').toString('utf8');
    const m = log.match(/Dart VM service is listening on (http:\/\/127\.0\.0\.1:(\d+)\/([^/]+)\/)/);
    if (m) uri = { url: m[1], port: m[2], token: m[3] };
    else await sleep(700);
  }
  if (!uri) throw new Error('VM service URI not found in logcat');
  adb('forward', `tcp:${uri.port}`, `tcp:${uri.port}`);
  ws = await openSocket(`ws://127.0.0.1:${uri.port}/${uri.token}/ws`);
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(JSON.stringify(msg.error)));
      else resolve(msg.result);
    }
  };
  ws.onerror = () => {};
  // Several isolates can linger on device (a restarting app keeps the old one).
  // Only the isolate that registered the probe extension is the live UI one.
  //
  // Right after `am start` that isolate may not have registered yet; failing on
  // the first miss would misread a slow start as a missing probe, so poll.
  for (let attempt = 0; attempt < 30; attempt++) {
    const vm = await send('getVM');
    for (const iso of vm.isolates ?? []) {
      isolateId = iso.id;
      try {
        await ext('ext.diting.probe');
        return uri;
      } catch {
        /* try the next isolate */
      }
    }
    await sleep(500);
  }
  throw new Error('没有任何 isolate 注册 ext.diting.probe');
}

async function ext(method, args = {}) {
  // A debug build started by `am start` has no DDS wrapper, so service
  // extensions are called directly as `ext.*`; `callServiceExtension` only
  // exists behind DDS.
  let r;
  try {
    r = await send(method, { isolateId, ...args });
  } catch {
    r = await send('callServiceExtension', { method, args: { isolateId, ...args } });
  }
  try {
    return JSON.parse(r);
  } catch {
    return r;
  }
}

async function probe() {
  const p = await ext('ext.diting.probe');
  if (p.screen) dpr = p.screen.dpr;
  return p;
}

function slug(loc) {
  return loc.replace(/^\/+/, '').replace(/[^a-zA-Z0-9]+/g, '_') || 'home';
}

function shot(name) {
  fs.mkdirSync(OUT, { recursive: true });
  const buf = adb('exec-out', 'screencap', '-p');
  const file = path.join(OUT, `${name}.png`);
  fs.writeFileSync(file, buf);
  return file;
}

/**
 * Turns "looks wrong" into reviewable numbers.
 *
 * `scrolled` dumps describe a list already moved to its end: rows legitimately
 * travel under the floating header there (`extendBodyBehindAppBar`), so the
 * "content painted into the app bar" rule only applies to a page at rest.
 */
function audit(p, label, { scrolled = false } = {}) {
  const f = [];
  if (p.error) return [`${label}: 探针失败 ${p.error}`];
  const { w: SW, h: SH, dpr: DPR } = p.screen;
  // The probe reports padding in physical pixels (FlutterView.viewPadding), so
  // convert to dp before comparing with text coords.
  const pad = { top: p.pad.top / DPR, bottom: p.pad.bottom / DPR };
  const bar = (p.boxes || []).filter((b) => b.k === 'AppBar').sort((a, b) => b.y + b.h - (a.y + a.h))[0];
  const barBottom = bar ? bar.y + bar.h : pad.top;
  const dock = (p.boxes || []).find((b) => b.k.includes('NavigationDock'));
  const inDock = (t) => dock && t.y >= dock.y - 1 && t.y + t.h <= dock.y + dock.h + 1;
  const visible = p.texts.filter((t) => !t.off && t.y >= 0 && t.y + t.h <= SH);
  // Rows clipped by the viewport were never painted (a list stopped mid-scroll
  // always has its last row touching the bottom edge); only text inside the
  // viewport that lands in system bar padding is a real problem.
  const painted = visible.filter((t) => t.y + t.h <= (t.vb ?? SH) + 0.5);
  const content = visible.filter((t) => !inDock(t) && !t.bar && t.y >= barBottom - 2);
  if (visible.length === 0) f.push(`${label}: 屏幕无可见文本（空白页？）`);
  else if (visible.length < 4 && (p.boxes || []).some((b) => b.k === 'PageBody'))
    f.push(`${label}: 正文近乎空白（整页只有 ${visible.length} 行文本）`);
  for (const d of p.diag || []) f.push(`${label}: 渲染异常 ${d}`);
  for (const t of painted) {
    if (t.clip) f.push(`${label}: 文本超出右边界 需${t.w}dp 可用${(SW - t.x).toFixed(1)}dp: 「${t.s}」`);
    if (!scrolled && t.y < barBottom - 2 && !inDock(t) && !t.bar && t.y + t.h > pad.top)
      f.push(`${label}: 内容画进顶栏区(y=${t.y} < 栏底 ${barBottom.toFixed(1)}): 「${t.s}」`);
    // System gesture bar: only body text painted into the bar padding counts,
    // wrapped lines from scrolling do not.
    if (t.y + t.h > SH - pad.bottom + 1 && !inDock(t))
      f.push(`${label}: 正文侵入系统导航条区(${t.y + t.h} > ${(SH - pad.bottom).toFixed(1)}): 「${t.s}」`);
  }
  // Space under the app bar is judged by the first thing actually painted on
  // screen (text or card/image), not by the first line of text: a card header or
  // an icon grid without text occupies that space just as well.
  // Keep this list in sync with `_structureTypes` in debug_probe.dart; a missing
  // type makes the space it occupies look like a gap (Chart, _FeatureCard,
  // CustomPaint, Button and GlyphIcon were each missed once).
  const effectLayers = /^(?:ImageFiltered|FadeIn|Animated|Semantics|Focus|Mouse|Scrollable|Viewport|Sliver|Layout|Padding|Constrained|Offstage|Visibility|Theme|Inherited|Builder|ValueListenable|ScaffoldMessenger|ScaffoldScope|CommonScaffold|AppBarInsetScope|PageBody|AppBarClearance|_Body|_Glass)/;
  const scaffoldLayers = /(?:_Scaffold|_Material|_Ink|_Tooltip|_ErrorWidget|_Hero|_EffectiveText|_SizeChanged|_Merge|_InlineSpan|CardEntrance|FloatingActionButtonTransition)/;
  const blockBoxes = (p.boxes || []).filter(
    (b) =>
      /Card|Grid|Image|Header|Control|Gallery|Strip|Field|Chart|Tile|Code|Preview|Frame|Panel|Button|CustomPaint|GlyphIcon|EditableText|TextField/.test(
        b.k,
      ) &&
      !effectLayers.test(b.k) &&
      !scaffoldLayers.test(b.k) &&
      b.w > 40 &&
      b.h > 40 &&
      // A full-screen layer is a scroll container or effect layer, not content;
      // keeping it would make "first content" always the bar bottom.
      b.h < SH * 0.7 &&
      b.y >= barBottom - 2 &&
      b.y < SH - 1 &&
      // The floating bar's own glass layer is also a `CustomPaint`; counting it
      // as content would report the normal space after a list ends as a gap.
      !(dock && b.y >= dock.y - 1 && b.y < dock.y + dock.h),
  );
  const firstBox = blockBoxes.sort((a, b) => a.y - b.y)[0];
  const firstText = content.filter((t) => t.y > barBottom - 8).sort((a, b) => a.y - b.y)[0];
  const first =
    firstBox && (!firstText || firstBox.y <= firstText.y)
      ? { y: firstBox.y, s: `${firstBox.k} 块` }
      : firstText;
  // Centered / full-height layouts (onboarding steps, scan frame, empty states)
  // have symmetric padding by design, so judging by "distance from bar bottom"
  // would flag them. Neither case is a collapse:
  //   - no room left below (content runs to the area bottom) => full-height
  //     layout, the top gap is its own breathing room;
  //   - comparable gaps above and below => centered layout.
  // Only "empty above, empty below, and clearly unequal" means content got pushed
  // down.
  //
  // The usable bottom edge is the content's scroll viewport (`vb`), not the
  // screen bottom: buttons pinned to the screen bottom sit outside the viewport,
  // so a screen-bottom measurement makes the gap below almost 0 and centering
  // becomes undetectable.
  const bodyBottom = (() => {
    const tally = new Map();
    for (const t of content) tally.set(t.vb ?? SH, (tally.get(t.vb ?? SH) || 0) + 1);
    return tally.size ? [...tally.entries()].sort((a, b) => b[1] - a[1])[0][0] : SH;
  })();
  const lastInArea = content
    .filter((t) => t.y + t.h <= bodyBottom + 0.5)
    .reduce((m, t) => Math.max(m, t.y + t.h), 0);
  const gapAbove = first ? first.y - barBottom : 0;
  const gapBelow = first ? bodyBottom - lastInArea : 0;
  const centered =
    first && (gapBelow < 60 || (gapAbove > 60 && gapAbove / gapBelow < 2.5));
  // A page scrolled to its end has no "top of content" to judge: the first
  // visible row is simply wherever the scroll stopped.
  if (first && !centered && !scrolled) {
    const gap = first.y - barBottom;
    // A block (card header / card) hugging the bar bottom is fine: it carries its
    // own padding, so text never sits on the bar.
    if (gap > 60) f.push(`${label}: 顶栏下空档 ${gap.toFixed(0)}dp（首块「${first.s}」y=${first.y.toFixed(1)}，栏底=${barBottom.toFixed(0)}，内容区底=${bodyBottom.toFixed(0)}，下方余 ${gapBelow.toFixed(0)}）`);
    else if (firstText && gap < 6 && firstText.y - barBottom < 6)
      f.push(`${label}: 正文顶到栏底仅 ${(firstText.y - barBottom).toFixed(0)}dp: 「${firstText.s}」`);
  }
  // Left-edge consistency: compare only the outer card shell, not arbitrary text.
  //
  // Counting by "visual line starts" does not work: inside a card a row places
  // chip / value / label side by side, so line starts legitimately differ.
  // Using the `ListHeader` rect as a reference column does not work either: it
  // is a full-width container (x=0) while text starts at 16.
  //
  // Only the outermost shell is judged: nested rows (`ListItem`, card-in-card)
  // are indented further by design. Expected column is the 16 design constant
  // (`pageContentPadding`), tolerance 8.
  const shellCandidates = (p.boxes || []).filter(
    (b) =>
      /^(?:CommonCard|DecorationListItem|ListTile)/.test(b.k) &&
      b.w > SW * 0.5 &&
      b.y >= barBottom - 2 &&
      b.y < SH - 1,
  );
  const contains = (a, b) =>
    b.x >= a.x - 0.5 &&
    b.y >= a.y - 0.5 &&
    b.x + b.w <= a.x + a.w + 0.5 &&
    b.y + b.h <= a.y + a.h + 0.5 &&
    b.w * b.h < a.w * a.h;
  const seenRect = new Set();
  const cardLike = shellCandidates.filter((a) => {
    if (shellCandidates.some((b) => b !== a && contains(b, a))) return false;
    const k = `${a.x},${a.y},${a.w},${a.h}`;
    if (seenRect.has(k)) return false;
    seenRect.add(k);
    return true;
  });
  const touching = cardLike.filter((b) => b.x < 1 || b.x + b.w > SW - 1);
  if (touching.length) {
    f.push(`${label}: 卡片贴住屏幕边沿 ${touching.length} 处（首处 x=${touching[0].x} w=${touching[0].w}，屏宽 ${SW}）`);
  }
  const over = cardLike.filter((b) => b.x > 24);
  if (over.length) {
    f.push(`${label}: 卡片缩进超过设计列 16 处（首处 x=${over[0].x}，疑重复加边距）`);
  }
  // Abnormal gap: vertical space between adjacent blocks (text or card/image) in
  // the content area.
  //
  // Entries contained by a bigger block are dropped first: the hint lines inside
  // a 360dp input box, or each text row inside a card, must not take part in gap
  // math, otherwise "bottom of hint text -> top of next card" measures as a huge
  // gap when that distance is the input's own interior.
  const rects = [
    ...content.map((t) => ({ y: t.y, h: t.h, s: t.s, x: t.x, w: t.w })),
    ...blockBoxes.map((b) => ({ y: b.y, h: b.h, s: b.k, x: b.x, w: b.w })),
  ];
  const inside = (a, b) =>
    a !== b &&
    a.y >= b.y - 0.5 &&
    a.y + a.h <= b.y + b.h + 0.5 &&
    a.x >= b.x - 0.5 &&
    a.x + a.w <= b.x + b.w + 0.5 &&
    a.h * a.w < b.h * b.w;
  const items = rects
    .filter((a) => !rects.some((b) => inside(a, b)))
    // Buttons / bars pinned to the screen bottom live outside the scroll
    // viewport; the large gap between them and the body is just "content shorter
    // than one screen", not a collapsed gap.
    .filter((a) => a.y < bodyBottom - 1)
    .sort((a, b) => a.y - b.y);
  let maxGap = 0,
    gapAt = '';
  for (let i = 1; i < items.length; i++) {
    const gap = items[i].y - (items[i - 1].y + items[i - 1].h);
    if (gap > maxGap) {
      maxGap = gap;
      gapAt = `${items[i - 1].s}→${items[i].s}`;
    }
  }
  if (maxGap > 90) f.push(`${label}: 纵向留白 ${maxGap.toFixed(0)}dp（${gapAt}）`);
  // Dock occlusion: content text falling inside the floating bar rect (the bar's
  // own labels excluded). Same scope as the header rule: with `extendBody` the
  // list scrolls under the floating bar, so rows sitting beneath it at rest are
  // the normal overlay state; only the end of the list has to clear it.
  if (dock && scrolled) {
    for (const t of painted) {
      if (!inDock(t) && !t.bar && t.y + t.h > dock.y + 2 && t.y < dock.y + dock.h)
        f.push(`${label}: 文本被底栏盖住: 「${t.s}」`);
    }
  }
  return f;
}

async function gotoRoute(loc, waitMs = 900) {
  // Right after launch `rootNavigatorKey.currentContext` is still null and `go`
  // silently returns `ok: false` (the probe does not error), so a "navigation
  // succeeded" is really the home page. Validate the response and retry.
  for (let attempt = 0; attempt < 10; attempt++) {
    const r = await ext('ext.diting.go', { loc });
    if (r && r.ok) {
      await sleep(waitMs);
      return;
    }
    await sleep(500);
  }
  throw new Error(`跳转到 ${loc} 失败（导航器未就绪）`);
}

/** Max vertical shift between two probes: rects and screenshot disagree while animations settle. */
function layoutShift(a, b) {
  const byLabel = new Map((a.texts || []).map((t) => [t.s, t.y]));
  let d = 0;
  for (const t of b.texts || []) {
    if (byLabel.has(t.s)) d = Math.max(d, Math.abs(byLabel.get(t.s) - t.y));
  }
  return d;
}

function textSignature(p, withY) {
  return JSON.stringify((p.texts || []).map((t) => (withY ? [t.s, t.y] : t.s)));
}

/**
 * Poll until the tree is actually still.
 *
 * `ext.diting.go` resolves before the target route builds, so the first probes
 * after a jump still describe the *outgoing* page mid-transition: the tab
 * animation sits at `amount ~ 0`, which paints it fully transparent and shifted
 * by 4% of the width. Screenshotting then yields a blank frame and rects that
 * look like the cards stick out of the screen. Waiting for two consecutive
 * identical probes (labels *and* y) plus a route change since `before` avoids
 * both false positives.
 */
async function settle(before = null) {
  let last = await probe();
  for (let i = 0; i < 24; i++) {
    await sleep(250);
    const cur = await probe();
    const still = textSignature(cur, true) === textSignature(last, true);
    const moved = !before || textSignature(cur, false) !== textSignature(before, false);
    if (still && moved) return cur;
    last = cur;
  }
  return last;
}

/** Navigate and capture, so screenshot and rects come from the same still frame. */
async function capture(loc, move = true, suffix = '') {
  const before = await probe();
  if (move) await gotoRoute(loc);
  const s = slug(loc) + suffix;
  const p = await settle(before);
  shot(s);
  return p;
}

async function swipeUp() {
  const [w, h] = adb('shell', 'wm', 'size').toString().match(/(\d+)x(\d+)/).slice(1).map(Number);
  adb('shell', 'input', 'swipe', String(w / 2), String(h * 0.75), String(w / 2), String(h * 0.3), '260');
  await sleep(500);
}

async function main() {
  const [cmd, a1, a2, a3, a4] = process.argv.slice(2);

  // Audit rules run offline so tuning a threshold does not need a device round
  // trip.
  //
  // Only routes still listed in `routes.txt` are audited: the output dir keeps
  // dumps of early ad-hoc routes (like `/profiles_edit`) that were since replaced
  // by path parameters, and auditing those yields fake "page missing" findings.
  if (cmd === 'reaudit') {
    const live = new Set(
      fs
        .readFileSync(ROUTES_FILE, 'utf8')
        .split(/\r?\n/)
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith('#'))
        .map(slug),
    );
    const files = fs
      .readdirSync(OUT)
      .filter((f) => f.endsWith('.json') && f !== 'summary.json')
      .filter((f) => live.has(f.replace(/\.json$/, '')))
      .filter((f) => !a1 || f.startsWith(slug(a1) + '.'))
      .sort();
    const skipped = fs
      .readdirSync(OUT)
      .filter((f) => f.endsWith('.json') && f !== 'summary.json' && !live.has(f.replace(/\.json$/, '')));
    const bad = [];
    for (const f of files) {
      const p = JSON.parse(fs.readFileSync(path.join(OUT, f), 'utf8'));
      const label = f.replace(/\.json$/, '');
      const findings = audit(p, label);
      if (findings.length) {
        bad.push(label);
        console.log(findings.join('\n'));
      }
    }
    console.log(
      `\n===== 离线复检：${files.length} 页（跳过 ${skipped.length} 份非当前路由的旧 dump），${bad.length} 页有发现 =====`,
    );
    return;
  }

  // `now`/`go` measure the current screen and must attach to a running instance:
  // `one`/`sheet` restart the app, which closes any sheet and resets in-memory
  // settings (glass level) to defaults. Use `go` to set a level on the appearance
  // page and then measure other pages.
  await connect({ attach: cmd === 'now' || cmd === 'go' });
  fs.mkdirSync(OUT, { recursive: true });

  if (cmd === 'one') {
    const p = await capture(a1);
    const s = slug(a1);
    fs.writeFileSync(path.join(OUT, `${s}.json`), JSON.stringify(p, null, 1));
    const f = audit(p, a1);
    console.log(f.length ? f.join('\n') : `${a1}: OK (${p.texts.filter((t) => !t.off).length} 文本)`);
  } else if (cmd === 'tail') {
    // Scroll to the list end before auditing: dock and gesture-bar padding only
    // show up on the last screen.
    await gotoRoute(a1);
    // Swipe until two rounds in a row move nothing. One swipe covers 45% of the
    // screen, so a long page needs several, and a single unchanged pair is not
    // enough to call it the end: the frame right after a fling still reports the
    // pre-fling offsets.
    let previous = await probe();
    let still = 0;
    for (let i = 0; i < 30; i++) {
      await swipeUp();
      const current = await probe();
      still = layoutShift(previous, current) < 2 ? still + 1 : 0;
      previous = current;
      if (still >= 2) break;
    }
    const p = await capture(a1, false, '_tail');
    fs.writeFileSync(path.join(OUT, `${slug(a1)}_tail.json`), JSON.stringify(p, null, 1));
    const f = audit(p, `${a1} 滚到底`, { scrolled: true });
    console.log(f.length ? f.join('\n') : `${a1} 滚到底: OK`);
  } else if (cmd === 'all') {
    const routes = fs
      .readFileSync(ROUTES_FILE, 'utf8')
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith('#'))
      .slice(0, a1 ? Number(a1) : undefined);
    const summary = [];
    for (const r of routes) {
      try {
        const p = await capture(r);
        const s = slug(r);
        fs.writeFileSync(path.join(OUT, `${s}.json`), JSON.stringify(p));
        const f = audit(p, r);
        summary.push({ r, n: p.texts?.filter((t) => !t.off).length ?? 0, findings: f });
        console.log(f.length ? f.join('\n') : `${r}: OK`);
      } catch (e) {
        console.log(`${r}: 探针异常 ${String(e).slice(0, 120)}`);
        summary.push({ r, n: -1, findings: [`${r}: 异常 ${String(e).slice(0, 120)}`] });
      }
    }
    fs.writeFileSync(path.join(OUT, 'summary.json'), JSON.stringify(summary, null, 1));
    const bad = summary.filter((s) => s.findings.length);
    console.log(`\n===== 汇总：${summary.length} 页，${bad.length} 页有发现 =====`);
    for (const s of bad) console.log(`${s.r} [${s.findings.length}]`);
  } else if (cmd === 'scroll') {
    await gotoRoute(a1);
    const n = Number(a2 || 3);
    for (let i = 0; i < n; i++) {
      if (i) await swipeUp();
      const p = await probe();
      const s = `${slug(a1)}_s${i}`;
      fs.writeFileSync(path.join(OUT, `${s}.json`), JSON.stringify(p));
      shot(s);
      const f = audit(p, `${a1}#${i}`);
      console.log(f.length ? f.join('\n') : `${a1}#${i}: OK`);
    }
  } else if (cmd === 'tap') {
    await probe(); // Refresh dpr first; the default 3.25 misplaces taps on 2.625.
    const x = Math.round(Number(a1) * dpr);
    const y = Math.round(Number(a2) * dpr);
    adb('shell', 'input', 'tap', String(x), String(y));
    await sleep(900);
    console.log(`tap 逻辑(${a1},${a2}) → 物理(${x},${y}) dpr=${dpr}`);
  } else if (cmd === 'sheet') {
    // Sheet audit: navigate, tap to open the sheet, then capture in place.
    // `one` only measures the route's first screen and cannot see sheet header
    // occlusion; a sheet header is a `FloatingHeader` drawn over the body, so the
    // check compares the first body line's y against the bar bottom.
    await gotoRoute(a1);
    // Only `probe()` refreshes `dpr` from the device; without it the default 3.25
    // scales the tap to the wrong spot on other densities.
    await probe();
    const x = Math.round(Number(a2) * dpr);
    const y = Math.round(Number(a3) * dpr);
    adb('shell', 'input', 'tap', String(x), String(y));
    await sleep(1200);
    const label = `${a1} ⊃ ${a4 || `tap(${a2},${a3})`}`;
    const p = await capture(label, false);
    fs.writeFileSync(path.join(OUT, `${slug(label)}.json`), JSON.stringify(p, null, 1));
    const f = audit(p, label);
    console.log(f.length ? f.join('\n') : `${label}: OK (${p.texts.filter((t) => !t.off).length} 文本)`);
  } else if (cmd === 'go') {
    // Navigate after attaching to a running instance: no restart, so in-memory UI
    // settings (glass level, dock shape, tab animation) survive. `one`
    // force-stops every time, so this is the only way to measure a page with
    // glass enabled.
    await gotoRoute(a1);
    const p = await capture(a1, false);
    fs.writeFileSync(path.join(OUT, `${slug(a1)}.json`), JSON.stringify(p, null, 1));
    const f = audit(p, a1);
    console.log(f.length ? f.join('\n') : `${a1}: OK (${p.texts.filter((t) => !t.off).length} 文本)`);
  } else if (cmd === 'now') {
    // Measure the current screen without navigating: sheet header occlusion is
    // only measurable while the sheet is open, and `go` would close it.
    const label = a1 || 'now';
    const p = await capture(label, false);
    fs.writeFileSync(path.join(OUT, `${slug(label)}.json`), JSON.stringify(p, null, 1));
    const f = audit(p, label);
    console.log(f.length ? f.join('\n') : `${label}: OK (${p.texts.filter((t) => !t.off).length} 文本)`);
  } else if (cmd === 'shot') {
    if (a1) await gotoRoute(a1);
    shot(a2 || `shot_${Date.now()}`);
    console.log('shot saved');
  } else if (cmd === 'raw') {
    await gotoRoute(a1);
    console.log(JSON.stringify(await probe(), null, 1));
  } else {
    console.log('unknown cmd');
  }
  ws.close();
  process.exit(0);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
