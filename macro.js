// =============================================================
// Macro Economy Indicators (월간 발표 — PDF Monday Morning Brief 기준)
// CPI/PPI/PMI/JOLTs/ADP/NFP 등은 월간 발표이므로 수기 또는
// FRED API 키 연동(아래 fetchFred 함수)을 통해 갱신합니다.
// =============================================================

const MACRO_DATA = [
  // ─── Review (지난주 5/12~5/15 발표 — investing.com 경제캘린더 확정값) ───
  { country: '미국', date: '5/12', indicator: 'Headline CPI',    period: '4월', actual: '3.8%', forecast: '3.7%', previous: '3.3%', unit: 'YoY', type: 'review' },
  { country: '미국', date: '5/12', indicator: 'Core CPI',        period: '4월', actual: '2.8%', forecast: '2.7%', previous: '2.6%', unit: 'YoY', type: 'review' },
  { country: '한국', date: '5/13', indicator: '실업률',           period: '4월', actual: '2.8%', forecast: '',     previous: '2.7%', unit: 'MoM', type: 'review' },
  { country: '미국', date: '5/13', indicator: 'Headline PPI',    period: '4월', actual: '6.0%', forecast: '4.9%', previous: '4.3%', unit: 'YoY', type: 'review' },
  { country: '미국', date: '5/13', indicator: 'Core PPI',        period: '4월', actual: '5.2%', forecast: '4.3%', previous: '4.0%', unit: 'YoY', type: 'review' },

  // ─── Preview (다음주 5/18~5/22 발표 예정 — investing.com importance ★★★만 선별) ───
  { country: '미국', date: '5/19', indicator: 'Building Permits',        period: '4월', actual: '', forecast: '', previous: '1.467M', unit: 'MoM', type: 'preview' },
  { country: '미국', date: '5/19', indicator: 'Housing Starts',          period: '4월', actual: '', forecast: '', previous: '1.324M', unit: 'MoM', type: 'preview' },
  { country: '미국', date: '5/20', indicator: 'FOMC Meeting Minutes',    period: '4월', actual: '', forecast: '', previous: '',       unit: '—',   type: 'preview' },
  { country: '미국', date: '5/21', indicator: 'Initial Jobless Claims',  period: '',     actual: '', forecast: '', previous: '',       unit: 'WoW', type: 'preview' },
  { country: '미국', date: '5/21', indicator: 'S&P Global Mfg PMI',      period: '5월', actual: '', forecast: '', previous: '54.5',   unit: 'Idx', type: 'preview' },
  { country: '미국', date: '5/21', indicator: 'S&P Global Services PMI', period: '5월', actual: '', forecast: '', previous: '51.3',   unit: 'Idx', type: 'preview' },
  { country: '미국', date: '5/21', indicator: 'Existing Home Sales',     period: '4월', actual: '', forecast: '', previous: '4.02M',  unit: 'MoM', type: 'preview' },
];

// =============================================================
// (선택) FRED API 연동 — API 키 발급 후 사용
// https://fred.stlouisfed.org/docs/api/api_key.html
// =============================================================
const FRED_API_KEY = ''; // ← API 키 입력 시 자동 연동

const FRED_SERIES = {
  'Headline CPI':     'CPIAUCSL',
  'Core CPI':         'CPILFESL',
  'Headline PPI':     'PPIACO',
  'Core PPI':         'PPILFE',
  'ISM 비제조업 PMI': 'NMFCI',       // ISM Services PMI
  'JOLTs':            'JTSJOL',
  'ADP 민간고용':     'ADPMNUSNERSA',
  '비농업고용지수':   'PAYEMS',
};

async function fetchFred(seriesId) {
  if (!FRED_API_KEY) return null;
  const url = `https://api.stlouisfed.org/fred/series/observations?series_id=${seriesId}&api_key=${FRED_API_KEY}&file_type=json&sort_order=desc&limit=2`;
  try {
    const res = await fetch(url);
    const data = await res.json();
    if (!data.observations || data.observations.length === 0) return null;
    return {
      latest: data.observations[0],
      previous: data.observations[1],
    };
  } catch (e) {
    console.warn('FRED fetch failed:', seriesId, e);
    return null;
  }
}
