/**
 * Reverent Partners — News Curator Core
 * ─────────────────────────────────────────
 * UI/스타일 제거한 순수 큐레이션 엔진.
 *
 * 제공 함수:
 *   curateNews({ pageType, startDate, endDate, opts }) → { items, cost, usage }
 *
 * 사용 모드:
 *   A. 서버(Cloudflare Worker / Node)에서 호출 — 권장. ANTHROPIC_API_KEY를 env에 보관.
 *   B. 브라우저에서 직접 호출 — opts.directBrowser=true 필요 (API 키 노출 주의).
 *
 * ⚠ 현재 dashboard에서는 호출되지 않음 (별도 과금 회피를 위해).
 *    참조용 스키마 + 추후 워커 활성화를 위한 모듈로 보존.
 *    실제 주간 큐레이션은 /deal-flow 슬래시 명령이 동일한 프롬프트/스키마로 수행.
 *
 * 출력 데이터 스키마 (items[]):
 *   {
 *     rank: number,           // 1~10 (score 내림차순 재부여)
 *     title: string,          // 헤드라인
 *     date: string,           // YYYY.MM.DD
 *     category: string,       // 페이지별 분류 (아래 참조)
 *     score: number,          // 1~10
 *     bullets: string[],      // 2~4개, 한국 IB 톤(~함/~임)
 *     financials: string,     // Page 6 한정. "매출/EV/EBITDA/Multiple"
 *     source: string,         // 매체명
 *     url: string             // 원문 URL
 *   }
 *
 * Page 5 categories: 정책/규제 | 증시동향 | 금리/환율 | 펀드결성 | IPO | 자본시장 제도 | 기타
 * Page 6 categories: PE Buyout | 기업간 인수 | 매각 추진 | 우협 선정 | SPA 체결 | Pre-IPO/VC 투자 | 리파이낸싱 | 기타
 */

// ─────────────────────────────────────────
// Defaults
// ─────────────────────────────────────────

export const DEFAULT_SOURCES = [
  'thebell.co.kr', 'investchosun.com', 'dealsite.co.kr', 'hankyung.com',
  'mk.co.kr', 'edaily.co.kr', 'mt.co.kr', 'fnnews.com', 'businesspost.co.kr',
  'bloter.net', 'einfomax.co.kr', 'fsc.go.kr', 'bok.or.kr', 'kcmi.re.kr',
  'korea.kr', 'etoday.co.kr', 'newsis.com', 'yna.co.kr', 'news1.kr', 'biz.chosun.com'
];

export const DEFAULT_PRIORITY = `Page 5 — 자본시장 동향:
1. 금융위·한은 등 당국 정책 변화 (국민성장펀드, 자본시장법, ETF 규제 등)
2. 한국 증시 주요 지표 (코스피·코스닥, 외국인 수급, 거래대금)
3. 환율·금리·외환보유액
4. IPO 시장 동향
5. 펀드 결성 / GP 선정 등 PEF 시장 인프라

Page 6 — 주요 거래 동향:
1. 조 단위 PE 빅딜 (바이아웃·세컨더리)
2. 그룹 카브아웃 (SK·한화·롯데 등 비핵심 자산 매각)
3. 우협 선정·본입찰 마감·SPA 체결 등 진행 단계 임박 딜
4. 기업간 전략적 인수 (수직계열화·볼트온)
5. 한국 PE 운용사 신규 펀드 / 리파이낸싱
6. 재무 데이터(EV·EBITDA·멀티플) 확보 가능한 딜 우선`;

export const DEFAULT_MODEL = 'claude-sonnet-4-5';

const PRICING = {
  'claude-sonnet-4-5': { in: 3, out: 15 },
  'claude-opus-4-5':   { in: 15, out: 75 },
  'claude-opus-4-7':   { in: 15, out: 75 },
};

// ─────────────────────────────────────────
// Prompt builder
// ─────────────────────────────────────────

function buildSystemPrompt({ pageType, startDate, endDate, curationPriority }) {
  const isPage5 = pageType === '자본시장 동향';
  const pageLabel = isPage5 ? 'Page 5 (자본시장 동향)' : 'Page 6 (주요 거래 동향)';
  const categories = isPage5
    ? '정책/규제 | 증시동향 | 금리/환율 | 펀드결성 | IPO | 자본시장 제도 | 기타'
    : 'PE Buyout | 기업간 인수 | 매각 추진 | 우협 선정 | SPA 체결 | Pre-IPO/VC 투자 | 리파이낸싱 | 기타';
  const financialsField = isPage5
    ? ''
    : ',\n    "financials": "매출 ___억 / EV ___억 / EBITDA ___억 / EV/EBITDA __x  (해당 없으면 빈 문자열)"';

  return `당신은 한국 투자은행 Reverent Partners의 시니어 애널리스트입니다. 매주 월요일 발표하는 Weekly Macro Update의 ${pageLabel} 섹션을 위해, ${startDate}부터 ${endDate}까지 보도된 한국 자본시장 뉴스를 수집·요약·정렬하는 역할입니다.

【Reverent Partners 큐레이션 우선순위】
${curationPriority || DEFAULT_PRIORITY}

【작업 절차】
1. web_search 도구를 사용해 "${startDate} ${pageType}", "${pageType} 우협 선정", "${pageType} 인수 매각" 등 키워드로 3~5회 검색
2. 검색 결과 중 ${startDate}~${endDate} 기간 보도 기사만 선별
3. 위 큐레이션 우선순위에 따라 score(1~10) 부여하여 정렬
4. 최종 10개를 아래 JSON 형식으로 출력

【출력 형식 — 반드시 JSON 배열로만 응답, 다른 텍스트 절대 포함 금지】
[
  {
    "rank": 1,
    "title": "보도자료 헤드라인 그대로",
    "date": "YYYY.MM.DD",
    "category": "${categories}",
    "score": 1~10,
    "bullets": ["핵심 한 문장 (60자 이내, ~함/~임 종결어미)", "...", "..."]${financialsField},
    "source": "매체명 (예: 더벨, 인베스트조선, 한국경제, 금융위)",
    "url": "원문 URL"
  }
]

【필수 규칙】
- 반드시 ${startDate}~${endDate} 기간 보도 뉴스만 포함. 그 외 기간 절대 포함 금지
- bullets는 2~4개, 사실 기반 + 한국 투자은행 톤 (~함, ~임 종결)
- 거래 규모·기업가치·멀티플 등 정량 정보 우선 표시
- score 내림차순으로 rank 부여 (1=가장 중요)
- 최종 출력은 순수 JSON 배열만. 마크다운 코드펜스, 설명, 인사말 모두 금지
- 정확히 10개. 부족하면 score를 낮춰서라도 10개 채울 것`;
}

function buildUserPrompt({ pageType, startDate, endDate }) {
  return `${startDate}부터 ${endDate}까지의 한국 ${pageType} 뉴스 10개를 위 형식대로 큐레이션해주세요. web_search를 적극 활용해 신뢰 매체에서 수집하고, Reverent Partners 우선순위에 따라 정렬해주세요. 최종 응답은 반드시 JSON 배열만 반환해주세요.`;
}

// ─────────────────────────────────────────
// Anthropic API call
// ─────────────────────────────────────────

/**
 * @param {Object} args
 * @param {'자본시장 동향'|'주요 거래 동향'} args.pageType
 * @param {string} args.startDate - YYYY-MM-DD
 * @param {string} args.endDate   - YYYY-MM-DD
 * @param {Object} [args.opts]
 * @param {string} args.opts.apiKey            - Anthropic API key
 * @param {string} [args.opts.model]           - Claude model id (default: sonnet-4-5)
 * @param {string} [args.opts.curationPriority]
 * @param {string[]} [args.opts.allowedDomains]
 * @param {boolean} [args.opts.directBrowser]  - true면 브라우저 직통 헤더 추가
 * @param {typeof fetch} [args.opts.fetchImpl] - Node 등에서 주입용
 */
export async function curateNews({ pageType, startDate, endDate, opts = {} }) {
  if (!opts.apiKey) throw new Error('opts.apiKey is required');
  if (!['자본시장 동향', '주요 거래 동향'].includes(pageType)) {
    throw new Error(`Invalid pageType: ${pageType}`);
  }

  const model = opts.model || DEFAULT_MODEL;
  const allowedDomains = opts.allowedDomains?.length ? opts.allowedDomains : DEFAULT_SOURCES;
  const fetchImpl = opts.fetchImpl || globalThis.fetch;

  const headers = {
    'Content-Type': 'application/json',
    'x-api-key': opts.apiKey,
    'anthropic-version': '2023-06-01',
  };
  if (opts.directBrowser) headers['anthropic-dangerous-direct-browser-access'] = 'true';

  const body = {
    model,
    max_tokens: 8000,
    system: buildSystemPrompt({ pageType, startDate, endDate, curationPriority: opts.curationPriority }),
    messages: [{ role: 'user', content: buildUserPrompt({ pageType, startDate, endDate }) }],
    tools: [{
      type: 'web_search_20250305',
      name: 'web_search',
      max_uses: 8,
      allowed_domains: allowedDomains,
      user_location: {
        type: 'approximate',
        city: 'Seoul',
        region: 'Seoul',
        country: 'KR',
        timezone: 'Asia/Seoul',
      },
    }],
  };

  const response = await fetchImpl('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errText = await response.text();
    let errMsg = errText;
    try { errMsg = JSON.parse(errText).error?.message || errText; } catch {}
    throw new Error(`Anthropic API ${response.status}: ${errMsg.substring(0, 300)}`);
  }

  const data = await response.json();
  const usage = data.usage || {};
  const webSearches = usage.server_tool_use?.web_search_requests || 0;
  const cost = calculateCost(model, usage.input_tokens || 0, usage.output_tokens || 0, webSearches);

  const fullText = (data.content || [])
    .filter(b => b.type === 'text')
    .map(b => b.text)
    .join('\n');

  const items = normalizeItems(parseJsonArray(fullText));
  return { items, cost, usage, rawText: fullText };
}

// ─────────────────────────────────────────
// JSON parsing — 3-stage fallback
// ─────────────────────────────────────────

function parseJsonArray(text) {
  const trimmed = text.trim();

  // 1) raw [...] block
  const arrMatch = trimmed.match(/\[\s*\{[\s\S]*\}\s*\]/);
  if (arrMatch) {
    try { return JSON.parse(arrMatch[0]); } catch {}
  }
  // 2) fenced code block
  const fenceMatch = text.match(/```(?:json)?\s*(\[[\s\S]*?\])\s*```/);
  if (fenceMatch) {
    try { return JSON.parse(fenceMatch[1]); } catch {}
  }
  // 3) direct parse
  try { return JSON.parse(trimmed); } catch {}

  throw new Error('Claude 응답을 JSON으로 파싱하지 못했습니다.');
}

// ─────────────────────────────────────────
// Normalize + sort + rank
// ─────────────────────────────────────────

function normalizeItems(parsed) {
  if (!Array.isArray(parsed)) throw new Error('응답이 JSON 배열 형식이 아닙니다');

  return parsed
    .map((it, i) => ({
      rank: it.rank || (i + 1),
      title: it.title || '(제목 없음)',
      date: it.date || '',
      category: it.category || '기타',
      score: typeof it.score === 'number' ? it.score : 5,
      bullets: Array.isArray(it.bullets) ? it.bullets : [],
      financials: it.financials || '',
      source: it.source || '',
      url: it.url || '',
    }))
    .sort((a, b) => b.score - a.score)
    .map((it, i) => ({ ...it, rank: i + 1 }))
    .slice(0, 10);
}

// ─────────────────────────────────────────
// Cost calculation
// ─────────────────────────────────────────

export function calculateCost(model, inputTokens, outputTokens, webSearches) {
  const p = PRICING[model] || PRICING[DEFAULT_MODEL];
  const tokenCost = (inputTokens * p.in + outputTokens * p.out) / 1_000_000;
  const searchCost = webSearches * 0.01;  // $10 per 1000 searches
  return tokenCost + searchCost;
}

// ─────────────────────────────────────────
// Helper: derive startDate from endDate + period
// ─────────────────────────────────────────

export function deriveStartDate(endDate, periodDays = 7) {
  const d = new Date(endDate);
  d.setDate(d.getDate() - periodDays);
  return d.toISOString().slice(0, 10);
}

// ─────────────────────────────────────────
// Helper: render selected items into Weekly Update text format
// (Export 기능. 선택된 items만 ◼/⚫ 양식으로)
// ─────────────────────────────────────────

export function renderWeeklyUpdateText({ page5 = [], page6 = [] }) {
  const lines = [];
  const divider = '━'.repeat(38);

  if (page5.length > 0) {
    lines.push(divider, '  Page 5  —  자본시장 동향', divider, '');
    [...page5].sort((a, b) => b.score - a.score).forEach(item => {
      lines.push(`◼ ${item.title} (${item.date})`);
      item.bullets.forEach(b => lines.push(`   ⚫ ${b}`));
      if (item.source) lines.push(`   ※ 출처: ${item.source}${item.url ? ' · ' + item.url : ''}`);
      lines.push('');
    });
  }
  if (page6.length > 0) {
    lines.push(divider, '  Page 6  —  주요 거래 동향', divider, '');
    [...page6].sort((a, b) => b.score - a.score).forEach(item => {
      lines.push(`◼ ${item.title} (${item.date})`);
      item.bullets.forEach(b => lines.push(`   ⚫ ${b}`));
      if (item.financials) lines.push(`   ※ ${item.financials}`);
      if (item.source) lines.push(`   ※ 출처: ${item.source}${item.url ? ' · ' + item.url : ''}`);
      lines.push('');
    });
  }
  return lines.join('\n');
}
