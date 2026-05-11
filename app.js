// =============================================================
// Reverent Partners — Live Capital Market Dashboard
// Reads: data.json (produced by refresh.ps1)
// =============================================================

const DATA_URL     = './data.json';
const CAL_URL      = './calendar.json';
const CAL_WEEK_URL = './calendar-week.json';
const REFRESH_MS   = 60_000;
const MIN_IMPORTANCE = 2;   // 표시할 최소 importance (1=낮음, 2=중간, 3=높음)

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
  US2Y: '미국채 5년 (^FVX)', US10Y: '미국채 10년', US30Y: '미국채 30년',

  // Commodities
  WTI: 'WTI', GOLD: '금', COPPER: '구리', WHEAT: '밀', BDI: 'BDI',

  // FX
  USDKRW: 'USD/KRW', USDEUR: 'USD/EUR', USDJPY: 'USD/JPY',
  USDCNY: 'USD/CNY', DXY: '달러인덱스',

  // CDS
  CDS_US: '미국', CDS_CN: '중국',

  // Sectors
  IT: 'IT (XLK)', HEALTHCARE: '헬스케어 (XLV)', DISCRET: '자유소비재 (XLY)',
  INDUSTRIALS: 'Industrials (XLI)', STAPLES: '필수소비재 (XLP)',
  ENERGY: '에너지 (XLE)', FINANCIALS: '금융 (XLF)', MATERIALS: '원자재 (XLB)',
  UTILITIES: '유틸리티 (XLU)', REALESTATE: '부동산 (XLRE)', COMM: '통신 (XLC)',
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
  try {
    const res = await fetch(`${CAL_URL}?_=${Date.now()}`, { cache: 'no-store' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    renderMacroFromCalendar(data);
  } catch (err) {
    console.warn('Calendar load failed, using static fallback:', err);
    renderMacroFallback();
  }
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
    const res = await fetch('/news/list?_=' + Date.now(), { cache: 'no-store' });
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
      <p>Claude Code 세션에서 <code>/news-clipping</code> 을 실행하면 결과가 자동으로 <code>dashboard/news/YYYY-MM-DD.md</code> 에 저장되고 여기에 표시됩니다.</p>
      <p>또는 매일 09:03 KST에 자동 실행되는 스케줄이 다음번 실행 시 자동 채워줍니다.</p>
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

// ─── View Router ──────────────────────────────────────────
function showView(name) {
  const valid = ['home', 'weekly', 'news'];
  if (!valid.includes(name)) name = 'home';

  document.querySelectorAll('.view').forEach(v => {
    v.hidden = v.id !== `view-${name}`;
  });
  document.querySelectorAll('.sidebar-item[data-view]').forEach(a => {
    a.classList.toggle('active', a.dataset.view === name);
  });

  if (name === 'weekly' && !weeklyCache) loadWeeklyCalendar();
  if (name === 'news') loadNewsIndex();
  window.scrollTo({ top: 0 });
}

function setupRouter() {
  window.addEventListener('hashchange', () => {
    showView(location.hash.replace('#', '') || 'home');
  });
  showView(location.hash.replace('#', '') || 'home');
}

// ─── Init ────────────────────────────────────────────────
document.getElementById('refreshBtn').addEventListener('click', forceRefresh);

updateClock();
setInterval(updateClock, 1000);

setupRouter();
setupWeeklyFilters();
setupNewsFilters();
loadCalendar();
loadData();
loadWeeklyCalendar();
// Manual refresh mode — no setInterval. Data is re-fetched only when:
//   - User clicks the ↻ 새로고침 button (forceRefresh → /refresh → Yahoo + Investing)
//   - User reloads the page
// This avoids hitting external API rate limits / anti-bot protection.

