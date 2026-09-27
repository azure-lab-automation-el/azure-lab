// Hebrew UI layer: one dictionary (i18n/he.json, inlined at build as he.js) + patterns for dynamic text.
// Translates text nodes and placeholder/title/aria-label attributes as the app renders them. Code, UPNs and commands stay LTR.
(function () {
  const q = new URLSearchParams(location.search).get('lang'); if (q) localStorage.setItem('lang', q);
  if ((q || localStorage.getItem('lang')) === 'en') return; // English view kept for comparison: ?lang=en (back with ?lang=he)
  const L = 'he-IL';
  document.documentElement.lang = 'he'; document.documentElement.dir = 'rtl';
  // Israeli date/time formats everywhere the app calls toLocale* without a locale.
  for (const m of ['toLocaleString', 'toLocaleDateString', 'toLocaleTimeString']) {
    const o = Date.prototype[m]; Date.prototype[m] = function (loc, opt) { return o.call(this, loc && loc.length ? L : L, Object.assign(m === 'toLocaleTimeString' ? { hour: '2-digit', minute: '2-digit' } : {}, opt || {})); };
  }
  const N = Number.prototype.toLocaleString; Number.prototype.toLocaleString = function (loc, opt) { return N.call(this, L, opt); };
  const D = window.HE_DICT || {};
  const P = [
    [/^(\d+) min ago$/, (m, n) => `לפני ${n} דק׳`], [/^(\d+) h ago$/, (m, n) => `לפני ${n} שע׳`], [/^(\d+) d ago$/, (m, n) => `לפני ${n} ימים`], [/^just now$/, () => 'עכשיו'],
    [/^(\d+) active$/, (m, n) => `${n} פעילים`], [/^(\d+) disabled$/, (m, n) => `${n} מושבתים`], [/^(\d+) members$/, (m, n) => `${n} חברים`],
    [/^(\d+) waiting for approval$/, (m, n) => `${n} ממתינים לאישור`], [/^(\d+) without manager$/, (m, n) => `${n} בלי מנהל`], [/^(\d+) would be created$/, (m, n) => `${n} ייווצרו`],
    [/^\+(\d+) more$/, (m, n) => `ועוד ${n}`], [/^and (\d+) more$/, (m, n) => `ועוד ${n}`], [/^would change (\d+)$/, (m, n) => `היה משנה ${n}`],
    [/^(\d+) ok · (\d+) failed$/, (m, a, b) => `${a} הצליחו · ${b} נכשלו`], [/^(\d+) runs in (\d+)h$/, (m, a, b) => `${a} ריצות ב-${b} שעות`],
    [/^(\d+) runs · (\d+) failed · last (.+)$/, (m, a, b, c) => `${a} ריצות · ${b} נכשלו · אחרונה ${tr(c)}`],
    [/^(.+) · 7 d: (\d+) ok \/ (\d+) failed$/, (m, a, b, c) => `${tr(a)} · 7 ימים: ${b} הצליחו / ${c} נכשלו`],
    [/^updated (.+)$/, (m, t) => `עודכן ${t}`], [/^(\d+) findings?$/, (m, n) => `${n} ממצאים`],
    [/^(\d+) of (\d+) events · page (\d+) of (\d+) · log built (.+), refreshed on every deploy$/, (m, a, b, c, d, e) => `${a} מתוך ${b} אירועים · עמוד ${c} מתוך ${d} · היומן נבנה ${tr(e)}, מתעדכן בכל פריסה`],
    [/^Read (.+) by esther-costs-read \(daily, read-only\)\. No budgets or billing are touched\.$/, (m, a) => `נקרא ${tr(a)} על ידי esther-costs-read (יומי, קריאה בלבד). תקציבים וחיובים לא נוגעים.`],
    [/^Total \$([\d.]+) in (\d+) days\. (.*)$/, (m, a, b, c) => `סה"כ $${a} ב-${b} ימים. ${c.replace('Read-only; no budgets or billing are touched.', 'קריאה בלבד; תקציבים וחיובים לא נוגעים.')}`],
    [/^Directory as of (.+) \(refreshes after every applied change\)\.$/, (m, a) => `מצב המדריך נכון ל-${a} (מתעדכן אחרי כל שינוי שהוחל).`],
    [/^Esther Hospital identity overview · directory as of (.+)$/, (m, a) => `סקירת זהויות בית החולים אסתר · המדריך נכון ל-${a}`],
    [/^Log built (.+) \(refreshes on every deploy, which follows every applied change\)\. Directory snapshot (.+)\.$/, (m, a, b) => `היומן נבנה ${tr(a)} (מתעדכן בכל פריסה, שמגיעה אחרי כל שינוי שהוחל). תמונת המדריך ${tr(b)}.`],
    [/^(.+) · (running|success|failure|queued|cancelled)$/, (m, a, b) => `${a} · ${tr(b)}`],
    [/^([●✓✕◌⊘–?]) (\w+)$/, (m, a, b) => `${a} ${tr(b)}`],
    [/^weekly, (Sun|Mon|Tue|Wed|Thu|Fri|Sat)$/, (m, a) => 'שבועי, יום ' + ({ Sun: 'א׳', Mon: 'ב׳', Tue: 'ג׳', Wed: 'ד׳', Thu: 'ה׳', Fri: 'ו׳', Sat: 'ש׳' }[a])],
    [/^monthly, day (\d+)$/, (m, a) => `חודשי, ב-${a} לחודש`], [/^daily$/, () => 'יומי'], [/^nightly$/, () => 'לילי'],
    [/^people match · group would be created$/, () => 'אנשים מתאימים · הקבוצה תיווצר'], [/^(\d+) people match$/, (m, a) => `${a} אנשים מתאימים`],
    [/^title has (.+)$/, (m, a) => `התפקיד מכיל ${a.replace(/ or /g, ' או ')}`],
    [/^USD ([\d.]+)$/, (m, a) => `$${a}`],
    [/^(.+) · (\d+ (?:min|h|d) ago|just now)$/, (m, a, b) => `${tr(a)} · ${tr(b)}`],
    [/^(\w+) · (approver|admin|helpdesk)$/, (m, a, b) => `${a} · ${tr(b)}`],
    [/^(Good morning|Good afternoon|Good evening)(.*)$/, (m, a, b) => ({ 'Good morning': 'בוקר טוב', 'Good afternoon': 'צהריים טובים', 'Good evening': 'ערב טוב' }[a]) + b],
  ];
  const INL = [[/\b(\d+) min ago\b/g, 'לפני $1 דק׳'], [/\b(\d+) h ago\b/g, 'לפני $1 שע׳'], [/\b(\d+) d ago\b/g, 'לפני $1 ימים'], [/\bjust now\b/g, 'עכשיו']];
  function inl(s) { for (const [re, r] of INL) s = s.replace(re, r); return s; }
  function tr(s) { const k = s.trim(); if (!k) return s; if (D[k]) return s.replace(k, D[k]); for (const [re, f] of P) { const m = re.exec(k); if (m) return s.replace(k, f(...m)); } return inl(s); }
  window.heTr = tr;
  const SKIP = new Set(['SCRIPT', 'STYLE', 'CODE', 'PRE', 'TEXTAREA', 'INPUT']);
  const ltr = (el) => el && el.closest && el.closest('code,pre,.ltr,[dir="ltr"],.upn');
  function node(n) {
    if (n.nodeType === 3) { const p = n.parentElement; if (!p || SKIP.has(p.tagName) || ltr(p)) return; const v = n.nodeValue; if (!/[A-Za-z]/.test(v)) return; const t = tr(v); if (t !== v) n.nodeValue = t; return; }
    if (n.nodeType !== 1 || SKIP.has(n.tagName) && n.tagName !== 'INPUT' && n.tagName !== 'TEXTAREA') return;
    for (const a of ['placeholder', 'title', 'aria-label']) { const v = n.getAttribute && n.getAttribute(a); if (v && /[A-Za-z]/.test(v)) { const t = tr(v); if (t !== v) n.setAttribute(a, t); } }
    if (SKIP.has(n.tagName)) return;
    for (const c of n.childNodes) node(c);
  }
  let busy = false;
  const mo = new MutationObserver((ms) => { if (busy) return; busy = true; try { for (const m of ms) { if (m.type === 'characterData') node(m.target); else for (const a of m.addedNodes) node(a); if (m.type === 'attributes') node(m.target); } } finally { busy = false; } });
  function start() { if (document.title) document.title = tr(document.title); node(document.body); mo.observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['placeholder', 'title', 'aria-label'] }); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
