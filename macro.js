// =============================================================
// Macro Economy Indicators (월간 발표 — PDF Monday Morning Brief 기준)
// CPI/PPI/PMI/JOLTs/ADP/NFP 등은 월간 발표이므로 수기 또는
// FRED API 키 연동(아래 fetchFred 함수)을 통해 갱신합니다.
// =============================================================

const MACRO_DATA = [
  // ─── Review (이미 발표된 지표) ───
  { country: '미국', date: '5/5',  indicator: 'ISM 비제조업 PMI', period: '4월', actual: '53.6',   forecast: '53.7',  previous: '54.0',  unit: 'MoM', type: 'review' },
  { country: '미국', date: '5/5',  indicator: 'JOLTs',           period: '3월', actual: '6.866M', forecast: '6.860M', previous: '6.922M', unit: 'MoM', type: 'review' },
  { country: '미국', date: '5/6',  indicator: 'ADP 민간고용',     period: '4월', actual: '109K',   forecast: '118K',   previous: '61K',    unit: 'MoM', type: 'review' },
  { country: '미국', date: '5/8',  indicator: '비농업고용지수',   period: '4월', actual: '115K',   forecast: '65K',    previous: '185K',   unit: 'MoM', type: 'review' },

  // ─── Preview (발표 예정) ───
  { country: '미국', date: '5/12', indicator: 'Headline CPI',    period: '4월', actual: '', forecast: '3.7%', previous: '3.3%', unit: 'YoY', type: 'preview' },
  { country: '미국', date: '5/12', indicator: 'Core CPI',        period: '4월', actual: '', forecast: '',     previous: '2.6%', unit: 'YoY', type: 'preview' },
  { country: '한국', date: '5/13', indicator: '실업률',           period: '4월', actual: '', forecast: '',     previous: '2.7%', unit: 'MoM', type: 'preview' },
  { country: '미국', date: '5/13', indicator: 'Headline PPI',    period: '4월', actual: '', forecast: '',     previous: '4.0%', unit: 'YoY', type: 'preview' },
  { country: '미국', date: '5/13', indicator: 'Core PPI',        period: '4월', actual: '', forecast: '',     previous: '3.8%', unit: 'YoY', type: 'preview' },
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
