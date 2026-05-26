// =============================================================
// Reverent Partners — Live Capital Market Dashboard
// Reads: data.json (produced by refresh.ps1)
// =============================================================

const DATA_URL     = './data.json';
const CAL_URL      = './calendar.json';
const CAL_WEEK_URL = './calendar-week.json';
const CAL_NEXT_WEEK_URL = './calendar-next-week.json';
const REFRESH_MS   = 60_000;
const MIN_IMPORTANCE = 2;   // 표시할 최소 importance (1=낮음, 2=중간, 3=높음)

// ─── Static deploy mode detection ─────────────────────────
// On localhost we're running serve.ps1 (full features).
// On a deployed host (Cloudflare Pages, etc.) there's no backend → switch
// to read-only mode: hide refresh/AI chat, read news/index.json instead of
// /news/list endpoint.
const IS_STATIC = !/^(localhost|127\.|0\.0\.0\.0|\[::1\])/i.test(window.location.hostname);
const NEWS_INDEX_URL = IS_STATIC ? './news/index.json' : '/news/list';
const MARKET_INDEX_URL = IS_STATIC ? './market/index.json' : '/market/list';
const DEALS_INDEX_URL = IS_STATIC ? './deals/index.json' : '/deals/list';
const TRADE_URL = './trade.json';
const MACRO_FROZEN_URL = './market-update-frozen.json';
const SHILLER_URL = './shiller.json';
const FEDWATCH_URL = './fedwatch.json';
const PEER_URL = './peer.json';
const IPO_URL = './ipo.json';

const FLAG_EMOJI = {
  United_States: '🇺🇸',
  South_Korea: '🇰🇷',
  Japan: '🇯🇵',
  China: '🇨🇳',
  Euro_Zone: '🇪🇺',
  United_Kingdom: '🇬🇧',
  Germany: '🇩🇪',
  Australia: '🇦🇺',
  Canada: '🇨🇦',
  Switzerland: '🇨🇭',
  New_Zealand: '🇳🇿',
};

// Investing.com flag key → Korean country label
const COUNTRY_KR = {
  United_States: '미국',
  South_Korea: '한국',
  China: '중국',
  Japan: '일본',
  Euro_Zone: '유로존',
  United_Kingdom: '영국',
  Germany: '독일',
  Australia: '호주',
  Canada: '캐나다',
  Switzerland: '스위스',
  New_Zealand: '뉴질랜드',
};

// Optional: 영문 지표명 → 한글 (필요시 추가)
const INDICATOR_KR = {
  'CPI (YoY)': 'Headline CPI (YoY)',
  'CPI (MoM)': 'Headline CPI (MoM)',
  'Core CPI (YoY)': 'Core CPI (YoY)',
  'Core CPI (MoM)': 'Core CPI (MoM)',
  'PPI (YoY)': 'Headline PPI (YoY)',
  'PPI (MoM)': 'Headline PPI (MoM)',
  'Core PPI (YoY)': 'Core PPI (YoY)',
  'PCE Price index (YoY)': 'Headline PCE (YoY)',
  'PCE price index (YoY)': 'Headline PCE (YoY)',
  'PCE Price Index (YoY)': 'Headline PCE (YoY)',
  'Core PCE Price Index (YoY)': 'Core PCE (YoY)',
  'Nonfarm Payrolls': '비농업고용지수',
  'ADP Nonfarm Employment Change': 'ADP 민간고용',
  'JOLTs Job Openings': 'JOLTs',
  'ISM Services PMI': 'ISM 비제조업 PMI',
  'ISM Non-Manufacturing PMI': 'ISM 비제조업 PMI',
  'ISM Manufacturing PMI': 'ISM 제조업 PMI',
  'Unemployment Rate': '실업률',
  'Retail Sales (MoM)': '소매판매 (MoM)',
  'GDP (QoQ)': 'GDP (QoQ)',
  'GDP (YoY)': 'GDP (YoY)',
  'Existing Home Sales': '기존주택매매',
  'Existing Home Sales (MoM)': '기존주택매매 (MoM)',
};

// English key → Korean display label
const LABELS = {
  // Index
  KOSPI: 'KOSPI', KOSDAQ: 'KOSDAQ', DOW: 'DOW',
  SPX: 'S&P500', NASDAQ: 'NASDAQ', SHANGHAI: 'Shanghai',

  // Rates
  KR3Y: '국고채 3년', KR10Y: '국고채 10년', CD91: 'CD (91일)',
  US2Y: '미국채 2년', US10Y: '미국채 10년', US30Y: '미국채 30년',

  // Commodities
  WTI: 'WTI', GOLD: '금', COPPER: '구리', WHEAT: '밀',

  // FX
  USDKRW: 'USD/KRW', USDEUR: 'USD/EUR', USDJPY: 'USD/JPY',
  USDCNY: 'USD/CNY', DXY: '달러인덱스',

  // CDS
  CDS_US: '미국', CDS_CN: '중국',

  // Sectors — S&P 500 GICS sector indices (^SP500-NN / ^GSPE)
  IT: 'IT (Tech)', HEALTHCARE: '헬스케어', DISCRET: '자유소비재',
  INDUSTRIALS: 'Industrials', STAPLES: '필수소비재',
  ENERGY: '에너지', FINANCIALS: '금융', MATERIALS: '원자재',
  UTILITIES: '유틸리티', REALESTATE: '부동산', COMM: '통신',
};

// ─── Format helpers ───────────────────────────────────────
function fmtNum(n, digits = 2) {
  if (n === null || n === undefined || isNaN(n)) return '—';
  return Number(n).toLocaleString('en-US', {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  });
}

function fmtPct(v, digits = 1) {
  if (v === null || v === undefined || isNaN(v)) return '—';
  const num = Number(v);
  const sign = num > 0 ? '+' : '';
  const cls = num > 0 ? 'pos' : num < 0 ? 'neg' : 'flat';
  return `<span class="${cls}">${sign}${num.toFixed(digits)}%</span>`;
}

function fmtBp(v) {
  if (v === null || v === undefined || isNaN(v)) return '—';
  const num = Number(v);
  const sign = num > 0 ? '+' : '';
  const cls = num > 0 ? 'pos' : num < 0 ? 'neg' : 'flat';
  return `<span class="${cls}">${sign}${Math.round(num)}</span>`;
}

function labelFor(row) {
  return LABELS[row.key] || row.key;
}

// ─── Row renderer ─────────────────────────────────────────
function renderRow(row) {
  const name = labelFor(row);

  if (!row.ok) {
    return `<tr><td>${name}</td><td colspan="4" class="loading">조회 실패</td></tr>`;
  }

  const isYield = row.type === 'bp';
  const isBpAbs = row.type === 'bp_abs';

  let currentStr;
  if (isYield) {
    currentStr = Number(row.current).toFixed(2) + '%';
  } else if (isBpAbs) {
    currentStr = fmtNum(row.current, 1);
  } else {
    currentStr = fmtNum(row.current, row.current < 10 ? 4 : 2);
  }

  const wow = (isYield || isBpAbs) ? fmtBp(row.wow) : fmtPct(row.wow);
  const mom = (isYield || isBpAbs) ? fmtBp(row.mom) : fmtPct(row.mom);
  const ytd = (isYield || isBpAbs) ? fmtBp(row.ytd) : fmtPct(row.ytd);

  const staticBadge = row.static ? ' <span class="static-tag" title="정적 데이터 (PDF 기준)">S</span>' : '';
  const asOfAttr = row.asOf ? ` title="As of ${row.asOf}"` : '';

  return `<tr>
    <td${asOfAttr}>${name}${staticBadge}</td>
    <td class="num-col">${currentStr}</td>
    <td class="num-col">${wow}</td>
    <td class="num-col">${mom}</td>
    <td class="num-col">${ytd}</td>
  </tr>`;
}

function renderGroup(tableId, rows) {
  const tbody = document.querySelector(`#${tableId} tbody`);
  if (!tbody) return;
  if (!rows || rows.length === 0) {
    tbody.innerHTML = `<tr><td colspan="5" class="loading">데이터 없음</td></tr>`;
    return;
  }
  tbody.innerHTML = rows.map(renderRow).join('');
}

// ─── Macro indicator table — dynamic from calendar.json ───
function countryLabel(flagKey, currency) {
  if (flagKey && COUNTRY_KR[flagKey]) return COUNTRY_KR[flagKey];
  return currency || flagKey || '—';
}

function indicatorLabel(name) {
  if (!name) return '—';
  return INDICATOR_KR[name] || name;
}

function importanceStars(n) {
  const filled = Math.min(Math.max(n || 0, 0), 3);
  return '<span class="imp">' + '★'.repeat(filled) + '<span class="imp-dim">' + '☆'.repeat(3 - filled) + '</span></span>';
}

function renderMacroFromCalendar(payload) {
  const tbody = document.getElementById('macroBody');
  if (!tbody) return;

  if (!payload || !payload.events || payload.events.length === 0) {
    renderMacroFallback();
    return;
  }

  const events = payload.events.filter((e) => (e.importance || 0) >= MIN_IMPORTANCE);
  if (events.length === 0) {
    renderMacroFallback();
    return;
  }

  let html = '';
  let lastType = null;

  events.forEach((e) => {
    if (e.type !== lastType) {
      html += `<tr class="section-divider"><td colspan="8">${
        e.type === 'review' ? 'Review (발표 완료)' : 'Preview (발표 예정)'
      }</td></tr>`;
      lastType = e.type;
    }

    const actual = e.actual
      ? `<td class="num-col actual">${e.actual}</td>`
      : `<td class="num-col actual"><span class="loading">—</span></td>`;
    const previous = e.previous
      ? `<td class="num-col previous">${e.previous}</td>`
      : `<td class="num-col previous">—</td>`;

    const dateTime = e.time ? `${e.date} ${e.time}` : (e.date || '—');

    html += `<tr class="${e.type}">
      <td>${countryLabel(e.flagKey, e.currency)}</td>
      <td title="${e.datetime || ''}">${dateTime}</td>
      <td>${indicatorLabel(e.indicator)} ${importanceStars(e.importance)}</td>
      <td>${e.period || '—'}</td>
      ${actual}
      <td class="num-col">${e.forecast || '—'}</td>
      ${previous}
      <td>—</td>
    </tr>`;
  });
  tbody.innerHTML = html;
}

function renderMacroFallback() {
  const tbody = document.getElementById('macroBody');
  if (!tbody || typeof MACRO_DATA === 'undefined') return;
  let html = '';
  let lastType = null;
  MACRO_DATA.forEach((d) => {
    if (d.type !== lastType) {
      html += `<tr class="section-divider"><td colspan="8">${
        d.type === 'review' ? 'Review' : 'Preview'
      }</td></tr>`;
      lastType = d.type;
    }
    const actual = d.actual
      ? `<td class="num-col actual">${d.actual}</td>`
      : `<td class="num-col actual"><span class="loading">—</span></td>`;
    html += `<tr class="${d.type}">
      <td>${d.country}</td>
      <td>${d.date}</td>
      <td>${d.indicator}</td>
      <td>${d.period}</td>
      ${actual}
      <td class="num-col">${d.forecast || '—'}</td>
      <td class="num-col previous">${d.previous || '—'}</td>
      <td>${d.unit}</td>
    </tr>`;
  });
  tbody.innerHTML = html;
}

async function loadCalendar() {
  // Market Update now shows a frozen weekly digest (this week + next week,
  // top 5 each), updated at weekend by fetch-calendar.ps1. The legacy "today"
  // single-table rendering and macro.js static fallback are gone.
  try {
    const res = await fetch(`${MACRO_FROZEN_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    renderMacroWeekly(data);
  } catch (err) {
    console.warn('market-update-frozen.json fetch failed:', err);
    renderMacroWeekly(null);
  }
}

function renderMacroWeekly(data) {
  const stamp = document.getElementById('macroFrozenStamp');
  if (stamp) {
    if (data && data.updatedKr) {
      stamp.textContent = `${data.updatedKr} (${data.frozenDow || ''})`;
    } else {
      stamp.textContent = '데이터 없음';
    }
  }

  // Rollover labels: once a freeze is ≥3 days old (i.e. it's past Mon),
  // last week's "이번 주" becomes "지난 주 (Review)" and last week's
  // "다음 주" becomes "이번 주 (Preview)".
  let leftLabel = '이번 주';
  let rightLabel = '다음 주';
  if (data && data.updatedKr) {
    const freezeDate = new Date(data.updatedKr.replace(' ', 'T').slice(0, 10) + 'T00:00:00');
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const daysSince = Math.floor((today - freezeDate) / 86400000);
    if (daysSince >= 3) {
      leftLabel  = '지난 주 (Review)';
      rightLabel = '이번 주 (Preview)';
    }
  }
  const lt = document.getElementById('macroLeftTitle');
  const rt = document.getElementById('macroRightTitle');
  if (lt) lt.textContent = leftLabel;
  if (rt) rt.textContent = rightLabel;

  renderMacroSide('macroThisWeekBody', data?.thisWeek);
  renderMacroSide('macroNextWeekBody', data?.nextWeek);
}

function renderMacroSide(tbodyId, events) {
  const tbody = document.getElementById(tbodyId);
  if (!tbody) return;
  if (!events || events.length === 0) {
    tbody.innerHTML = `<tr><td colspan="6" class="loading" style="text-align:center;color:var(--text-muted);">데이터 없음</td></tr>`;
    return;
  }
  tbody.innerHTML = events.map(e => {
    const actual   = (e.actual && e.actual !== '') ? `<td class="num-col actual">${e.actual}</td>` : `<td class="num-col actual">—</td>`;
    const forecast = (e.forecast && e.forecast !== '') ? `<td class="num-col">${e.forecast}</td>` : `<td class="num-col">—</td>`;
    const previous = (e.previous && e.previous !== '') ? `<td class="num-col previous">${e.previous}</td>` : `<td class="num-col previous">—</td>`;
    const dateTime = e.time ? `${e.date} ${e.time}` : (e.date || '—');
    return `<tr class="${e.type || ''}">
      <td>${countryLabel(e.flagKey, e.currency)}</td>
      <td title="${e.datetime || ''}">${dateTime}</td>
      <td>${indicatorLabel(e.indicator)} ${importanceStars(e.importance)}</td>
      ${actual}
      ${forecast}
      ${previous}
    </tr>`;
  }).join('');
}

// ─── Re-read data.json only (fast, ~ms) ───────────────────
async function loadData() {
  const updateEl = document.getElementById('lastUpdate');
  updateEl.innerHTML = '<span class="updating">읽는 중…</span>';

  try {
    const res = await fetch(`${DATA_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    renderGroup('indexTable',     data.index);
    renderGroup('rateTable',      data.rate);
    renderGroup('commodityTable', data.commodity);
    renderGroup('fxTable',        data.fx);
    renderGroup('cdsTable',       data.cds);
    renderGroup('sectorTable',    data.sector);

    const ts = new Date(data.updated);
    const krTime = new Intl.DateTimeFormat('ko-KR', {
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
      hour12: false, timeZone: 'Asia/Seoul',
    }).format(ts);

    updateEl.innerHTML = `<span class="live-dot"></span>${krTime}`;
  } catch (err) {
    console.error('Load failed:', err);
    updateEl.innerHTML =
      `<span style="color:#fca5a5;">data.json 로딩 실패 — serve.ps1을 실행하세요</span>`;
  }
}

// ─── Force live fetch from Yahoo + Investing (slow, ~15s) ─
async function forceRefresh() {
  const btn = document.getElementById('refreshBtn');
  const updateEl = document.getElementById('lastUpdate');
  const origLabel = btn.textContent;

  btn.disabled = true;
  btn.textContent = '⏳ Yahoo + Investing fetch 중…';
  updateEl.innerHTML = '<span class="updating">Yahoo + Investing.com 실시간 fetch 중… (약 15초)</span>';

  try {
    const res = await fetch(`/refresh?_=${Date.now()}`, {
      method: 'GET',
      cache: 'no-store',
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const r = await res.json();
    console.log('Server refresh result:', r);
    await Promise.all([loadData(), loadCalendar(), loadWeeklyCalendar()]);
  } catch (err) {
    console.error('Force refresh failed:', err);
    updateEl.innerHTML =
      `<span style="color:#fca5a5;">강제 새로고침 실패 — ${err.message}</span>`;
  } finally {
    btn.disabled = false;
    btn.textContent = origLabel;
  }
}

// ─── Clock ───────────────────────────────────────────────
function updateClock() {
  const now = new Date();
  document.getElementById('currentDateTime').textContent =
    new Intl.DateTimeFormat('ko-KR', {
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
      hour12: false, timeZone: 'Asia/Seoul',
    }).format(now);
}

// ─── Init ────────────────────────────────────────────────
// ─── Weekly Calendar View ─────────────────────────────────
let weeklyCache = null;
let weeklyFilters = { importance: 2, country: 'ALL' };

const KR_WEEKDAY = ['일','월','화','수','목','금','토'];

function parseInvestingDateTime(s) {
  if (!s) return null;
  const m = s.match(/^(\d{4})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/);
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
}

function todayKr() {
  const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit' });
  return fmt.format(new Date()); // YYYY-MM-DD
}

function dateKey(dt) {
  return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,'0')}-${String(dt.getDate()).padStart(2,'0')}`;
}

function formatDayLabel(dt) {
  return `${dt.getFullYear()}.${String(dt.getMonth()+1).padStart(2,'0')}.${String(dt.getDate()).padStart(2,'0')}`;
}

function renderWeeklyEventRow(e) {
  const flag = FLAG_EMOJI[e.flagKey] || '';
  const indicator = (typeof INDICATOR_KR !== 'undefined' && INDICATOR_KR[e.indicator]) || e.indicator || '—';
  const period = e.period ? `<span class="period-tag">(${e.period})</span>` : '';
  const stars = '★'.repeat(Math.min(e.importance || 0, 3));
  const isReleased = !!e.actual;
  const statusBadge = isReleased
    ? '<span class="event-status review">✓ 발표완료</span>'
    : '<span class="event-status preview">⏳ 예정</span>';

  const actualCell = isReleased
    ? `<div class="event-num-cell actual"><span class="num-label">실제</span><span class="num-value">${e.actual}</span></div>`
    : `<div class="event-num-cell dim"><span class="num-label">실제</span><span class="num-value">—</span></div>`;
  const forecastCell = e.forecast
    ? `<div class="event-num-cell"><span class="num-label">전망</span><span class="num-value">${e.forecast}</span></div>`
    : `<div class="event-num-cell dim"><span class="num-label">전망</span><span class="num-value">—</span></div>`;
  const previousCell = e.previous
    ? `<div class="event-num-cell"><span class="num-label">이전</span><span class="num-value">${e.previous}</span></div>`
    : `<div class="event-num-cell dim"><span class="num-label">이전</span><span class="num-value">—</span></div>`;

  return `
    <div class="event-row ${isReleased ? 'released' : ''}">
      <span class="event-imp" title="중요도 ${e.importance}">${stars}</span>
      <span class="event-time">${e.time || '—'}</span>
      <span class="event-country"><span class="flag">${flag}</span>${e.currency || ''}</span>
      <span class="event-indicator">${indicator}${period} ${statusBadge}</span>
      <div class="event-numbers">${actualCell}${forecastCell}${previousCell}</div>
    </div>
  `;
}

function renderWeeklyView() {
  const body = document.getElementById('weeklyBody');
  const statsEl = document.getElementById('weeklyStats');
  if (!body) return;

  if (!weeklyCache || !weeklyCache.events) {
    body.innerHTML = '<p class="loading" style="padding:40px;text-align:center;">캘린더 로딩 중…</p>';
    return;
  }

  const events = weeklyCache.events.filter(e => {
    if ((e.importance || 0) < weeklyFilters.importance) return false;
    if (weeklyFilters.country !== 'ALL' && e.flagKey !== weeklyFilters.country) return false;
    return true;
  });

  if (statsEl) {
    const releasedCount = events.filter(e => e.actual).length;
    statsEl.textContent = `${events.length}개 이벤트 (발표완료 ${releasedCount} · 예정 ${events.length - releasedCount}) — 전체 ${weeklyCache.events.length}개 중`;
  }

  if (events.length === 0) {
    body.innerHTML = '<div class="day-empty" style="padding:60px;">조건에 맞는 이벤트가 없습니다. 필터를 조정해보세요.</div>';
    return;
  }

  const groups = new Map();
  events.forEach(e => {
    const dt = parseInvestingDateTime(e.datetime);
    if (!dt) return;
    const key = dateKey(dt);
    if (!groups.has(key)) groups.set(key, { date: dt, events: [] });
    groups.get(key).events.push(e);
  });

  const sortedKeys = Array.from(groups.keys()).sort();
  const today = todayKr();

  body.innerHTML = sortedKeys.map(key => {
    const { date, events: dayEvents } = groups.get(key);
    const isToday = key === today;
    const isPast = key < today;
    const classes = ['day-group'];
    if (isToday) classes.push('is-today');
    else if (isPast) classes.push('is-past');

    const todayPill = isToday ? '<span class="today-pill">TODAY</span>' : '';
    const dayLabel = formatDayLabel(date);
    const weekday = KR_WEEKDAY[date.getDay()];

    return `
      <div class="${classes.join(' ')}">
        <div class="day-header">
          <span class="day-date">${dayLabel}</span>
          <span class="day-weekday">${weekday}요일</span>
          ${todayPill}
          <span class="day-count">${dayEvents.length}건</span>
        </div>
        <div class="day-events">
          ${dayEvents.map(renderWeeklyEventRow).join('')}
        </div>
      </div>
    `;
  }).join('');
}

async function loadWeeklyCalendar() {
  try {
    const res = await fetch(`${CAL_WEEK_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    weeklyCache = await res.json();
    renderWeeklyView();
  } catch (err) {
    console.warn('Weekly load failed:', err);
    const body = document.getElementById('weeklyBody');
    if (body) {
      body.innerHTML = `<div class="day-empty" style="padding:60px;color:#dc2626;">주간 캘린더 로딩 실패: ${err.message}</div>`;
    }
  }
}

function setupWeeklyFilters() {
  document.querySelectorAll('#impFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#impFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      weeklyFilters.importance = parseInt(btn.dataset.imp, 10);
      renderWeeklyView();
    });
  });
  document.querySelectorAll('#countryFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#countryFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      weeklyFilters.country = btn.dataset.country;
      renderWeeklyView();
    });
  });
}

// ─── News Clipping View ───────────────────────────────────
let newsState = { dates: [], current: null, cache: {}, sectorFilter: 'ALL' };

async function loadNewsIndex() {
  try {
    const res = await fetch(`${NEWS_INDEX_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    newsState.dates = data.dates || [];
    renderNewsDatePills();
    if (newsState.dates.length > 0) {
      const target = newsState.current && newsState.dates.includes(newsState.current)
        ? newsState.current
        : newsState.dates[0];
      await loadNewsDate(target);
    } else {
      renderNewsEmpty();
    }
  } catch (err) {
    console.warn('News index load failed:', err);
    renderNewsEmpty();
  }
}

function renderNewsDatePills() {
  const el = document.getElementById('newsDatePills');
  if (!el) return;
  if (newsState.dates.length === 0) {
    el.innerHTML = '<span style="font-size:12px;color:var(--text-muted);">저장된 클리핑 없음</span>';
    return;
  }
  const today = todayKr();
  el.innerHTML = newsState.dates.map(d => {
    const rel = (d === today) ? '<span class="pill-rel">오늘</span>' : '';
    const active = (d === newsState.current) ? ' active' : '';
    return `<button class="news-date-pill${active}" data-date="${d}">${d}${rel}</button>`;
  }).join('');
  el.querySelectorAll('.news-date-pill').forEach(btn => {
    btn.addEventListener('click', () => loadNewsDate(btn.dataset.date));
  });
}

async function loadNewsDate(date) {
  newsState.current = date;
  renderNewsDatePills();

  let md = newsState.cache[date];
  if (!md) {
    try {
      const res = await fetch(`/news/${date}.md?_=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      md = await res.text();
      newsState.cache[date] = md;
    } catch (err) {
      document.getElementById('newsBody').innerHTML =
        `<div class="news-empty"><h3>로딩 실패</h3><p>${err.message}</p></div>`;
      return;
    }
  }
  renderNewsContent(md);
}

function renderNewsEmpty() {
  document.getElementById('newsBody').innerHTML = `
    <div class="news-empty">
      <div class="news-empty-icon">📭</div>
      <h3>아직 저장된 클리핑이 없습니다</h3>
      <p>이 페이지는 매일 자동 생성되는 뉴스 클리핑을 6개 섹터 카드로 보여줍니다.</p>
      <p>⏰ <strong>다음 자동 실행</strong>: 내일 아침 09:03 KST</p>
      <p>지금 즉시 보고 싶으면: 새 Claude Code 세션에서 <code>/news-clipping</code> 수동 실행 (약 5~10분).</p>
    </div>`;
}

// ─── Markdown parser for news clipping format ─────────────
function parseNewsClipping(md) {
  const out = { title: '', date: '', sectors: [] };
  const lines = md.split(/\r?\n/);
  let sector = null;
  let article = null;
  let buf = [];

  const closeArticle = () => {
    if (article && sector) {
      article.bodyMd = buf.join('\n').trim();
      sector.articles.push(article);
    }
    article = null;
    buf = [];
  };

  for (const line of lines) {
    if (/^#\s/.test(line)) {
      out.title = line.replace(/^#\s+/, '').trim();
      const m = out.title.match(/(\d{4}-\d{2}-\d{2})/);
      if (m) out.date = m[1];
    } else if (/^##\s/.test(line)) {
      closeArticle();
      sector = { name: line.replace(/^##\s+/, '').trim(), articles: [] };
      out.sectors.push(sector);
    } else if (/^###\s/.test(line)) {
      closeArticle();
      let head = line.replace(/^###\s+/, '').trim();
      let type = '';
      const tm = head.match(/\((글로벌|국내)\)\s*$/);
      if (tm) {
        type = tm[1];
        head = head.replace(/\s*\((글로벌|국내)\)\s*$/, '').trim();
      }
      article = { headline: head, type, summary: [], implication: {}, source: null };
    } else if (article) {
      buf.push(line);
    }
  }
  closeArticle();

  // Parse each article's bodyMd into structured fields
  out.sectors.forEach(s => {
    s.articles.forEach(a => {
      const body = a.bodyMd || '';
      const bodyLines = body.split(/\r?\n/);
      let mode = '';
      for (const ln of bodyLines) {
        const t = ln.trim();
        if (!t) continue;
        if (/^\*\*3?문장?\s*Summary\*\*/i.test(t) || /^\*\*요약\*\*/.test(t)) {
          mode = 'summary'; continue;
        }
        if (/^\*\*Implication\*\*/i.test(t) || /^\*\*시사점\*\*/.test(t)) {
          mode = 'impl'; continue;
        }
        if (/^\*\*Source\*\*/i.test(t) || /^\*\*출처\*\*/.test(t)) {
          const m = t.match(/\[([^\]]+)\]\(([^)]+)\)/);
          if (m) a.source = { name: m[1], url: m[2] };
          mode = '';
          continue;
        }
        if (mode === 'summary' && /^\d+\./.test(t)) {
          a.summary.push(t.replace(/^\d+\.\s*/, ''));
        } else if (mode === 'impl' && /^[-•]\s*\*/.test(t)) {
          // - *Technical / Industry*: ...    or   - *Market / Flow / Valuation*: ...
          const m = t.match(/^[-•]\s*\*([^*]+)\*\s*:?\s*(.*)$/);
          if (m) {
            const label = m[1].trim();
            const text = m[2].trim();
            if (/Technical|Industry|기술|산업/i.test(label)) {
              a.implication.technical = text;
            } else if (/Market|Flow|Valuation|시장|밸류/i.test(label)) {
              a.implication.market = text;
            } else {
              a.implication[label] = text;
            }
          }
        }
      }
    });
  });

  return out;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function linkifyInline(s) {
  // simple **bold**, *italic*, [text](url)
  return escapeHtml(s)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(?<!\*)\*([^*\n]+)\*(?!\*)/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

function sectorIdFromName(name) {
  // "1. Tech / Data Infrastructure" → "1"
  const m = name.match(/^(\d+)\./);
  return m ? m[1] : null;
}

function renderNewsContent(md) {
  const body = document.getElementById('newsBody');
  if (!body) return;

  const parsed = parseNewsClipping(md);
  if (parsed.sectors.length === 0) {
    body.innerHTML = `<div class="news-empty"><h3>파싱 실패</h3><p>이 파일에서 섹터를 찾을 수 없습니다.</p></div>`;
    return;
  }

  const sectors = parsed.sectors.filter(s => {
    if (newsState.sectorFilter === 'ALL') return true;
    return sectorIdFromName(s.name) === newsState.sectorFilter;
  });

  const dateHeader = parsed.date
    ? `<div class="news-date-header">${parsed.title}</div>`
    : '';

  if (sectors.length === 0) {
    body.innerHTML = dateHeader + `<div class="news-empty"><p>선택한 섹터에 항목이 없습니다.</p></div>`;
    return;
  }

  body.innerHTML = dateHeader + sectors.map(s => {
    const articles = s.articles.length > 0
      ? s.articles.map(a => renderArticleCard(a)).join('')
      : '<div class="news-card" style="color:var(--text-muted);font-style:italic;">오늘 주목할 만한 뉴스 없음</div>';
    return `
      <div class="news-sector-block">
        <div class="news-sector-header">
          <span class="news-sector-title">${escapeHtml(s.name)}</span>
          <span class="news-sector-count">${s.articles.length}건</span>
        </div>
        <div class="news-articles">${articles}</div>
      </div>
    `;
  }).join('');
}

function renderArticleCard(a) {
  const typeClass = a.type === '글로벌' ? 'global' : (a.type === '국내' ? 'korea' : 'none');
  const typeLabel = a.type || '—';

  const summaryHtml = a.summary.length > 0
    ? `<div class="news-section news-summary">
         <h4 class="news-section-title">3문장 Summary</h4>
         <ol>${a.summary.map(s => `<li>${linkifyInline(s)}</li>`).join('')}</ol>
       </div>`
    : '';

  const impl = a.implication || {};
  const implRows = [];
  if (impl.technical) implRows.push(`<div class="impl-row"><span class="impl-label">Technical</span><span class="impl-text">${linkifyInline(impl.technical)}</span></div>`);
  if (impl.market) implRows.push(`<div class="impl-row"><span class="impl-label">Market</span><span class="impl-text">${linkifyInline(impl.market)}</span></div>`);
  Object.keys(impl).forEach(k => {
    if (k !== 'technical' && k !== 'market') {
      implRows.push(`<div class="impl-row"><span class="impl-label">${escapeHtml(k)}</span><span class="impl-text">${linkifyInline(impl[k])}</span></div>`);
    }
  });

  const implHtml = implRows.length > 0
    ? `<div class="news-section">
         <h4 class="news-section-title">Implication</h4>
         <div class="news-implication">${implRows.join('')}</div>
       </div>`
    : '';

  const sourceHtml = a.source
    ? `<div class="news-source">📎 <a href="${escapeHtml(a.source.url)}" target="_blank" rel="noopener">${escapeHtml(a.source.name)} →</a></div>`
    : '';

  return `
    <div class="news-card">
      <div class="news-card-head">
        <span class="news-type ${typeClass}">${escapeHtml(typeLabel)}</span>
        <h3 class="news-headline">${linkifyInline(a.headline)}</h3>
      </div>
      ${summaryHtml}
      ${implHtml}
      ${sourceHtml}
    </div>
  `;
}

function setupNewsFilters() {
  document.querySelectorAll('#newsSectorFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#newsSectorFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      newsState.sectorFilter = btn.dataset.sector;
      if (newsState.current && newsState.cache[newsState.current]) {
        renderNewsContent(newsState.cache[newsState.current]);
      }
    });
  });
}

// ─── Market Brief View ───────────────────────────────────
let marketState = { dates: [], current: null, cache: {} };

async function loadMarketIndex() {
  try {
    const res = await fetch(`${MARKET_INDEX_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    marketState.dates = data.dates || [];
    renderMarketDatePills();
    if (marketState.dates.length > 0) {
      const target = marketState.current && marketState.dates.includes(marketState.current)
        ? marketState.current
        : marketState.dates[0];
      await loadMarketDate(target);
    } else {
      renderMarketEmpty();
    }
  } catch (err) {
    console.warn('Market index load failed:', err);
    renderMarketEmpty();
  }
}

function renderMarketDatePills() {
  const el = document.getElementById('marketDatePills');
  if (!el) return;
  if (marketState.dates.length === 0) {
    el.innerHTML = '<span style="color:var(--text-muted);font-size:13px;">저장된 시황 없음</span>';
    return;
  }
  const today = todayKr();
  el.innerHTML = marketState.dates.map(d => {
    const rel = (d === today) ? '<span class="pill-rel">오늘</span>' : '';
    const active = (d === marketState.current) ? ' active' : '';
    return `<button class="news-date-pill${active}" data-date="${d}">${d}${rel}</button>`;
  }).join('');
  el.querySelectorAll('.news-date-pill').forEach(btn => {
    btn.addEventListener('click', () => loadMarketDate(btn.dataset.date));
  });
}

async function loadMarketDate(date) {
  marketState.current = date;
  renderMarketDatePills();
  let md = marketState.cache[date];
  if (!md) {
    try {
      const res = await fetch(`./market/${date}.md?_=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      md = await res.text();
      marketState.cache[date] = md;
    } catch (err) {
      document.getElementById('marketBody').innerHTML =
        `<div class="news-empty"><h3>로딩 실패</h3><p>${err.message}</p></div>`;
      return;
    }
  }
  renderMarketContent(md);
}

function renderMarketEmpty() {
  document.getElementById('marketBody').innerHTML = `
    <div class="news-empty">
      <div class="news-empty-icon">🌅</div>
      <h3>아직 저장된 시황이 없습니다</h3>
      <p>이 페이지는 매일 자동 생성되는 미 증시 마감 시황 대시보드를 보여줍니다.</p>
      <p>⏰ <strong>다음 자동 실행</strong>: 내일 아침 08:00 KST</p>
      <p>지금 즉시 보고 싶으면: 새 Claude Code 세션에서 <code>/morning-market</code> 수동 실행.</p>
    </div>
  `;
}

// Parse the morning-market markdown into structured sections.
// Expected format:
//   # 🌅 일일 시황 대시보드 — YYYY년 M월 D일
//   > 데이터 기준: ...
//   ## ◆ 미국 증시
//   - DOW: ...
//   ## ◆ 미국 국채시장
//   ## ◆ 외환 & 상품시장
//   ## ◆ 시황 코멘트
//   (paragraphs)
//   ## ◆ 특징주
//   ### 종목명 (±X.XX%)
//   (body)
function parseMarketBrief(md) {
  const out = { title: '', meta: '', indices: [], rates: [], fx: [], commentary: '', stocks: [] };
  const lines = md.split(/\r?\n/);
  let section = null;          // 'indices'|'rates'|'fx'|'commentary'|'stocks'
  let stockBuf = null;         // { name, change, body[] }
  const commentaryLines = [];

  const SECTION_MAP = {
    '미국 증시': 'indices',
    '미국 국채시장': 'rates',
    '외환 & 상품시장': 'fx',
    '외환&상품시장': 'fx',
    '시황 코멘트': 'commentary',
    '특징주': 'stocks',
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Title (first H1)
    if (!out.title && /^#\s+/.test(line)) {
      out.title = line.replace(/^#\s+/, '').trim();
      continue;
    }
    // Meta blockquote (> 데이터 기준: ...)
    if (!out.meta && /^>\s+/.test(line)) {
      out.meta = line.replace(/^>\s+/, '').trim();
      continue;
    }
    // Section header (## ◆ Name) or (## Name)
    const h2 = line.match(/^##\s+(?:◆\s+)?(.+?)\s*$/);
    if (h2) {
      // flush previous stock card if any
      if (stockBuf) { out.stocks.push(stockBuf); stockBuf = null; }
      section = SECTION_MAP[h2[1].trim()] || null;
      continue;
    }
    // Stock header (### 종목명 (±X.XX%))
    const h3 = line.match(/^###\s+(.+?)\s*$/);
    if (h3 && section === 'stocks') {
      if (stockBuf) out.stocks.push(stockBuf);
      const m = h3[1].match(/^(.+?)\s*\(([+-]?[\d.,]+%?)\)\s*$/);
      stockBuf = m
        ? { name: m[1].trim(), change: m[2].trim(), body: [] }
        : { name: h3[1].trim(), change: '', body: [] };
      continue;
    }

    // Body of each section
    if (section === 'indices' || section === 'rates' || section === 'fx') {
      const m = line.match(/^-\s+(.+?)\s*:\s*(.+?)\s*$/);
      if (m) {
        out[section].push({ label: m[1].trim(), value: m[2].trim() });
      }
    } else if (section === 'commentary') {
      commentaryLines.push(line);
    } else if (section === 'stocks' && stockBuf) {
      stockBuf.body.push(line);
    }
  }
  if (stockBuf) out.stocks.push(stockBuf);

  // Commentary: trim leading/trailing empty lines, collapse runs
  out.commentary = commentaryLines.join('\n').replace(/^\s+|\s+$/g, '');

  return out;
}

function renderMarketContent(md) {
  const body = document.getElementById('marketBody');
  if (!body) return;
  const p = parseMarketBrief(md);

  if (!p.title) {
    body.innerHTML = `<div class="news-empty"><h3>파싱 실패</h3><p>제목을 찾을 수 없습니다.</p></div>`;
    return;
  }

  const tableHtml = (rows) => rows.length === 0 ? '' : `
    <table class="market-brief-table">
      <tbody>
        ${rows.map(r => `<tr><th>${escapeHtml(r.label)}</th><td>${formatChangeValue(r.value)}</td></tr>`).join('')}
      </tbody>
    </table>
  `;

  const commentaryHtml = p.commentary
    ? `<div class="market-brief-commentary">${
        p.commentary.split(/\n\s*\n/).map(par =>
          `<p>${linkifyInline(par.replace(/\n/g, ' '))}</p>`
        ).join('')
      }</div>`
    : '';

  const stocksHtml = p.stocks.length === 0 ? '' : `
    <div class="market-brief-stocks">
      ${p.stocks.map(s => {
        const chgClass = s.change.startsWith('-') ? 'down' : (s.change.startsWith('+') ? 'up' : 'flat');
        const bodyText = s.body.join('\n').trim();
        return `
          <div class="market-stock-card">
            <div class="market-stock-head">
              <span class="market-stock-name">${escapeHtml(s.name)}</span>
              ${s.change ? `<span class="market-stock-change ${chgClass}">${escapeHtml(s.change)}</span>` : ''}
            </div>
            <div class="market-stock-body">${linkifyInline(bodyText)}</div>
          </div>
        `;
      }).join('')}
    </div>
  `;

  body.innerHTML = `
    <div class="market-brief-header">
      <h2 class="market-brief-title">${escapeHtml(p.title)}</h2>
      ${p.meta ? `<div class="market-brief-meta">${escapeHtml(p.meta)}</div>` : ''}
    </div>

    <div class="market-brief-grid">
      ${p.indices.length ? `<div class="market-brief-block"><h3>◆ 미국 증시</h3>${tableHtml(p.indices)}</div>` : ''}
      ${p.rates.length ? `<div class="market-brief-block"><h3>◆ 미국 국채시장</h3>${tableHtml(p.rates)}</div>` : ''}
      ${p.fx.length ? `<div class="market-brief-block"><h3>◆ 외환 & 상품시장</h3>${tableHtml(p.fx)}</div>` : ''}
    </div>

    ${commentaryHtml ? `<div class="market-brief-block market-brief-block-full"><h3>◆ 시황 코멘트</h3>${commentaryHtml}</div>` : ''}

    ${p.stocks.length ? `<div class="market-brief-block market-brief-block-full"><h3>◆ 특징주</h3>${stocksHtml}</div>` : ''}
  `;
}

// Color-code numeric change values inline: +x.xx% (green) / -x.xx% (red)
function formatChangeValue(text) {
  return escapeHtml(text)
    .replace(/(\(\s*)([+\-][\d,.]+(?:bp|p|%)?)([^)]*?)(\s*\))/g, (m, lp, n1, rest, rp) => {
      const cls = n1.startsWith('-') ? 'down' : 'up';
      return `${lp}<span class="chg ${cls}">${n1}</span>${rest}${rp}`;
    });
}

// ─── Deal Flow View ──────────────────────────────────────
//
// Update algorithm: Claude Code 세션에서 사용자가 매주 큐레이션 → deals/YYYY-MM-DD.md 저장.
// 대시보드는 정적 MD 파일만 읽음 (별도 API 호출/과금 없음, news·market 패턴과 동일).
//
let dealsState = { dates: [], current: null, cache: {}, calThisWeek: null, calNextWeek: null };

async function loadDealsCalendars() {
  if (dealsState.calThisWeek && dealsState.calNextWeek) return;
  const fetchJson = async (url) => {
    try {
      const res = await fetch(`${url}?_=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) return null;
      return await res.json();
    } catch (e) { return null; }
  };
  const [tw, nw] = await Promise.all([
    fetchJson(CAL_WEEK_URL),
    fetchJson(CAL_NEXT_WEEK_URL),
  ]);
  dealsState.calThisWeek = tw;
  dealsState.calNextWeek = nw;
}

async function loadDealsIndex() {
  try {
    const [idxRes] = await Promise.all([
      fetch(`${DEALS_INDEX_URL}?_=${Date.now()}`, { cache: 'no-store' }),
      loadDealsCalendars(),
    ]);
    if (!idxRes.ok) throw new Error(`HTTP ${idxRes.status}`);
    const data = await idxRes.json();
    dealsState.dates = data.dates || [];
    renderDealsDatePills();
    if (dealsState.dates.length > 0) {
      const target = dealsState.current && dealsState.dates.includes(dealsState.current)
        ? dealsState.current
        : dealsState.dates[0];
      await loadDealsDate(target);
    } else {
      renderDealsEmpty();
    }
  } catch (err) {
    console.warn('Deals index load failed:', err);
    renderDealsEmpty();
  }
}

function renderDealsDatePills() {
  const el = document.getElementById('dealsDatePills');
  if (!el) return;
  if (dealsState.dates.length === 0) {
    el.innerHTML = '<span style="color:var(--text-muted);font-size:13px;">저장된 Macro/자본시장/거래동향 없음</span>';
    return;
  }
  const today = todayKr();
  el.innerHTML = dealsState.dates.map(d => {
    // d is the Friday end-of-week date (YYYY-MM-DD)
    const rel = (d >= today) ? '<span class="pill-rel">이번주</span>' : '';
    const active = (d === dealsState.current) ? ' active' : '';
    return `<button class="news-date-pill${active}" data-date="${d}">W/E ${d}${rel}</button>`;
  }).join('');
  el.querySelectorAll('.news-date-pill').forEach(btn => {
    btn.addEventListener('click', () => loadDealsDate(btn.dataset.date));
  });
}

async function loadDealsDate(date) {
  dealsState.current = date;
  renderDealsDatePills();
  let md = dealsState.cache[date];
  if (!md) {
    try {
      const res = await fetch(`./deals/${date}.md?_=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      md = await res.text();
      dealsState.cache[date] = md;
    } catch (err) {
      document.getElementById('dealsBody').innerHTML =
        `<div class="news-empty"><h3>로딩 실패</h3><p>${err.message}</p></div>`;
      return;
    }
  }
  renderDealsContent(md);
}

function renderDealsEmpty() {
  document.getElementById('dealsBody').innerHTML = `
    <div class="news-empty">
      <div class="news-empty-icon">💼</div>
      <h3>아직 저장된 Macro/자본시장/거래동향이 없습니다</h3>
      <p>이 페이지는 매주 금요일 오후에 갱신되는 자본시장·딜 동향 요약을 보여줍니다.</p>
      <p>⏰ <strong>다음 자동 갱신</strong>: 다가오는 금요일 16:00 KST</p>
    </div>
  `;
}

// Parse weekly deal flow markdown
//   # 💼 Weekly Deal Flow — ...
//   > 데이터 기준: ...
//   ## 1. 자본시장 동향
//   ### 헤드라인 (YYYY.MM.DD)
//   - bullet
//   - bullet
//   ## 2. 주요 거래 동향
//   ### 헤드라인 (YYYY.MM.DD)
//   - bullet
//   #### Valuation (단위: 억원, FY25)         ← optional, page 6 only
//   | 항목 | 값 |
//   |---|---|
//   | 매출액 | 3,159 |
//   ...
//   ## 3. Deal Summary
//   | ... | ... |  (markdown table)
function parseDealFlow(md) {
  const out = { title: '', meta: '', sections: [], summaryTable: null };
  const lines = md.split(/\r?\n/);
  let section = null;
  let article = null;
  let tableLines = [];
  let inValuation = false;

  const closeArticle = () => {
    if (article && section) section.articles.push(article);
    article = null;
    inValuation = false;
  };

  for (const line of lines) {
    if (!out.title && /^#\s+/.test(line)) {
      out.title = line.replace(/^#\s+/, '').trim();
      continue;
    }
    if (!out.meta && /^>\s+/.test(line)) {
      out.meta = line.replace(/^>\s+/, '').trim();
      continue;
    }
    const h2 = line.match(/^##\s+(.+?)\s*$/);
    if (h2) {
      closeArticle();
      const name = h2[1].trim();
      if (/Deal\s*Summary|딜\s*요약|거래\s*요약/i.test(name)) {
        section = { name, articles: [], isSummary: true };
        tableLines = [];
      } else {
        section = { name, articles: [], isSummary: false };
      }
      out.sections.push(section);
      continue;
    }
    const h3 = line.match(/^###\s+(.+?)\s*$/);
    if (h3 && section && !section.isSummary) {
      closeArticle();
      let head = h3[1].trim();
      let date = '';
      const dm = head.match(/\(([0-9]{4}\.[0-9]{2}\.[0-9]{2})\)\s*$/);
      if (dm) {
        date = dm[1];
        head = head.replace(/\s*\([0-9]{4}\.[0-9]{2}\.[0-9]{2}\)\s*$/, '').trim();
      }
      article = { headline: head, date, bullets: [], valuationTitle: '', valuationLines: [] };
      continue;
    }
    // H4 — Valuation sub-section inside an article
    const h4 = line.match(/^####\s+(.+?)\s*$/);
    if (h4 && article) {
      if (/Valuation|밸류에이션|가치평가/i.test(h4[1])) {
        article.valuationTitle = h4[1].trim();
        inValuation = true;
      } else {
        inValuation = false;
      }
      continue;
    }
    // Collect table lines in summary section
    if (section && section.isSummary) {
      if (/^\s*\|/.test(line)) {
        tableLines.push(line);
        section.tableLines = tableLines;
      }
      continue;
    }
    // Valuation table lines
    if (inValuation && article) {
      if (/^\s*\|/.test(line)) {
        article.valuationLines.push(line);
        continue;
      }
      // Non-table, non-empty line exits valuation mode (but keeps article)
      if (line.trim() !== '') inValuation = false;
    }
    // Bullets for article
    if (article && !inValuation) {
      const bm = line.match(/^[-•]\s+(.+)$/);
      if (bm) article.bullets.push(bm[1].trim());
    }
  }
  closeArticle();
  return out;
}

// Extract { label → raw cell string } from a markdown two-column key/value table.
// Skips header + separator rows.
function parseValuationTable(lines) {
  if (!lines || lines.length < 2) return null;
  const rows = lines
    .map(l => l.trim())
    .filter(l => l.startsWith('|'))
    .map(l => l.replace(/^\||\|$/g, '').split('|').map(c => c.trim()));
  if (rows.length < 2) return null;
  // Detect separator row; data rows are after it. If no separator, drop only header.
  const sepIdx = rows.findIndex(r => r.every(c => /^:?-+:?$/.test(c)));
  const dataRows = sepIdx >= 0 ? rows.slice(sepIdx + 1) : rows.slice(1);
  const out = {};
  for (const r of dataRows) {
    if (r.length >= 2 && r[0]) out[r[0]] = (r[1] || '').trim();
  }
  return out;
}

function renderMdTable(tableLines) {
  if (!tableLines || tableLines.length < 2) return '';
  const rows = tableLines
    .map(l => l.trim())
    .filter(l => l.startsWith('|'))
    .map(l => l.replace(/^\||\|$/g, '').split('|').map(c => c.trim()));
  // Detect separator row like |---|---|
  const headerIdx = 0;
  const sepIdx = rows.findIndex(r => r.every(c => /^:?-+:?$/.test(c)));
  const header = rows[headerIdx];
  const body = sepIdx >= 0 ? rows.slice(sepIdx + 1) : rows.slice(1);
  return `
    <table class="deals-summary-table">
      <thead><tr>${header.map(h => `<th>${linkifyInline(h)}</th>`).join('')}</tr></thead>
      <tbody>
        ${body.map(r => `<tr>${r.map(c => `<td>${linkifyInline(c)}</td>`).join('')}</tr>`).join('')}
      </tbody>
    </table>
  `;
}

// Filter calendar events: US + KR + importance === 3
function _filterMacroEvents(cal) {
  if (!cal || !cal.events) return [];
  return cal.events.filter(e =>
    (e.importance || 0) === 3 &&
    (e.flagKey === 'United_States' || e.flagKey === 'South_Korea')
  );
}

function _renderMacroEventRow(e, mode) {
  const flag = FLAG_EMOJI[e.flagKey] || '';
  const indicator = (typeof INDICATOR_KR !== 'undefined' && INDICATOR_KR[e.indicator]) || e.indicator || '—';
  const period = e.period ? ` <span class="period-tag">(${e.period})</span>` : '';
  const cells = [];
  if (mode === 'review') {
    cells.push(`<span class="mc-cell mc-actual"><em>실제</em>${e.actual || '—'}</span>`);
    cells.push(`<span class="mc-cell"><em>전망</em>${e.forecast || '—'}</span>`);
    cells.push(`<span class="mc-cell"><em>이전</em>${e.previous || '—'}</span>`);
  } else {
    cells.push(`<span class="mc-cell"><em>전망</em>${e.forecast || '—'}</span>`);
    cells.push(`<span class="mc-cell"><em>이전</em>${e.previous || '—'}</span>`);
  }
  return `
    <div class="mc-row">
      <span class="mc-time">${e.time || '—'}</span>
      <span class="mc-flag">${flag}</span>
      <span class="mc-indicator">${escapeHtml(indicator)}${period}</span>
      <span class="mc-nums">${cells.join('')}</span>
    </div>
  `;
}

function _renderMacroCalendarColumn(title, events, mode) {
  if (!events || events.length === 0) {
    return `
      <div class="mc-col">
        <div class="mc-col-title">${escapeHtml(title)}</div>
        <div class="mc-empty">데이터 없음 — calendar-${mode === 'review' ? 'week' : 'next-week'}.json 갱신 필요</div>
      </div>
    `;
  }
  // group by date key
  const groups = new Map();
  events.forEach(e => {
    const dt = parseInvestingDateTime(e.datetime);
    if (!dt) return;
    const key = dateKey(dt);
    if (!groups.has(key)) groups.set(key, { date: dt, items: [] });
    groups.get(key).items.push(e);
  });
  const sortedKeys = Array.from(groups.keys()).sort();
  const daysHtml = sortedKeys.map(key => {
    const { date, items } = groups.get(key);
    const dayLabel = formatDayLabel(date);
    const weekday = KR_WEEKDAY[date.getDay()];
    return `
      <div class="mc-day">
        <div class="mc-day-head">
          <span class="mc-day-date">${dayLabel}</span>
          <span class="mc-day-weekday">${weekday}</span>
          <span class="mc-day-count">${items.length}건</span>
        </div>
        <div class="mc-day-events">${items.map(e => _renderMacroEventRow(e, mode)).join('')}</div>
      </div>
    `;
  }).join('');
  return `
    <div class="mc-col">
      <div class="mc-col-title">${escapeHtml(title)}</div>
      ${daysHtml}
    </div>
  `;
}

function renderMacroCalendarCard() {
  // DEPRECATED — replaced by renderMacroNotesCard (image+comment cards).
  // Kept for reference; no longer rendered.
  const thisWeek = _filterMacroEvents(dealsState.calThisWeek);
  const nextWeek = _filterMacroEvents(dealsState.calNextWeek);
  if (thisWeek.length === 0 && nextWeek.length === 0) return '';
  return `
    <div class="macro-cal-card">
      <div class="macro-cal-header">
        <span class="macro-cal-title">📅 주간 주요 경제지표 (★★★ · 🇺🇸 미국 · 🇰🇷 한국)</span>
      </div>
      <div class="macro-cal-grid">
        ${_renderMacroCalendarColumn('이번 주 Review', thisWeek, 'review')}
        ${_renderMacroCalendarColumn('다음 주 Preview', nextWeek, 'preview')}
      </div>
    </div>
  `;
}

// ─── Macro Notes (paste screenshots + comments, per-week localStorage) ──
function _macroNotesKey(weekDate) { return `macro-notes-${weekDate || 'default'}`; }

function _loadMacroNotes(weekDate) {
  const key = _macroNotesKey(weekDate);
  // Defensive coercion: legacy data may have stored a single card object
  // (instead of an array of cards). Always return an array.
  const toArray = (v) => {
    if (Array.isArray(v)) return v;
    if (v && typeof v === 'object' && v.id) return [v];
    return [];
  };
  // localStorage first (fresh edits)
  try {
    const raw = localStorage.getItem(key);
    if (raw) return toArray(JSON.parse(raw));
  } catch {}
  // Then user-state.json cache (deployed values, shared across browsers)
  if (_userStateCache && _userStateCache[key] != null) {
    return toArray(_userStateCache[key]);
  }
  return [];
}

function _saveMacroNotes(weekDate, notes) {
  const key = _macroNotesKey(weekDate);
  try {
    localStorage.setItem(key, JSON.stringify(notes));
  } catch (e) {
    alert('저장 실패 — 브라우저 저장 용량 초과 가능성. 오래된 카드를 삭제하세요.');
    return false;
  }
  // Also persist server-side so deploy carries them to Cloudflare
  saveUserState(key, notes);
  return true;
}

function _macroNoteUid() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function _formatMacroNoteDate(ts) {
  if (!ts) return '';
  try {
    return new Date(ts).toLocaleString('ko-KR', {
      month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
    });
  } catch { return ''; }
}

function _compressMacroImage(dataUrl) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      const MAX_W = 1400;
      const scale = Math.min(1, MAX_W / img.width);
      const w = Math.round(img.width * scale);
      const h = Math.round(img.height * scale);
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, w, h);
      ctx.drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL('image/jpeg', 0.85));
    };
    img.onerror = reject;
    img.src = dataUrl;
  });
}

function renderMacroNotesCard(weekDate) {
  const notes = _loadMacroNotes(weekDate);
  const empty = `
    <div class="macro-notes-empty">
      <div class="empty-icon">📋</div>
      <p class="empty-title">아직 저장된 카드가 없습니다</p>
      <p class="empty-hint">
        화면을 캡처하여 클립보드에 복사한 뒤 <kbd>Ctrl+V</kbd> 를 누르세요.<br>
        또는 위의 <strong>+ 새 카드</strong> 버튼으로 빈 카드를 추가할 수 있습니다.
      </p>
    </div>`;
  const cards = notes.map(n => `
    <div class="macro-note-card" data-id="${n.id}">
      ${n.image
        ? `<div class="macro-note-imgwrap"><img src="${n.image}" alt="" class="macro-note-img" loading="lazy"></div>`
        : `<div class="macro-note-imgwrap macro-note-noimage">이미지 없음 — Ctrl+V로 붙여넣기</div>`
      }
      <input type="text" class="macro-note-title" placeholder="제목 (선택)" value="${escapeHtml(n.title || '')}" maxlength="120">
      <textarea class="macro-note-comment" placeholder="코멘트를 작성하세요…" rows="3">${escapeHtml(n.comment || '')}</textarea>
      <div class="macro-note-actions">
        <span class="macro-note-date">${_formatMacroNoteDate(n.createdAt)}</span>
        <button class="macro-note-delete" data-action="delete" type="button">🗑 삭제</button>
      </div>
    </div>
  `).join('');
  return `
    <div class="macro-notes-section" data-week="${escapeHtml(weekDate || 'default')}">
      <div class="macro-notes-toolbar">
        <button class="macro-add-btn" data-action="add" type="button">+ 새 카드</button>
        <span class="macro-paste-hint">💡 스크린샷 복사 후 <kbd>Ctrl+V</kbd> 로 이 페이지에 붙여넣기 — 이번 주 저장소에 보관됩니다.</span>
      </div>
      <div class="macro-notes-grid">
        ${notes.length === 0 ? empty : cards}
      </div>
    </div>
  `;
}

function _rerenderMacroNotes(sectionEl, weekDate) {
  const tmp = document.createElement('div');
  tmp.innerHTML = renderMacroNotesCard(weekDate);
  const next = tmp.firstElementChild;
  if (next && sectionEl.parentNode) {
    sectionEl.replaceWith(next);
    _wireMacroNotesEvents(next, weekDate);
    return next;
  }
  return sectionEl;
}

async function _macroNotesAdd(sectionEl, weekDate, rawImage) {
  let image = '';
  if (rawImage) {
    try { image = await _compressMacroImage(rawImage); }
    catch { image = rawImage; }
  }
  const notes = _loadMacroNotes(weekDate);
  const note = { id: _macroNoteUid(), title: '', comment: '', image, createdAt: Date.now() };
  notes.unshift(note);
  if (!_saveMacroNotes(weekDate, notes)) return;
  _rerenderMacroNotes(sectionEl, weekDate);
  // Focus newly added card
  setTimeout(() => {
    const el = document.querySelector(`.macro-note-card[data-id="${note.id}"]`);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'center' });
      const ta = el.querySelector('.macro-note-comment');
      ta && ta.focus();
    }
  }, 60);
}

function _wireMacroNotesEvents(sectionEl, weekDate) {
  if (!sectionEl) return;

  // Auto-resize every paste-card comment textarea to fit its content.
  const autoResize = (ta) => {
    if (!ta) return;
    ta.style.height = 'auto';
    ta.style.height = Math.min(ta.scrollHeight + 2, 600) + 'px';
  };
  sectionEl.querySelectorAll('.macro-note-comment').forEach(ta => {
    requestAnimationFrame(() => autoResize(ta));
  });

  sectionEl.addEventListener('click', (e) => {
    const action = e.target.dataset && e.target.dataset.action;
    if (action === 'add') {
      _macroNotesAdd(sectionEl, weekDate, '');
    } else if (action === 'delete') {
      const card = e.target.closest('.macro-note-card');
      if (!card) return;
      if (!confirm('이 카드를 삭제할까요?')) return;
      const notes = _loadMacroNotes(weekDate).filter(n => n.id !== card.dataset.id);
      _saveMacroNotes(weekDate, notes);
      _rerenderMacroNotes(sectionEl, weekDate);
    }
  });

  sectionEl.addEventListener('input', (e) => {
    const card = e.target.closest('.macro-note-card');
    if (!card) return;
    const id = card.dataset.id;
    const notes = _loadMacroNotes(weekDate);
    const i = notes.findIndex(n => n.id === id);
    if (i < 0) return;
    if (e.target.classList.contains('macro-note-title')) {
      notes[i].title = e.target.value;
      _saveMacroNotes(weekDate, notes);
    } else if (e.target.classList.contains('macro-note-comment')) {
      notes[i].comment = e.target.value;
      _saveMacroNotes(weekDate, notes);
      // Grow textarea to fit new content
      e.target.style.height = 'auto';
      e.target.style.height = Math.min(e.target.scrollHeight + 2, 600) + 'px';
    }
  });
}

// Global paste handler — once installed, active whenever deals view is showing
// a macro-notes-section.
let _macroPasteAttached = false;
function _ensureMacroPasteHandler() {
  if (_macroPasteAttached) return;
  _macroPasteAttached = true;
  document.addEventListener('paste', (e) => {
    const dealsView = document.getElementById('view-deals');
    if (!dealsView || dealsView.hidden) return;
    const sectionEl = dealsView.querySelector('.macro-notes-section');
    if (!sectionEl) return;
    const items = e.clipboardData && e.clipboardData.items;
    if (!items || items.length === 0) return;
    let imgItem = null;
    for (const it of items) {
      if (it.type && it.type.startsWith('image/')) { imgItem = it; break; }
    }
    if (!imgItem) return;
    e.preventDefault();
    const file = imgItem.getAsFile();
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const weekDate = sectionEl.dataset.week || 'default';
      _macroNotesAdd(sectionEl, weekDate, reader.result);
    };
    reader.readAsDataURL(file);
  });
}

function _isMacroSection(name) {
  return /macro|매크로/i.test(name || '');
}

function renderDealsContent(md) {
  const body = document.getElementById('dealsBody');
  if (!body) return;
  _valuationCounter = 0; // reset per-render so card ids start at val-0
  const p = parseDealFlow(md);
  if (!p.title || p.sections.length === 0) {
    body.innerHTML = `<div class="news-empty"><h3>파싱 실패</h3><p>이 파일에서 섹션을 찾을 수 없습니다.</p></div>`;
    return;
  }
  // localStorage key needs a stable per-week scope
  const weekDate = dealsState.current
    || (p.title.match(/(\d{4}-\d{2}-\d{2})/) || [])[1]
    || 'unknown';

  const header = `
    <div class="market-brief-header">
      <h2 class="market-brief-title">${escapeHtml(p.title)}</h2>
      ${p.meta ? `<div class="market-brief-meta">${escapeHtml(p.meta)}</div>` : ''}
    </div>
  `;

  const commentStorageKey = `macro-comment-${weekDate}`;
  const savedComment = (() => {
    try { return localStorage.getItem(commentStorageKey) || ''; }
    catch (e) { return ''; }
  })();

  const sectionsHtml = p.sections.map(s => {
    if (s.isSummary) {
      const tbl = renderMdTable(s.tableLines);
      if (!tbl) return '';
      return `
        <div class="news-sector-block">
          <div class="news-sector-header">
            <span class="news-sector-title">${escapeHtml(s.name)}</span>
          </div>
          <div class="deals-summary-wrap">${tbl}</div>
        </div>
      `;
    }
    const articles = s.articles.length > 0
      ? s.articles.map(a => renderDealArticle(a, weekDate)).join('')
      : '<div class="news-card" style="color:var(--text-muted);font-style:italic;">이번 주 해당 카테고리 항목 없음</div>';
    const isMacro = _isMacroSection(s.name);
    const macroCalendar = isMacro ? renderMacroNotesCard(weekDate) : '';
    // Note: 매크로 코멘트 textarea was removed per user request — image cards
    // already carry per-card comments, and the dashboard Section 3 has its
    // own macro comment box for week-level notes.
    return `
      <div class="news-sector-block">
        <div class="news-sector-header">
          <span class="news-sector-title">${escapeHtml(s.name)}</span>
          <span class="news-sector-count">${s.articles.length}건</span>
        </div>
        ${macroCalendar}
        <div class="news-articles">${articles}</div>
      </div>
    `;
  }).join('');

  body.innerHTML = header + sectionsHtml;

  // Initial compute pass for every valuation card just rendered
  body.querySelectorAll('.valuation-card[id]').forEach(card => {
    if (window.computeValuation) window.computeValuation(card.id);
  });

  // Wire up macro notes (paste images + comments)
  const macroNotesSection = body.querySelector('.macro-notes-section');
  if (macroNotesSection) {
    const weekKey = macroNotesSection.dataset.week || 'default';
    _wireMacroNotesEvents(macroNotesSection, weekKey);
    _ensureMacroPasteHandler();
  }

  // Wire up macro comment — explicit save via FIX button (no auto-save)
  wireFixSaveTextarea({
    textarea: body.querySelector('#macroCommentArea'),
    fixBtn:   body.querySelector('#macroCommentFix'),
    statusEl: body.querySelector('#macroCommentStatus'),
  });
}

// ─── Reusable: textarea + FIX button + localStorage save ─────────────
// Reads textarea.dataset.storageKey; saves text + timestamp on FIX click.
// Status spans show "● 저장되지 않은 변경" (dirty) / "✓ MM-DD HH:MM 저장됨" (saved).
// Loads previously saved value into the textarea if it's empty.
function wireFixSaveTextarea({ textarea, fixBtn, statusEl }) {
  if (!textarea) return;
  const storageKey = textarea.dataset.storageKey;
  if (!storageKey) {
    console.warn('wireFixSaveTextarea: missing data-storage-key on', textarea);
    return;
  }

  // Hydrate from localStorage first, then user-state cache (deployed file).
  if (textarea.value === '') {
    try {
      const saved = localStorage.getItem(storageKey);
      if (saved) {
        textarea.value = saved;
      } else if (_userStateCache && typeof _userStateCache[storageKey] === 'string') {
        textarea.value = _userStateCache[storageKey];
      }
    } catch (e) { /* ignore */ }
  }

  // Auto-resize the textarea height to fit content (capped at 800px).
  // Triggered on hydrate and every input — so the box grows as the user types
  // instead of forcing them to scroll within a fixed-height box.
  const resizeToFit = () => {
    textarea.style.height = 'auto';
    const target = Math.min(textarea.scrollHeight + 2, 800);
    textarea.style.height = target + 'px';
  };
  // Initial pass — wait one frame so the browser has laid the textarea out.
  requestAnimationFrame(resizeToFit);
  textarea.addEventListener('input', resizeToFit);

  let savedValue = textarea.value;
  const setStatus = (text, cls) => {
    if (!statusEl) return;
    statusEl.textContent = text;
    statusEl.classList.remove('dirty', 'saved');
    if (cls) statusEl.classList.add(cls);
  };
  const refresh = () => {
    const dirty = textarea.value !== savedValue;
    if (fixBtn) fixBtn.disabled = !dirty;
    if (dirty) setStatus('● 저장되지 않은 변경', 'dirty');
  };
  if (savedValue) {
    let savedAt = localStorage.getItem(`${storageKey}-time`);
    if (!savedAt && _userStateCache) savedAt = _userStateCache[`${storageKey}-time`];
    if (savedAt) setStatus(`✓ ${savedAt} 저장됨`, 'saved');
  }

  textarea.addEventListener('input', refresh);
  textarea.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      if (fixBtn && !fixBtn.disabled) fixBtn.click();
    }
  });

  if (fixBtn) {
    fixBtn.addEventListener('click', () => {
      try {
        localStorage.setItem(storageKey, textarea.value);
        savedValue = textarea.value;
        const t = new Date();
        const stamp = `${String(t.getMonth() + 1).padStart(2, '0')}-${String(t.getDate()).padStart(2, '0')} ${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}`;
        localStorage.setItem(`${storageKey}-time`, stamp);
        // Mirror to user-state.json so deploy carries the comment
        saveUserState(storageKey, textarea.value);
        saveUserState(`${storageKey}-time`, stamp);
        setStatus(`✓ ${stamp} 저장됨`, 'saved');
        fixBtn.disabled = true;
      } catch (e) {
        setStatus('저장 실패 (localStorage)', 'dirty');
      }
    });
  }
}

function setupDashboardMacroComment() {
  wireFixSaveTextarea({
    textarea: document.getElementById('dashboardMacroCommentArea'),
    fixBtn:   document.getElementById('dashboardMacroCommentFix'),
    statusEl: document.getElementById('dashboardMacroCommentStatus'),
  });
}

// Counter for per-render valuation card ids — reset every renderDealsContent call
let _valuationCounter = 0;

function renderDealArticle(a, weekDate) {
  const dateBadge = a.date
    ? `<span class="deals-date-badge">${escapeHtml(a.date)}</span>`
    : '';
  const bulletsHtml = a.bullets.length > 0
    ? `<ul class="deals-bullets">${a.bullets.map(b => `<li>${linkifyInline(b)}</li>`).join('')}</ul>`
    : '';
  let valuationHtml = '';
  if (a.valuationLines && a.valuationLines.length > 0) {
    const data = parseValuationTable(a.valuationLines);
    if (data) {
      const cardId = `val-${_valuationCounter++}`;
      valuationHtml = renderValuationCard(cardId, weekDate || 'unknown', a.headline, a.valuationTitle, data);
    }
  }
  return `
    <div class="news-card deals-card">
      <div class="news-card-head">
        ${dateBadge}
        <h3 class="news-headline">${linkifyInline(a.headline)}</h3>
      </div>
      ${bulletsHtml}
      ${valuationHtml}
    </div>
  `;
}

// ─── Valuation card (Page 6 only) ────────────────────────
const VAL_PNL_FIELDS = [
  { key: '매출액',          ph: '예: 3,159' },
  { key: '영업이익',        ph: '예: 172' },
  { key: '감가상각비(D&A)', ph: '+영업이익 = EBITDA' },
  { key: 'EBITDA',          ph: '비워두면 자동 계산' },
  { key: '당기순이익',      ph: '예: 11' },
];
const VAL_DEBT_FIELDS = [
  { key: '단기차입금' },
  { key: '유동성장기차입금' },
  { key: '유동리스부채' },
  { key: '장기차입금' },
  { key: '리스부채' },
];
const VAL_CASH_FIELDS = [
  { key: '현금및현금성자산' },
  { key: '단기금융상품' },
];
const VAL_DEAL_FIELDS = [
  { key: 'Deal Value',      ph: '거래대금' },
  { key: '% Stake',         ph: '0~100' },
  { key: '시가총액',        ph: '상장사만' },
];

// ─── Valuation persistence (localStorage) ────────────────
function simpleHash(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) - h) + s.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h).toString(36);
}

function valuationStorageKey(weekDate, headline) {
  return `rp::valuation::${weekDate}::${simpleHash(headline)}`;
}

// ─── Server-side user state (user-state.json) ────────────────────
// Holds anything users have explicitly saved: valuation Fix values, macro
// image-card notes, macro comments (deals + dashboard), capmkt comments.
// Loaded once at init from /user-state.json, updated via POST /save-state.
// On Cloudflare static site the POST 404s silently — localStorage is the
// fallback persistence for solo browser use.
let _userStateCache = null;

async function loadUserState() {
  try {
    const res = await fetch('/user-state.json?_=' + Date.now(), { cache: 'no-store' });
    if (res.ok) {
      const data = await res.json();
      _userStateCache = data.entries || {};
    } else {
      _userStateCache = {};
    }
  } catch (e) {
    _userStateCache = {};
  }
  return _userStateCache;
}

// One-shot migration: push any localStorage entries the server doesn't have
// yet. Lets pre-existing localStorage saves (from before the /save-state
// endpoint existed) propagate to user-state.json → deploy → other browsers.
function migrateLocalStorageToUserState() {
  if (!_userStateCache) return;
  const prefixes = [
    'rp::valuation::',
    'macro-notes-',
    'macro-comment-',
    'dashboard-macro-comment',
    'capmkt-comment-',
    'ipo-mcap-',
  ];

  // Treat these server values as "empty / missing" so localStorage content
  // can supersede them. (Previously, an empty array on the server caused
  // localStorage cards to be silently skipped, leaving them un-deployed.)
  const isEmpty = (v) => (
    v === undefined || v === null ||
    (Array.isArray(v) && v.length === 0) ||
    (typeof v === 'string' && v === '')
  );

  let pushed = 0;
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (!key) continue;
    if (!prefixes.some((p) => key.startsWith(p))) continue;

    let raw;
    try { raw = localStorage.getItem(key); } catch { continue; }
    if (raw === null || raw === '') continue;

    let value = raw;
    try {
      const parsed = JSON.parse(raw);
      if (parsed !== null && parsed !== undefined) value = parsed;
    } catch { /* keep as string */ }

    // Only push if local has content AND server is empty/missing.
    if (isEmpty(value)) continue;
    if (!isEmpty(_userStateCache[key])) continue; // server already has substantive content

    saveUserState(key, value);
    pushed++;
  }
  if (pushed > 0) console.log(`[user-state] migrated ${pushed} localStorage entries → server`);
}

// Best-effort POST. Updates cache optimistically (so re-renders see it
// before the server roundtrip completes).
function saveUserState(key, value) {
  if (_userStateCache) {
    if (value === null || value === undefined) delete _userStateCache[key];
    else _userStateCache[key] = value;
  }
  try {
    fetch('/save-state', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, value }),
    }).catch(() => {}); // silent — Cloudflare or offline
  } catch {}
}

function loadSavedValuation(weekDate, headline) {
  const key = valuationStorageKey(weekDate, headline);
  try {
    const raw = localStorage.getItem(key);
    if (raw) return JSON.parse(raw);
  } catch {}
  if (_userStateCache && _userStateCache[key]) {
    return _userStateCache[key];
  }
  return null;
}

function renderValuationCard(cardId, weekDate, headline, title, data) {
  data = data || {};
  const saved = loadSavedValuation(weekDate, headline);
  const merged = saved ? { ...data, ...saved.values } : data;
  const dealType = merged['Deal Type'] || '';
  const renderInput = (f) => {
    const v = merged[f.key] !== undefined ? merged[f.key] : '';
    const ph = f.ph ? ` placeholder="${escapeHtml(f.ph)}"` : '';
    return `<tr>
      <th>${escapeHtml(f.key)}</th>
      <td><input type="text" inputmode="decimal" data-key="${escapeHtml(f.key)}" value="${escapeHtml(v)}"${ph} oninput="onValuationInput('${cardId}')" /></td>
    </tr>`;
  };
  const titleStr = title || 'Valuation';
  const savedBadge = saved
    ? `<span class="valuation-saved-badge" title="${escapeHtml(saved.savedAt)} 저장">📌 저장됨</span>`
    : '';
  return `
    <div class="valuation-card" id="${cardId}" data-week="${escapeHtml(weekDate)}" data-headline="${escapeHtml(headline)}">
      <div class="valuation-head">
        <span class="valuation-title">💹 ${escapeHtml(titleStr)}</span>
        ${dealType ? `<span class="valuation-dealtype">${escapeHtml(dealType)}</span>` : ''}
        ${savedBadge}
      </div>
      <div class="valuation-grid">

        <div class="val-col">
          <div class="val-col-title">손익</div>
          <table class="val-input-table">
            <tbody>${VAL_PNL_FIELDS.map(renderInput).join('')}</tbody>
          </table>
        </div>

        <div class="val-col">
          <div class="val-col-title">Net Debt 항목</div>
          <table class="val-input-table">
            <tbody>
              ${VAL_DEBT_FIELDS.map(renderInput).join('')}
              <tr class="val-subtotal"><th>IBD 총계</th><td data-out="IBD">—</td></tr>
              ${VAL_CASH_FIELDS.map(renderInput).join('')}
              <tr class="val-subtotal"><th>현금성 총계</th><td data-out="Cash">—</td></tr>
              <tr class="val-subtotal val-emphasis"><th>Net Debt</th><td data-out="NetDebt">—</td></tr>
            </tbody>
          </table>
        </div>

        <div class="val-col">
          <div class="val-col-title">Deal · Multiples</div>
          <table class="val-input-table">
            <tbody>
              ${VAL_DEAL_FIELDS.map(renderInput).join('')}
              <tr class="val-subtotal"><th>Equity Value</th><td data-out="EquityValue">—</td></tr>
              <tr class="val-subtotal val-emphasis"><th>EV</th><td data-out="EV">—</td></tr>
              <tr class="val-subtotal"><th>EBITDA (계산)</th><td data-out="EBITDA">—</td></tr>
              <tr class="val-multiple"><th>EV / EBITDA</th><td data-out="EV_EBITDA">—</td></tr>
              <tr class="val-multiple"><th>EV / 매출</th><td data-out="EV_Sales">—</td></tr>
              <tr class="val-multiple"><th>PER</th><td data-out="PER">—</td></tr>
              <tr class="val-multiple"><th>Premium vs 시총</th><td data-out="Premium">—</td></tr>
            </tbody>
          </table>
        </div>

      </div>
      <div class="valuation-foot">
        <div class="valuation-actions">
          <button type="button" class="val-action-btn val-action-dart" onclick="autoFillValuationFromDart('${cardId}')" title="DART OpenAPI로 P&L/Net Debt 항목 자동 채우기 (corp_code 입력 필요)">📥 DART 자동 채우기</button>
          <button type="button" class="val-action-btn val-action-fix" onclick="saveValuationByCard('${cardId}')" title="현재 입력값을 브라우저에 영구 저장">📌 Fix (저장)</button>
          <button type="button" class="val-action-btn val-action-reset" onclick="resetValuationByCard('${cardId}')" title="저장값을 삭제하고 MD 기본값으로 되돌림">↺ 초기화</button>
        </div>
        <span class="valuation-status" id="${cardId}-status">${saved ? `📌 ${escapeHtml(saved.savedAt)} 자동 저장됨` : '단위: 억원 · 입력 즉시 자동 저장 (이 브라우저)'}</span>
      </div>
    </div>
  `;
}

// Debounced auto-save on input: every keystroke triggers a delayed save so
// users never lose values to a forgotten Fix click. The Fix button remains as
// an explicit "save now" affordance (also produces the timestamp badge).
const _valuationSaveTimers = new Map();
window.onValuationInput = function (cardId) {
  // 1. Live recompute of derived cells (EBITDA, EV, multiples, etc.)
  if (window.computeValuation) window.computeValuation(cardId);
  // 2. Debounced persist to localStorage (400 ms idle)
  if (_valuationSaveTimers.has(cardId)) {
    clearTimeout(_valuationSaveTimers.get(cardId));
  }
  _valuationSaveTimers.set(cardId, setTimeout(() => {
    _valuationSaveTimers.delete(cardId);
    _autoSaveValuation(cardId);
  }, 400));
};

function _autoSaveValuation(cardId) {
  const card = document.getElementById(cardId);
  if (!card) return;
  const weekDate = card.dataset.week;
  const headline = card.dataset.headline;
  if (!weekDate || !headline) return;
  const values = {};
  card.querySelectorAll('input[data-key]').forEach(el => {
    const k = el.dataset.key;
    const v = el.value.trim();
    if (v !== '') values[k] = v;
  });
  const savedAt = new Date().toLocaleString('ko-KR', { hour12: false });
  const payload = { values, savedAt, weekDate, headline };
  const key = valuationStorageKey(weekDate, headline);
  try {
    localStorage.setItem(key, JSON.stringify(payload));
  } catch (e) {
    console.warn('valuation autosave failed', e);
    const status = document.getElementById(`${cardId}-status`);
    if (status) status.textContent = '저장 실패 (localStorage)';
    return;
  }
  // Best-effort server-side persist (writes valuations.json — survives deploy)
  saveUserState(key, payload);
  const status = document.getElementById(`${cardId}-status`);
  if (status) status.textContent = `✓ ${savedAt} 자동 저장됨`;
  let badge = card.querySelector('.valuation-saved-badge');
  if (!badge) {
    badge = document.createElement('span');
    badge.className = 'valuation-saved-badge';
    card.querySelector('.valuation-head').appendChild(badge);
  }
  badge.textContent = '📌 저장됨';
  badge.title = `${savedAt} 저장`;
}

// Window-exposed handlers for inline onclick
// ─── DART OpenAPI auto-fill ─────────────────────────────────────
// Fetches financials via serve.ps1 backend (/api/dart-valuation?corp_code=…)
// and populates P&L + Debt + Cash inputs on the valuation card.
// Maps DART fields → Korean input labels used in VAL_PNL_FIELDS etc.
window.autoFillValuationFromDart = async function (cardId) {
  const card = document.getElementById(cardId);
  if (!card) return;
  if (IS_STATIC) {
    alert('DART 자동 채우기는 로컬 서버(localhost:8000)에서만 동작합니다.\nCloudflare 배포 페이지에서는 사용 불가.');
    return;
  }

  const corpCode = (prompt('회사의 DART corp_code (8자리)를 입력하세요.\n예) 두나무=01310241, NAVER=00266961, 삼성전자=00126380', '') || '').trim();
  if (!corpCode) return;
  if (!/^\d{8}$/.test(corpCode)) {
    alert('corp_code는 8자리 숫자여야 합니다.');
    return;
  }
  const useLtm = confirm('LTM (최신분기 누적) 기준으로 가져올까요?\n- 확인: LTM = FY + 최신 Q1 - 직전 Q1\n- 취소: 가장 최근 사업보고서 (FY) 만 사용');

  const status = document.getElementById(`${cardId}-status`);
  if (status) status.textContent = '⏳ DART에서 데이터를 가져오는 중…';

  try {
    const url = `/api/dart-valuation?corp_code=${corpCode}` + (useLtm ? '&ltm=1' : '');
    const res = await fetch(url, { cache: 'no-store' });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ error: `HTTP ${res.status}` }));
      throw new Error(err.error || `HTTP ${res.status}`);
    }
    const data = await res.json();

    // Map DART JSON → input keys (Korean labels used in VAL_PNL_FIELDS etc.)
    const fieldMap = {
      // P&L
      '매출액':           data.pnl?.revenue,
      '영업이익':         data.pnl?.operating_income,
      '당기순이익':       data.pnl?.net_income,
      // (감가상각비 / EBITDA: not auto-filled — left for manual / Excel input)
      // Debt
      '단기차입금':       data.debt?.st_borrowings,
      '유동성장기차입금': data.debt?.current_lt_borrowings,
      '유동리스부채':     data.debt?.current_lease,
      '장기차입금':       data.debt?.lt_borrowings,
      '리스부채':         data.debt?.nc_lease,
      // Cash
      '현금및현금성자산': data.cash?.cash_and_equivalents,
      '단기금융상품':     data.cash?.st_financial_invest,
    };

    let filled = 0;
    Object.entries(fieldMap).forEach(([k, v]) => {
      if (v == null) return;
      const el = card.querySelector(`input[data-key="${k}"]`);
      if (!el) return;
      el.value = Number(v).toLocaleString('en-US');
      filled++;
    });

    // Recompute derived (EBITDA, EV, multiples) + auto-save
    if (window.computeValuation) window.computeValuation(cardId);
    _autoSaveValuation(cardId);

    if (status) {
      status.textContent = `✓ DART ${data.fiscal_period} → ${filled}개 항목 채움 (단위: 억원)`;
    }
  } catch (err) {
    if (status) status.textContent = `❌ DART fetch 실패: ${err.message}`;
    alert(`DART fetch 실패: ${err.message}`);
  }
};

window.saveValuationByCard = function (cardId) {
  const card = document.getElementById(cardId);
  if (!card) return;
  const weekDate = card.dataset.week;
  const headline = card.dataset.headline;
  const inputs = card.querySelectorAll('input[data-key]');
  const values = {};
  inputs.forEach(el => {
    const k = el.dataset.key;
    const v = el.value.trim();
    if (v !== '') values[k] = v;
  });
  const savedAt = new Date().toLocaleString('ko-KR', { hour12: false });
  const payload = { values, savedAt, weekDate, headline };
  const key = valuationStorageKey(weekDate, headline);
  localStorage.setItem(key, JSON.stringify(payload));
  saveUserState(key, payload);
  // Update status + badge in place
  const status = document.getElementById(`${cardId}-status`);
  if (status) status.textContent = `📌 ${savedAt} 저장됨`;
  let badge = card.querySelector('.valuation-saved-badge');
  if (!badge) {
    badge = document.createElement('span');
    badge.className = 'valuation-saved-badge';
    card.querySelector('.valuation-head').appendChild(badge);
  }
  badge.textContent = '📌 저장됨';
  badge.title = `${savedAt} 저장`;
};

window.resetValuationByCard = function (cardId) {
  const card = document.getElementById(cardId);
  if (!card) return;
  const weekDate = card.dataset.week;
  const headline = card.dataset.headline;
  if (!confirm('이 거래의 저장된 입력값을 모두 삭제하고 MD 기본값으로 되돌립니다. 계속할까요?')) return;
  const key = valuationStorageKey(weekDate, headline);
  localStorage.removeItem(key);
  saveUserState(key, null);
  // Re-render the whole deals view so MD defaults are restored
  if (dealsState.current && dealsState.cache[dealsState.current]) {
    renderDealsContent(dealsState.cache[dealsState.current]);
  }
};

// Number parser tolerates commas, parentheses (negative), and units like 억원
function parseValNum(s) {
  if (s === null || s === undefined) return null;
  const t = String(s).replace(/[,\s억원원KRW]/g, '').trim();
  if (t === '' || t === '-') return null;
  let neg = false;
  let body = t;
  if (body.startsWith('(') && body.endsWith(')')) { neg = true; body = body.slice(1, -1); }
  if (body.startsWith('-')) { neg = true; body = body.slice(1); }
  const n = Number(body);
  if (!isFinite(n)) return null;
  return neg ? -n : n;
}

function fmtVal(n, digits = 0) {
  if (n === null || !isFinite(n)) return '—';
  return n.toLocaleString('ko-KR', { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

function fmtMultiple(n) {
  if (n === null || !isFinite(n)) return '—';
  return n.toFixed(1) + 'x';
}

function fmtPercent(n) {
  if (n === null || !isFinite(n)) return '—';
  return (n >= 0 ? '+' : '') + n.toFixed(1) + '%';
}

// Live recompute — exposed on window for inline oninput handlers
window.computeValuation = function (cardId) {
  const card = document.getElementById(cardId);
  if (!card) return;
  const read = (key) => parseValNum(card.querySelector(`[data-key="${key}"]`)?.value);
  const setOut = (k, html) => {
    const el = card.querySelector(`[data-out="${k}"]`);
    if (el) el.textContent = html;
  };

  const revenue   = read('매출액');
  const opIncome  = read('영업이익');
  const da        = read('감가상각비(D&A)');
  const ebitdaRaw = read('EBITDA');
  const netIncome = read('당기순이익');

  // EBITDA: direct input first, else 영업이익 + D&A
  const ebitda = ebitdaRaw !== null
    ? ebitdaRaw
    : (opIncome !== null && da !== null ? opIncome + da : null);

  const debt = ['단기차입금', '유동성장기차입금', '유동리스부채', '장기차입금', '리스부채']
    .map(read).filter(v => v !== null);
  const ibd = debt.length ? debt.reduce((a, b) => a + b, 0) : null;

  const cash = ['현금및현금성자산', '단기금융상품']
    .map(read).filter(v => v !== null);
  const cashTotal = cash.length ? cash.reduce((a, b) => a + b, 0) : null;

  const netDebt = (ibd !== null || cashTotal !== null)
    ? (ibd || 0) - (cashTotal || 0)
    : null;

  const dealValue = read('Deal Value');
  const stake     = read('% Stake');
  const mktCap    = read('시가총액');

  // Equity Value:
  //   1순위: Deal Value / Stake (control 거래 implied)
  //   2순위: 시가총액 (소수지분·listed 케이스 fallback)
  const equity = (dealValue !== null && stake !== null && stake > 0)
    ? dealValue / (stake / 100)
    : (mktCap !== null ? mktCap : null);

  const ev = (equity !== null && netDebt !== null) ? equity + netDebt
           : (equity !== null ? equity : null);

  const evEbitda = (ev !== null && ebitda && ebitda !== 0) ? ev / ebitda : null;
  const evSales  = (ev !== null && revenue && revenue !== 0) ? ev / revenue : null;
  const per      = (equity !== null && netIncome && netIncome !== 0) ? equity / netIncome : null;
  const premium  = (equity !== null && mktCap && mktCap !== 0) ? (equity / mktCap - 1) * 100 : null;

  setOut('IBD',        fmtVal(ibd));
  setOut('Cash',       fmtVal(cashTotal));
  setOut('NetDebt',    fmtVal(netDebt));
  setOut('EquityValue',fmtVal(equity));
  setOut('EV',         fmtVal(ev));
  setOut('EBITDA',     fmtVal(ebitda));
  setOut('EV_EBITDA',  fmtMultiple(evEbitda));
  setOut('EV_Sales',   fmtMultiple(evSales));
  setOut('PER',        fmtMultiple(per));
  setOut('Premium',    fmtPercent(premium));
};

// ─── View Router ──────────────────────────────────────────
function showView(name) {
  const valid = ['home', 'weekly', 'news', 'market', 'deals', 'semicon', 'peer'];
  if (!valid.includes(name)) name = 'home';

  document.querySelectorAll('.view').forEach(v => {
    v.hidden = v.id !== `view-${name}`;
  });
  document.querySelectorAll('.sidebar-item[data-view]').forEach(a => {
    a.classList.toggle('active', a.dataset.view === name);
  });

  if (name === 'weekly' && !weeklyCache) loadWeeklyCalendar();
  if (name === 'news') loadNewsIndex();
  if (name === 'market') loadMarketIndex();
  if (name === 'deals') loadDealsIndex();
  if (name === 'semicon') loadSemicon();
  if (name === 'peer') loadPeer();
  window.scrollTo({ top: 0 });
}

function setupRouter() {
  window.addEventListener('hashchange', () => {
    showView(location.hash.replace('#', '') || 'home');
  });
  showView(location.hash.replace('#', '') || 'home');
}

// ─── Static mode UI adjustments ──────────────────────────
if (IS_STATIC) {
  // Hide refresh button (no backend to call /refresh)
  const rb = document.getElementById('refreshBtn');
  if (rb) rb.style.display = 'none';

  // Replace "수동 갱신 모드" badge with view-only indicator
  const badge = document.querySelector('.manual-mode-badge');
  if (badge) {
    badge.innerHTML = '<span class="dot" style="background:#22c55e"></span> View-only · 공개 배포본';
    badge.title = 'Cloudflare Pages에 배포된 공개 뷰. 데이터는 마지막 git push 시점 기준.';
  }

  // Hide AI chat widget (uses owner's API key — keep private)
  const chat = document.getElementById('chatWidget');
  if (chat) chat.style.display = 'none';
}

// ─── Semiconductor 수출입 View ────────────────────────────
let tradeCache = null;
let semiconCharts = { ssd: null, nand: null, dram: null };
let semiconRange = '5y';
let semiconMetric = 'value';  // 'value' | 'weight' | 'unitPrice'

const SEMICON_METRIC_LABELS = {
  value:     { label: '수출액',    unit: '$mn',  field: 'value',     digits: 0 },
  weight:    { label: '수출중량',  unit: 'kg',   field: 'weight',    digits: 0 },
  unitPrice: { label: '단가',      unit: '$/kg', field: 'unitPrice', digits: 1 },
};

function metricCfg() { return SEMICON_METRIC_LABELS[semiconMetric] || SEMICON_METRIC_LABELS.value; }

async function loadSemicon() {
  if (!tradeCache) {
    try {
      const res = await fetch(`${TRADE_URL}?_=${Date.now()}`, { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      tradeCache = await res.json();
    } catch (err) {
      console.warn('Trade data load failed:', err);
      document.getElementById('semiconBody').innerHTML =
        `<div class="news-empty"><h3>trade.json 로딩 실패</h3><p>${err.message}</p></div>`;
      return;
    }
  }
  const ts = document.getElementById('semiconUpdated');
  if (ts && tradeCache.updatedKr) ts.textContent = `데이터 기준: ${tradeCache.updatedKr.slice(0, 10)}`;
  renderSemicon();
}

function filterByRange(series, range) {
  if (!series || series.length === 0) return [];
  if (range === 'all') return series;
  const monthsBack = range === '3y' ? 36 : 60;
  const latestMonth = series[series.length - 1].month;
  const [latestY, latestM] = latestMonth.split('-').map(Number);
  // total months from year 0 helps comparison
  const latestIdx = latestY * 12 + latestM;
  const cutoff = latestIdx - monthsBack + 1;
  return series.filter(d => {
    const [y, m] = d.month.split('-').map(Number);
    return (y * 12 + m) >= cutoff;
  });
}

function computeStats(series) {
  const cfg = metricCfg();
  const f = cfg.field;
  if (!series || series.length < 13) return null;
  const latest = series[series.length - 1];
  const prev1  = series[series.length - 2];
  const prev12 = series[series.length - 13];
  const lv = latest?.[f];
  const p1 = prev1?.[f];
  const p12 = prev12?.[f];
  const mom = (p1 != null && p1 !== 0) ? ((lv - p1) / p1) * 100 : null;
  const yoy = (p12 != null && p12 !== 0) ? ((lv - p12) / p12) * 100 : null;
  return {
    latest: lv,
    latestMonth: latest.month,
    mom,
    yoy,
    unit: cfg.unit,
    digits: cfg.digits,
  };
}

function renderStatsBlock(stats) {
  if (!stats) return '<span class="loading">데이터 부족</span>';
  const mom = stats.mom;
  const yoy = stats.yoy;
  const momCls = mom > 0 ? 'pos' : mom < 0 ? 'neg' : '';
  const yoyCls = yoy > 0 ? 'pos' : yoy < 0 ? 'neg' : '';
  const momTxt = mom === null || isNaN(mom) ? '—' : `${mom >= 0 ? '+' : ''}${mom.toFixed(1)}%`;
  const yoyTxt = yoy === null || isNaN(yoy) ? '—' : `${yoy >= 0 ? '+' : ''}${yoy.toFixed(1)}%`;
  const latest = stats.latest != null
    ? `${Number(stats.latest).toLocaleString('en-US', { maximumFractionDigits: stats.digits })} ${stats.unit}`
    : '—';
  return `
    <div class="semicon-stat">
      <span class="stat-label">${stats.latestMonth}</span>
      <span class="stat-value">${latest}</span>
    </div>
    <div class="semicon-stat">
      <span class="stat-label">MoM</span>
      <span class="stat-value ${momCls}">${momTxt}</span>
    </div>
    <div class="semicon-stat">
      <span class="stat-label">YoY</span>
      <span class="stat-value ${yoyCls}">${yoyTxt}</span>
    </div>
  `;
}

function drawChart(canvasId, label, series, color) {
  if (typeof Chart === 'undefined') {
    console.warn('Chart.js not loaded yet');
    return;
  }
  const ctx = document.getElementById(canvasId);
  if (!ctx) return;
  const cfg = metricCfg();
  const f = cfg.field;
  const labels = series.map(d => d.month);
  const values = series.map(d => d[f]);

  const key = canvasId.replace('Chart', '');
  if (semiconCharts[key]) semiconCharts[key].destroy();

  const chart = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: `${label} ${cfg.label} (${cfg.unit})`,
        data: values,
        borderColor: color,
        backgroundColor: color + '22',
        borderWidth: 2,
        pointRadius: 0,
        pointHoverRadius: 5,
        tension: 0.15,
        fill: true,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: (c) => {
              const v = c.parsed.y;
              const txt = v == null
                ? '—'
                : Number(v).toLocaleString('en-US', { maximumFractionDigits: cfg.digits });
              return `${txt} ${cfg.unit}`;
            },
          },
        },
      },
      scales: {
        x: {
          ticks: {
            maxRotation: 0,
            autoSkip: true,
            maxTicksLimit: 12,
            font: { size: 11 },
          },
          grid: { display: false },
        },
        y: {
          beginAtZero: cfg.field !== 'unitPrice',
          ticks: {
            callback: (v) => Number(v).toLocaleString('en-US', { maximumFractionDigits: cfg.digits }),
            font: { size: 11 },
          },
          grid: { color: '#e9ecf0' },
        },
      },
    },
  });

  semiconCharts[key] = chart;
}

function renderSemicon() {
  if (!tradeCache) return;
  const palette = {
    ssd:  '#1e3a5f',
    nand: '#b89968',
    dram: '#2c5282',
  };
  ['ssd', 'nand', 'dram'].forEach(key => {
    const full = tradeCache[key] || [];
    const filtered = filterByRange(full, semiconRange);
    const stats = computeStats(full); // stats always from full series (latest is latest)
    const statsEl = document.getElementById(`${key}Stats`);
    if (statsEl) statsEl.innerHTML = renderStatsBlock(stats);
    drawChart(`${key}Chart`, key.toUpperCase(), filtered, palette[key]);
  });
}

// ─── Semiconductor Peer & IPO View ───────────────────────
let peerCache = null;
let ipoCache  = null;

async function loadPeer() {
  if (!peerCache) {
    try {
      const res = await fetch(`${PEER_URL}?_=${Date.now()}`, { cache: 'no-store' });
      if (res.ok) peerCache = await res.json();
    } catch (err) { console.warn('peer.json fetch failed:', err); }
  }
  if (!ipoCache) {
    try {
      const res = await fetch(`${IPO_URL}?_=${Date.now()}`, { cache: 'no-store' });
      if (res.ok) ipoCache = await res.json();
    } catch (err) { console.warn('ipo.json fetch failed:', err); }
  }
  renderPeer();
  renderIpo();
}

function renderPeer() {
  if (!peerCache) return;

  // Header meta
  const setText = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v ?? '—'; };
  setText('peerRefDate',  peerCache.refDate);
  setText('peerPrevDate', peerCache.prevDate);
  setText('peerYtdDate',  peerCache.ytdDate);

  const body = document.getElementById('peerBody');
  if (!body) return;

  const fmtPct = (v) => {
    if (v == null) return '—';
    const cls = v > 0 ? 'up' : (v < 0 ? 'down' : 'flat');
    const sign = v > 0 ? '+' : '';
    return `<span class="peer-pct ${cls}">${sign}${(v * 100).toFixed(1)}%</span>`;
  };
  const fmtMcap = (v) => {
    if (v == null) return '—';
    return Math.round(v).toLocaleString();
  };
  const fmtMult = (v) => {
    if (v == null) return '<span class="peer-nm">NM</span>';
    return v.toFixed(1) + 'x';
  };

  // Group by category in the order they first appear (preserves Excel layout).
  const groups = [];
  const groupMap = {};
  for (const c of peerCache.companies) {
    if (!groupMap[c.category]) {
      groupMap[c.category] = [];
      groups.push(c.category);
    }
    groupMap[c.category].push(c);
  }

  let html = '';
  for (const cat of groups) {
    const rows = groupMap[cat];
    rows.forEach((c, i) => {
      const rowSpan = (i === 0) ? ` rowspan="${rows.length}"` : '';
      const catCell = (i === 0) ? `<td class="peer-cat-cell"${rowSpan}>${cat}</td>` : '';
      html += `
        <tr>
          <td class="peer-name">${c.name}</td>
          ${catCell}
          <td class="num-col">${fmtMcap(c.mcap)}</td>
          <td class="num-col">${fmtMult(c.per)}</td>
          <td class="num-col peer-fwd">${fmtMult(c.fwdPer)}</td>
          <td class="num-col">${fmtMult(c.pbr)}</td>
          <td class="num-col peer-fwd">${fmtMult(c.fwdPbr)}</td>
          <td class="num-col">${fmtPct(c.wow)}</td>
          <td class="num-col">${fmtPct(c.ytd)}</td>
        </tr>
      `;
    });
  }
  body.innerHTML = html;
}

// Pre-IPO market cap user overrides — persisted to localStorage + user-state.json
// so the user can fill in values from the prospectus and they survive deploys.
function getIpoMcapOverride(code) {
  if (!code) return null;
  const key = 'ipo-mcap-' + code;
  let raw = localStorage.getItem(key);
  if (raw === null && _userStateCache && _userStateCache[key] != null) {
    raw = String(_userStateCache[key]);
  }
  const v = parseFloat(raw);
  return (isFinite(v) && v > 0) ? v : null;
}
function setIpoMcapOverride(code, value) {
  if (!code) return;
  const key = 'ipo-mcap-' + code;
  localStorage.setItem(key, String(value));
  saveUserState(key, value);
}
function clearIpoMcapOverride(code) {
  if (!code) return;
  const key = 'ipo-mcap-' + code;
  localStorage.removeItem(key);
  saveUserState(key, null);
}

function renderIpo() {
  if (!ipoCache) return;
  const setText = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v ?? '—'; };
  setText('ipoUpdated', ipoCache.updatedKr);

  const body = document.getElementById('ipoBody');
  if (!body) return;

  const fmtPct = (v) => {
    if (v == null) return '—';
    const cls = v > 0 ? 'up' : (v < 0 ? 'down' : 'flat');
    const sign = v > 0 ? '+' : '';
    return `<span class="peer-pct ${cls}">${sign}${(v * 100).toFixed(1)}%</span>`;
  };
  const fmtNum = (v) => v == null ? '—' : Math.round(v).toLocaleString();
  const fmtDate = (s) => {
    if (!s) return '—';
    const m = s.match(/^(\d{4})\/(\d{2})\/(\d{2})$/);
    if (m) return `${m[1].slice(2)}.${m[2]}.${m[3]}`;
    return s;
  };

  // Pre-IPO = no current price yet (company hasn't started trading).
  const isPreIpo = (c) => c.curPrice == null;

  body.innerHTML = ipoCache.companies.map(c => {
    // mcap rendering: locked override > scraped value > input UI for pre-IPOs > "—"
    let mcapCell;
    const override = getIpoMcapOverride(c.code);
    if (c.mcap != null) {
      mcapCell = fmtNum(c.mcap);
    } else if (override != null) {
      mcapCell = `
        <span class="ipo-mcap-fixed">${fmtNum(override)}</span>
        <button class="ipo-mcap-edit" data-code="${c.code}" title="값 수정">✎</button>
      `;
    } else if (isPreIpo(c) && c.code) {
      mcapCell = `
        <input class="ipo-mcap-input" type="number" min="0" step="1" placeholder="입력" data-code="${c.code}" />
        <button class="ipo-mcap-fix" data-code="${c.code}">FIX</button>
      `;
    } else {
      mcapCell = '—';
    }

    const rowCls = isPreIpo(c) ? 'ipo-row pre-ipo' : 'ipo-row';
    return `
      <tr class="${rowCls}">
        <td class="peer-name">${c.name}</td>
        <td class="ipo-date">${fmtDate(c.listDate)}</td>
        <td class="num-col">${fmtNum(c.ipoPrice)}</td>
        <td class="num-col">${fmtNum(c.curPrice)}</td>
        <td class="num-col ipo-mcap-cell">${mcapCell}</td>
        <td class="num-col">${fmtPct(c.curVsIpo)}</td>
      </tr>
    `;
  }).join('');

  // Wire up FIX / Edit / Enter-to-save.
  body.querySelectorAll('.ipo-mcap-fix').forEach(btn => {
    btn.addEventListener('click', () => {
      const code = btn.dataset.code;
      const input = body.querySelector(`.ipo-mcap-input[data-code="${code}"]`);
      const val = parseFloat(input?.value);
      if (!isFinite(val) || val <= 0) {
        input?.focus();
        return;
      }
      setIpoMcapOverride(code, val);
      renderIpo();
    });
  });
  body.querySelectorAll('.ipo-mcap-input').forEach(input => {
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        const btn = body.querySelector(`.ipo-mcap-fix[data-code="${input.dataset.code}"]`);
        btn?.click();
      }
    });
  });
  body.querySelectorAll('.ipo-mcap-edit').forEach(btn => {
    btn.addEventListener('click', () => {
      clearIpoMcapOverride(btn.dataset.code);
      renderIpo();
    });
  });
}

// ─── FedWatch (Fed rate probability) — Home Section 2 ────
let fedwatchCache = null;
let fedwatchView = 'current'; // 'current' | 'aggregated' | 'direction'
let fedwatchActiveMeetingIdx = 0;

async function loadFedWatch() {
  if (fedwatchCache) { renderFedWatch(); return; }
  try {
    const res = await fetch(`${FEDWATCH_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    fedwatchCache = await res.json();
    renderFedWatch();
  } catch (err) {
    console.warn('FedWatch fetch failed:', err);
    const nxt = document.getElementById('fedwatchNext');
    if (nxt) nxt.innerHTML = '<div class="fedwatch-next-loading">FedWatch 데이터를 불러올 수 없습니다.</div>';
  }
}

function fedwatchTopProb(probs) {
  if (!probs || !probs.length) return null;
  return probs.reduce((best, p) => (p.current > (best?.current ?? -1) ? p : best), null);
}

function fedwatchDaysUntil(iso) {
  if (!iso) return null;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const meet = new Date(iso + 'T00:00:00');
  const diff = Math.round((meet - today) / 86400000);
  return diff;
}

// Implied rate from Fed funds futures price: rate = 100 - price
function fedwatchImpliedRate(futurePrice) {
  if (futurePrice == null) return null;
  return 100 - futurePrice;
}

function renderFedWatch() {
  if (!fedwatchCache) return;
  const meetings = (fedwatchCache.meetings || []).filter(m => m.probabilities && m.probabilities.length);
  if (!meetings.length) return;

  // Updated label
  const updEl = document.getElementById('fedwatchUpdated');
  if (updEl) {
    const m0 = meetings[0];
    updEl.textContent = m0.lastUpdate ? `Updated: ${m0.lastUpdate}` : `Updated: ${fedwatchCache.updatedKr || ''}`;
  }

  // Next FOMC highlight card
  const next = meetings[0];
  const top = fedwatchTopProb(next.probabilities);
  const daysLeft = fedwatchDaysUntil(next.iso);
  const impRate = fedwatchImpliedRate(next.futurePrice);
  const nxtEl = document.getElementById('fedwatchNext');
  if (nxtEl) {
    nxtEl.innerHTML = `
      <div class="fedwatch-next-block">
        <span class="fedwatch-next-label">다음 FOMC</span>
        <span class="fedwatch-next-value">${next.date}</span>
        ${daysLeft != null ? `<span class="fedwatch-next-sub">D-${daysLeft} · ${next.meetingTime || ''}</span>` : ''}
      </div>
      <div class="fedwatch-next-block">
        <span class="fedwatch-next-label">시장 컨센서스 (최고확률)</span>
        <span class="fedwatch-next-value big">${top ? top.range : '—'}</span>
        <span class="fedwatch-next-sub">${top ? top.current.toFixed(1) + '%' : ''} · 전주 ${top ? top.prevWeek.toFixed(1) + '%' : ''}</span>
      </div>
      <div class="fedwatch-next-block">
        <span class="fedwatch-next-label">Implied Rate</span>
        <span class="fedwatch-next-value">${impRate != null ? impRate.toFixed(3) + '%' : '—'}</span>
        <span class="fedwatch-next-sub">${next.futurePrice != null ? 'Fed Funds Futures @ ' + next.futurePrice : ''}</span>
      </div>
    `;
  }

  renderFedWatchMatrix(meetings);

  // View toggle: render prob-table for Current/Compare; hide for Aggregated
  // (Aggregated view uses the matrix above only — no per-meeting cards).
  const tableWrap = document.getElementById('fedwatchTableWrap');
  if (tableWrap) {
    // Single-meeting drill-down only makes sense in Current view; the
    // Aggregated and Direction views show summarized data in the matrix above.
    if (fedwatchView === 'current') {
      tableWrap.hidden = false;
      renderFedWatchTable(meetings);
    } else {
      tableWrap.hidden = true;
    }
  }
}

function renderFedWatchTable(meetings) {
  const tabsEl = document.getElementById('fedwatchMeetingTabs');
  if (tabsEl) {
    tabsEl.innerHTML = meetings.map((m, i) => {
      const cls = (i === fedwatchActiveMeetingIdx) ? 'fedwatch-meeting-tab active' : 'fedwatch-meeting-tab';
      return `<button class="${cls}" data-idx="${i}">${m.date}</button>`;
    }).join('');
    tabsEl.querySelectorAll('.fedwatch-meeting-tab').forEach(btn => {
      btn.addEventListener('click', () => {
        fedwatchActiveMeetingIdx = parseInt(btn.dataset.idx, 10);
        renderFedWatch();
      });
    });
  }

  const idx = Math.min(fedwatchActiveMeetingIdx, meetings.length - 1);
  const meeting = meetings[idx];
  const top = fedwatchTopProb(meeting.probabilities);
  const body = document.getElementById('fedwatchProbBody');
  if (!body) return;

  body.innerHTML = meeting.probabilities.map(p => {
    const isTop = (top && p.range === top.range);
    const cls = isTop ? 'highlight' : '';
    const dCurDay = p.current - p.prevDay;
    const dCurWk  = p.current - p.prevWeek;
    const fmt = (v) => v == null ? '—' : v.toFixed(1);
    const arrow = (d) => {
      if (Math.abs(d) < 0.05) return '<span class="fedwatch-delta-flat">·</span>';
      return d > 0
        ? `<span class="fedwatch-delta-up">▲${Math.abs(d).toFixed(1)}</span>`
        : `<span class="fedwatch-delta-down">▼${Math.abs(d).toFixed(1)}</span>`;
    };

    const barHtml = `
        <div class="fedwatch-bar-group">
          <div class="fedwatch-bar-row"><div class="fedwatch-bar-track"><div class="fedwatch-bar-fill" style="width:${p.current}%"></div></div><span class="pct">${fmt(p.current)}%</span></div>
        </div>
      `;

    return `
      <tr class="${cls}">
        <td>${p.range}</td>
        <td class="num-col">${fmt(p.current)}%</td>
        <td class="num-col">${fmt(p.prevDay)}%${arrow(dCurDay)}</td>
        <td class="num-col">${fmt(p.prevWeek)}%${arrow(dCurWk)}</td>
        <td class="fedwatch-bar-cell">${barHtml}</td>
      </tr>
    `;
  }).join('');
}

function setupFedWatchFilters() {
  document.querySelectorAll('#fedwatchViewFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#fedwatchViewFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      fedwatchView = btn.dataset.view;
      renderFedWatch();
    });
  });
}

// CME FedWatch–style conditional probability matrix.
// Branches on fedwatchView:
//   - 'current'    → cells show current %
//   - 'compare'    → cells show current % + ▲▼ delta vs previous week
//   - 'aggregated' → table reshapes into per-meeting summary
//                    (Implied Rate / Most Likely / CUT / HOLD / HIKE vs current rate)
function renderFedWatchMatrix(meetings) {
  if (!meetings || !meetings.length) return;
  const headEl = document.getElementById('fedwatchMatrixHead');
  const bodyEl = document.getElementById('fedwatchMatrixBody');
  const legendEl = document.getElementById('fedwatchMatrixLegend');
  if (!headEl || !bodyEl) return;

  // Current rate column = top probability range of the nearest meeting (shared by all modes).
  const top0 = fedwatchTopProb(meetings[0].probabilities);
  const currentRange = top0 ? top0.range : null;

  // Legend differs per view mode.
  if (legendEl) {
    if (fedwatchView === 'direction') {
      legendEl.innerHTML = `
        <span class="legend-chip legend-cut"></span>CUT
        <span class="legend-chip legend-hold"></span>HOLD
        <span class="legend-chip legend-hike"></span>HIKE
      `;
    } else {
      legendEl.innerHTML = `
        <span class="legend-chip legend-max"></span>최고확률
        <span class="legend-chip legend-current"></span>현재 금리 / 0bp
      `;
    }
  }

  if (fedwatchView === 'direction') {
    renderFedWatchMatrixDirection(meetings, currentRange, headEl, bodyEl);
    return;
  }
  if (fedwatchView === 'aggregated') {
    renderFedWatchMatrixCumulative(meetings, currentRange, headEl, bodyEl);
    return;
  }

  // Collect every range across all meetings, sort by lower bound ascending.
  const rangeSet = new Set();
  meetings.forEach(m => m.probabilities.forEach(p => rangeSet.add(p.range)));
  const ranges = Array.from(rangeSet).sort((a, b) => {
    const aLo = parseFloat(a.split('-')[0]);
    const bLo = parseFloat(b.split('-')[0]);
    return aLo - bLo;
  });

  // "3.25 - 3.50" → "325-350" (bp format like CME)
  const fmtCol = (r) => r.split('-')
    .map(s => Math.round(parseFloat(s.trim()) * 100))
    .join('-');

  // Header row
  headEl.innerHTML = '<tr>'
    + '<th>MEETING DATE</th>'
    + ranges.map(r => {
        const cls = (r === currentRange) ? 'col-current' : '';
        return `<th class="${cls}">${fmtCol(r)}</th>`;
      }).join('')
    + '</tr>';

  // Body rows
  bodyEl.innerHTML = meetings.map(m => {
    const probMap = {};
    m.probabilities.forEach(p => { probMap[p.range] = p.current; });
    const vals = Object.values(probMap).filter(v => v != null);
    const rowMax = vals.length ? Math.max(...vals) : 0;

    const cells = ranges.map(r => {
      const v = probMap[r];
      const has = (v != null);
      const isZero = !has || v === 0;
      const isMax = has && v > 0 && v === rowMax;
      const isCurrent = (r === currentRange);

      let cls = '';
      if (isMax) cls = 'matrix-max';
      else if (isCurrent) cls = 'matrix-current';
      if (isZero) cls += ' matrix-zero';

      const display = isZero ? '0.0%' : v.toFixed(1) + '%';
      return `<td class="${cls.trim()}">${display}</td>`;
    }).join('');

    return `<tr><td class="meeting-cell">${m.date}</td>${cells}</tr>`;
  }).join('');
}

// CME-style Aggregated view: bp-shift matrix.
// Same probabilities as Current, but columns are reframed as cumulative bp
// change from today's Fed Funds target rate. E.g. if current = 3.50-3.75,
// the 3.50-3.75 band is the "0bp" column, 3.75-4.00 is "+25bp", etc.
function renderFedWatchMatrixCumulative(meetings, currentRange, headEl, bodyEl) {
  // Midpoint of current rate range (in % points), e.g. "3.50 - 3.75" -> 3.625
  const midpoint = (rangeStr) => {
    if (!rangeStr) return null;
    const parts = rangeStr.split('-').map(s => parseFloat(s.trim()));
    if (parts.length !== 2 || parts.some(isNaN)) return null;
    return (parts[0] + parts[1]) / 2;
  };
  const curMid = midpoint(currentRange);

  // Build the column set: every unique bp shift across all meetings/ranges.
  const bpSet = new Set();
  meetings.forEach(m => m.probabilities.forEach(p => {
    const mid = midpoint(p.range);
    if (mid != null && curMid != null) {
      const bp = Math.round((mid - curMid) * 100); // % point -> bp
      bpSet.add(bp);
    }
  }));
  const bpCols = Array.from(bpSet).sort((a, b) => a - b);

  // Header: MEETING | -50bp | -25bp | 0bp(현재) | +25bp | +50bp …
  const fmtBpCol = (bp) => {
    if (bp === 0) return '0bp<br><span class="bp-current-mark">(현재)</span>';
    return (bp > 0 ? '+' : '') + bp + 'bp';
  };
  headEl.innerHTML = '<tr>'
    + '<th>MEETING DATE</th>'
    + bpCols.map(bp => {
        const cls = (bp === 0) ? 'col-current' : '';
        return `<th class="${cls}">${fmtBpCol(bp)}</th>`;
      }).join('')
    + '</tr>';

  // Body: per meeting, distribute probabilities into bp columns.
  bodyEl.innerHTML = meetings.map(m => {
    const bpMap = {};
    let rowMax = 0;
    m.probabilities.forEach(p => {
      const mid = midpoint(p.range);
      if (mid == null || curMid == null) return;
      const bp = Math.round((mid - curMid) * 100);
      bpMap[bp] = (bpMap[bp] || 0) + (p.current || 0);
      if (bpMap[bp] > rowMax) rowMax = bpMap[bp];
    });

    const cells = bpCols.map(bp => {
      const v = bpMap[bp] ?? 0;
      const isZero = v === 0;
      const isMax = v > 0 && v === rowMax;
      const isCurrent = (bp === 0);
      let cls = '';
      if (isMax) cls = 'matrix-max';
      else if (isCurrent) cls = 'matrix-current';
      if (isZero) cls += ' matrix-zero';
      return `<td class="${cls.trim()}">${isZero ? '0.0%' : v.toFixed(1) + '%'}</td>`;
    }).join('');

    return `<tr><td class="meeting-cell">${m.date}</td>${cells}</tr>`;
  }).join('');
}

// Direction view: per-meeting summary collapsing all bands into CUT/HOLD/HIKE.
// Columns: MEETING / IMPLIED RATE (100 - futurePrice) / MOST LIKELY / CUT / HOLD / HIKE
// CUT/HOLD/HIKE measured vs `currentRange` (nearest meeting's top range = current Fed Funds target).
function renderFedWatchMatrixDirection(meetings, currentRange, headEl, bodyEl) {
  // Numeric lower bound of current range, used to classify each rate range as cut/hold/hike.
  const curLo = currentRange != null ? parseFloat(currentRange.split('-')[0]) : null;

  headEl.innerHTML = `
    <tr>
      <th>MEETING DATE</th>
      <th>IMPLIED RATE</th>
      <th>MOST LIKELY</th>
      <th class="agg-col-cut">CUT</th>
      <th class="agg-col-hold">HOLD</th>
      <th class="agg-col-hike">HIKE</th>
    </tr>
  `;

  bodyEl.innerHTML = meetings.map(m => {
    const top = fedwatchTopProb(m.probabilities);
    const implied = (m.futurePrice != null) ? (100 - m.futurePrice) : null;

    let pCut = 0, pHold = 0, pHike = 0;
    m.probabilities.forEach(p => {
      if (p.current == null) return;
      const lo = parseFloat(p.range.split('-')[0]);
      if (curLo == null) {
        pHold += p.current; // unknown current → treat all as hold
      } else if (Math.abs(lo - curLo) < 0.01) {
        pHold += p.current;
      } else if (lo < curLo) {
        pCut += p.current;
      } else {
        pHike += p.current;
      }
    });

    // Highlight the dominant scenario among cut / hold / hike.
    const maxBucket = Math.max(pCut, pHold, pHike);
    const cutCls  = (pCut  === maxBucket && pCut  > 0) ? 'agg-bucket agg-cut-cell  agg-bucket-max' : 'agg-bucket agg-cut-cell';
    const holdCls = (pHold === maxBucket && pHold > 0) ? 'agg-bucket agg-hold-cell agg-bucket-max' : 'agg-bucket agg-hold-cell';
    const hikeCls = (pHike === maxBucket && pHike > 0) ? 'agg-bucket agg-hike-cell agg-bucket-max' : 'agg-bucket agg-hike-cell';

    return `
      <tr>
        <td class="meeting-cell">${m.date}</td>
        <td class="agg-implied">${implied != null ? implied.toFixed(3) + '%' : '—'}</td>
        <td class="agg-most-likely">
          <span class="agg-range">${top ? top.range : '—'}</span>
          <span class="agg-pct">${top ? top.current.toFixed(1) + '%' : ''}</span>
        </td>
        <td class="${cutCls}">${pCut.toFixed(1)}%</td>
        <td class="${holdCls}">${pHold.toFixed(1)}%</td>
        <td class="${hikeCls}">${pHike.toFixed(1)}%</td>
      </tr>
    `;
  }).join('');
}

// ─── Shiller P/E (CAPE) — bottom of Home view ─────────────
let shillerCache = null;
let shillerChart = null;
let shillerRange = '20y';

async function loadShiller() {
  if (shillerCache) { renderShiller(); return; }
  try {
    const res = await fetch(`${SHILLER_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    shillerCache = await res.json();
    renderShiller();
  } catch (err) {
    console.warn('Shiller fetch failed:', err);
    const cur = document.getElementById('shillerCurrent');
    if (cur) cur.textContent = 'N/A';
  }
}

function renderShiller() {
  if (!shillerCache) return;

  // Latest spot
  const latest = shillerCache.latest;
  const curEl = document.getElementById('shillerCurrent');
  const dateEl = document.getElementById('shillerDate');
  if (curEl && latest) curEl.textContent = latest.value.toFixed(2);
  if (dateEl && latest) dateEl.textContent = '(' + (latest.raw || latest.date) + ')';

  // Filter monthly series — supports any "<N>y" range (e.g. "5y", "20y", "50y")
  const all = shillerCache.monthly || [];
  let filtered = all;
  const m = String(shillerRange).match(/^(\d+)y$/);
  if (m) {
    const yrsBack = parseInt(m[1], 10);
    const cutoff = new Date();
    cutoff.setFullYear(cutoff.getFullYear() - yrsBack);
    const cutoffStr = cutoff.toISOString().slice(0, 7);
    filtered = all.filter(d => d.month >= cutoffStr);
  }

  drawShillerChart(filtered);
}

function drawShillerChart(series) {
  if (typeof Chart === 'undefined') return;
  const ctx = document.getElementById('shillerChart');
  if (!ctx) return;
  if (shillerChart) shillerChart.destroy();

  // Mean of the *selected range* (not a hardcoded historical constant) —
  // so the toggle (5년 / 20년 / 전체) re-computes the dashed reference line.
  const labels = series.map(d => d.month);
  const values = series.map(d => d.value);
  const mean = values.length
    ? values.reduce((sum, v) => sum + v, 0) / values.length
    : 0;
  const meanLine = new Array(series.length).fill(mean);

  // Label like "5년 평균: 35.42" — uses the active range button text if available
  const activeBtn = document.querySelector('#shillerRangeFilter .filter-btn.active');
  const rangeLbl = activeBtn ? activeBtn.textContent.trim() : '선택 기간';
  const meanLbl = `${rangeLbl} 평균: ${mean.toFixed(2)}`;

  shillerChart = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Shiller P/E (CAPE)',
          data: values,
          borderColor: '#1e3a5f',
          backgroundColor: '#1e3a5f22',
          borderWidth: 2,
          pointRadius: 0,
          pointHoverRadius: 5,
          tension: 0.1,
          fill: true,
        },
        {
          label: meanLbl,
          data: meanLine,
          borderColor: '#b89968',
          borderWidth: 1.5,
          borderDash: [5, 5],
          pointRadius: 0,
          fill: false,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: true, position: 'top', labels: { font: { size: 11 } } },
        tooltip: {
          callbacks: { label: (c) => `${c.dataset.label}: ${c.parsed.y.toFixed(2)}` },
        },
      },
      scales: {
        x: {
          ticks: { maxRotation: 0, autoSkip: true, maxTicksLimit: 12, font: { size: 11 } },
          grid: { display: false },
        },
        y: {
          beginAtZero: false,
          ticks: { font: { size: 11 } },
          grid: { color: '#e9ecf0' },
        },
      },
    },
  });
}

function setupShillerFilters() {
  document.querySelectorAll('#shillerRangeFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#shillerRangeFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      shillerRange = btn.dataset.range;
      renderShiller();
    });
  });
}

// ─── Capital Market: per-card weekly comment (localStorage) ──
// Each card (Index / Rate / Commodity / FX) has an editable comment toggle.
// User types → FIX → saved to localStorage under `capmkt-comment-{key}`,
// and timestamp under `capmkt-comment-time-{key}`. Persists per browser.
function setupCapMktComments() {
  const keys = ['index', 'rate', 'commodity', 'fx'];
  for (const k of keys) initCardComment(k);
}

function initCardComment(key) {
  const toggle  = document.querySelector(`.card-comment-toggle[data-key="${key}"]`);
  const wrap    = document.querySelector(`.card-comment[data-key="${key}"]`);
  const input   = document.querySelector(`.card-comment-input[data-key="${key}"]`);
  const fixBtn  = document.querySelector(`.card-comment-fix[data-key="${key}"]`);
  const timeEl  = document.querySelector(`.card-comment-saved-time[data-key="${key}"]`);
  const badge   = toggle?.querySelector('.toggle-badge');
  if (!toggle || !wrap || !input) return;

  const storageKey = `capmkt-comment-${key}`;
  const timeKey    = `capmkt-comment-time-${key}`;

  // Hydrate from localStorage, fall back to user-state.json cache
  let saved     = localStorage.getItem(storageKey);
  let savedTime = localStorage.getItem(timeKey);
  if (!saved && _userStateCache && typeof _userStateCache[storageKey] === 'string') {
    saved = _userStateCache[storageKey];
  }
  if (!savedTime && _userStateCache && typeof _userStateCache[timeKey] === 'string') {
    savedTime = _userStateCache[timeKey];
  }
  if (saved) {
    input.value = saved;
    if (badge)  badge.hidden = false;
    if (timeEl && savedTime) timeEl.textContent = `Saved · ${savedTime}`;
  }

  // Toggle expand/collapse
  toggle.addEventListener('click', () => {
    const willOpen = wrap.hidden;
    wrap.hidden = !willOpen;
    toggle.classList.toggle('expanded', willOpen);
    toggle.setAttribute('aria-expanded', String(willOpen));
    if (willOpen) input.focus();
  });

  // Auto-save with 400ms debounce — same UX as macro comment
  let saveTimer = null;
  input.addEventListener('input', () => {
    if (timeEl) timeEl.textContent = '저장 중…';
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      const val = input.value.trim();
      if (val) {
        localStorage.setItem(storageKey, val);
        const now = new Date().toLocaleString('ko-KR', {
          year: '2-digit', month: '2-digit', day: '2-digit',
          hour: '2-digit', minute: '2-digit',
        });
        localStorage.setItem(timeKey, now);
        // Mirror to user-state.json so deploy carries the comment everywhere
        saveUserState(storageKey, val);
        saveUserState(timeKey, now);
        if (timeEl) timeEl.textContent = `✓ Saved · ${now}`;
        if (badge)  badge.hidden = false;
      } else {
        localStorage.removeItem(storageKey);
        localStorage.removeItem(timeKey);
        saveUserState(storageKey, null);
        saveUserState(timeKey, null);
        if (timeEl) timeEl.textContent = '';
        if (badge)  badge.hidden = true;
      }
    }, 400);
  });

  // Hide legacy FIX button — auto-save makes it redundant
  if (fixBtn) fixBtn.style.display = 'none';
}

function setupSemiconFilters() {
  document.querySelectorAll('#semiconRangeFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#semiconRangeFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      semiconRange = btn.dataset.range;
      if (tradeCache) renderSemicon();
    });
  });
  document.querySelectorAll('#semiconMetricFilter .filter-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('#semiconMetricFilter .filter-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      semiconMetric = btn.dataset.metric;
      if (tradeCache) renderSemicon();
    });
  });
}

// ─── Init ────────────────────────────────────────────────
const refreshBtnEl = document.getElementById('refreshBtn');
if (refreshBtnEl) refreshBtnEl.addEventListener('click', forceRefresh);

updateClock();
setInterval(updateClock, 1000);

setupRouter();
setupWeeklyFilters();
setupNewsFilters();
setupSemiconFilters();
setupShillerFilters();
setupFedWatchFilters();
setupCapMktComments();
setupDashboardMacroComment();
// Load deployed user-state (valuations + macro notes + comments), then
// re-render deals view if it's already mounted and refill any comment
// fields that are still empty (covers fresh-browser / cleared-cache case).
loadUserState().then(() => {
  // Push any localStorage-only saves (from before /save-state existed) to
  // the server so the next deploy carries them everywhere.
  migrateLocalStorageToUserState();

  // Refill empty Capital Market comments from server cache.
  // (Initial setupCapMktComments() ran before _userStateCache existed —
  //  if this browser has empty localStorage, those inputs are blank now.)
  for (const k of ['index','rate','commodity','fx']) {
    const input  = document.querySelector(`.card-comment-input[data-key="${k}"]`);
    const badge  = document.querySelector(`.card-comment-toggle[data-key="${k}"] .toggle-badge`);
    const timeEl = document.querySelector(`.card-comment-saved-time[data-key="${k}"]`);
    if (!input || input.value !== '') continue;
    const skey = `capmkt-comment-${k}`;
    const tkey = `capmkt-comment-time-${k}`;
    if (_userStateCache && typeof _userStateCache[skey] === 'string' && _userStateCache[skey]) {
      input.value = _userStateCache[skey];
      if (badge) badge.hidden = false;
      if (timeEl && _userStateCache[tkey]) timeEl.textContent = `Saved · ${_userStateCache[tkey]}`;
    }
  }

  // Refill empty Dashboard macro comment from server cache.
  const dmac = document.getElementById('dashboardMacroCommentArea');
  if (dmac && dmac.value === '' && _userStateCache) {
    const v = _userStateCache['dashboard-macro-comment'];
    if (typeof v === 'string' && v) {
      dmac.value = v;
      const dmacFix = document.getElementById('dashboardMacroCommentFix');
      if (dmacFix) dmacFix.disabled = true;
      const dmacStatus = document.getElementById('dashboardMacroCommentStatus');
      const t = _userStateCache['dashboard-macro-comment-time'];
      if (dmacStatus && t) dmacStatus.textContent = `✓ ${t} 저장됨`;
    }
  }

  if (typeof dealsState !== 'undefined' &&
      dealsState.current && dealsState.cache &&
      dealsState.cache[dealsState.current]) {
    renderDealsContent(dealsState.cache[dealsState.current]);
  }
});
loadCalendar();
loadData();
loadWeeklyCalendar();
loadShiller();
loadFedWatch();
// Manual refresh mode — no setInterval. Data is re-fetched only when:
//   - User clicks the ↻ 새로고침 button (forceRefresh → /refresh → Yahoo + Investing)
//   - User reloads the page
// This avoids hitting external API rate limits / anti-bot protection.

