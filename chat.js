// =============================================================
// AI Chat Widget — calls /chat endpoint on serve.ps1
// Server bundles dashboard data + calls Anthropic API (Claude Opus 4.7)
// =============================================================

(function () {
  const CHAT_API = '/chat';

  const panel    = document.getElementById('chatPanel');
  const toggle   = document.getElementById('chatToggle');
  const closeBtn = document.getElementById('chatClose');
  const msgsEl   = document.getElementById('chatMessages');
  const input    = document.getElementById('chatInput');
  const sendBtn  = document.getElementById('chatSend');
  const statusEl = document.getElementById('chatStatus');

  // Conversation history sent to API (excludes the greeting bubble)
  const history = [];

  // ─── Open / close panel ─────────────────────────────────
  function openPanel() {
    panel.classList.add('open');
    panel.setAttribute('aria-hidden', 'false');
    toggle.classList.add('hidden');
    setTimeout(() => input.focus(), 250);
  }

  function closePanel() {
    panel.classList.remove('open');
    panel.setAttribute('aria-hidden', 'true');
    toggle.classList.remove('hidden');
  }

  toggle.addEventListener('click', openPanel);
  closeBtn.addEventListener('click', closePanel);

  // Esc to close
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && panel.classList.contains('open')) closePanel();
  });

  // ─── Message rendering ──────────────────────────────────
  function appendMessage(role, text, opts = {}) {
    const wrap = document.createElement('div');
    wrap.className = `chat-message ${role}`;

    const bubble = document.createElement('div');
    bubble.className = 'chat-bubble' + (opts.error ? ' error' : '') + (opts.thinking ? ' thinking' : '');

    if (opts.html) {
      bubble.innerHTML = text;
    } else {
      bubble.textContent = text;
    }

    wrap.appendChild(bubble);
    msgsEl.appendChild(wrap);
    msgsEl.scrollTop = msgsEl.scrollHeight;
    return bubble;
  }

  function thinkingIndicator() {
    return appendMessage('assistant', '<span class="typing-indicator"><span></span><span></span><span></span></span>', { html: true, thinking: true });
  }

  // Convert plain Claude text → safer HTML
  // - Escape HTML entities
  // - Preserve newlines as <br>
  // - Render `code` as <code>, **bold** as <strong>
  function renderResponse(text) {
    let s = text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    s = s.replace(/`([^`]+)`/g, '<code style="background:#f3f5f8;padding:1px 5px;border-radius:3px;font-size:12px;">$1</code>');
    s = s.replace(/\n/g, '<br>');
    return s;
  }

  // ─── Send message ───────────────────────────────────────
  async function sendMessage(text) {
    text = (text || '').trim();
    if (!text) return;
    if (sendBtn.disabled) return;

    appendMessage('user', text);
    history.push({ role: 'user', content: text });

    input.value = '';
    input.disabled = true;
    sendBtn.disabled = true;
    statusEl.classList.remove('error');
    statusEl.textContent = 'Claude Opus 4.7가 응답을 생성하고 있습니다…';

    const placeholder = thinkingIndicator();

    try {
      const res = await fetch(CHAT_API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify({ messages: history }),
      });

      const raw = await res.text();
      let payload;
      try { payload = JSON.parse(raw); } catch { payload = { error: raw }; }

      placeholder.parentElement.remove();

      if (!res.ok || payload.error) {
        const errMsg = payload.error || `HTTP ${res.status}`;
        appendMessage('assistant', `오류: ${errMsg}`, { error: true });
        statusEl.textContent = '응답 실패';
        statusEl.classList.add('error');
        history.pop();
        return;
      }

      const reply = payload.response || '(빈 응답)';
      appendMessage('assistant', renderResponse(reply), { html: true });
      history.push({ role: 'assistant', content: reply });

      const usage = payload.usage || {};
      const cached = usage.cache_read_input_tokens || 0;
      const written = usage.cache_creation_input_tokens || 0;
      const inputT = usage.input_tokens || 0;
      const outputT = usage.output_tokens || 0;
      statusEl.textContent = `토큰 in:${inputT} | out:${outputT} | cache write:${written} read:${cached}`;
    } catch (err) {
      placeholder.parentElement.remove();
      appendMessage('assistant', `네트워크 오류: ${err.message}`, { error: true });
      statusEl.textContent = '네트워크 오류';
      statusEl.classList.add('error');
      history.pop();
    } finally {
      input.disabled = false;
      sendBtn.disabled = false;
      input.focus();
    }
  }

  // ─── Input handlers ─────────────────────────────────────
  sendBtn.addEventListener('click', () => sendMessage(input.value));

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      sendMessage(input.value);
    }
  });

  // Suggestion buttons
  document.querySelectorAll('.chat-suggest').forEach((btn) => {
    btn.addEventListener('click', () => {
      const q = btn.dataset.q;
      if (q) sendMessage(q);
    });
  });
})();
