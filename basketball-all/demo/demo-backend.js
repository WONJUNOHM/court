/* 체험용 데모 백엔드: 서버(FastAPI) 없이 브라우저 localStorage 로 api/* 요청을 처리한다.
   main.py 의 규칙(혼잡도 계산, 만료 시간, 검증)을 그대로 옮겼다. */
(function () {
  const COURTS = __COURTS__;
  const KEY = 'court-demo-v1', MIN = 60e3, HOUR = 36e5;
  const LEVELS = ['입문', '초급', '중급', '상급', '누구나'], FORMATS = ['3vs3', '5vs5', '자유'];
  const COND_TAGS = {lights_on: '조명 켜짐', lights_off: '조명 꺼짐', wet: '바닥 젖음', waiting: '대기팀 있음', ball: '공 빌려줌'};
  const HIDE_AT = 3;
  const realFetch = window.fetch.bind(window);
  const nowMs = () => Date.now();
  const kstStr = (ms = nowMs()) => new Date(ms + 9 * HOUR).toISOString().slice(0, 16).replace('T', ' ');
  const agoMin = t => Math.max(0, Math.floor((nowMs() - t) / MIN));
  const mem = {};
  const load = () => { try { const s = localStorage.getItem(KEY); if (s) return JSON.parse(s); } catch (e) {} return mem.s || null; };
  const save = s => { mem.s = s; try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) { throw new HttpError(400, '저장 공간이 부족합니다. 하단의 초기화를 눌러 주세요'); } };
  class HttpError extends Error { constructor(code, msg) { super(msg); this.code = code; } }

  function seed() {
    const t = nowMs(), s = {seq: 100, checkins: [], reports: [], conds: [], posts: [], fits: [], fitReported: []};
    const ci = (c, n, m) => s.checkins.push({court: c, nick: n, t: t - m * MIN, out: false});
    ci('hg-mangwon', '예시-민수', 40); ci('hg-mangwon', '예시-지훈', 70); ci('hg-mangwon', '예시-서연', 95);
    s.reports.push({court: 'hg-mangwon', count: 7, t: t - 5 * MIN}, {court: 'hg-ttukseom', count: 11, t: t - 12 * MIN},
      {court: 'hg-banpo', count: 2, t: t - 20 * MIN}, {court: 'mangwon-yusuji', count: 4, t: t - 8 * MIN});
    s.conds.push({court: 'hg-mangwon', tag: 'lights_on', t: t - 30 * MIN}, {court: 'hg-banpo', tag: 'wet', t: t - 15 * MIN});
    const mk = (id, court, title, addMin, cap, fmt, level, joined, nick) => s.posts.push({id, court, nick, title, play_at: kstStr(t + addMin * MIN), capacity: cap, fmt, level, link: '', created: t - 25 * MIN, joined});
    mk(1, 'hg-mangwon', '예시 · 5대5 한 판 뛰실 분', 120, 10, '5vs5', '중급', ['예시-민수', '예시-지훈', '예시-서연', '예시-도윤', '예시-하준', '예시-유나'], '예시-민수');
    mk(2, 'mangwon-yusuji', '예시 · 3대3 입문자 환영', 26 * 60, 6, '3vs3', '입문', ['예시-가온', '예시-나래', '예시-다온'], '예시-가온');
    mk(3, 'hg-ttukseom', '예시 · 자유 슈팅 + 미니게임', 5 * 60, 8, '자유', '누구나', ['예시-라온', '예시-마루', '예시-바다', '예시-사랑', '예시-아란', '예시-자람', '예시-차온'], '예시-라온');
    s.fits.push({id: 1, court: 'hg-banpo', nick: '예시-지훈', shoes: '나이키 KD 16', size: '270', top: '흰 슬리브리스', bottom: '검정 반바지', extra: '발목 보호대', comment: '아스팔트라 밑창이 빨리 닳는 느낌입니다.', grip: 3, photo: '', created: t - 3 * HOUR, likes: ['예시-서연'], reports: 0},
      {id: 2, court: 'hg-mangwon', nick: '예시-서연', shoes: '아디다스 하든 8', size: '250', top: '회색 반팔', bottom: '네이비 반바지', extra: '', comment: '고무 바닥이라 접지가 좋았습니다.', grip: 5, photo: '', created: t - 26 * HOUR, likes: [], reports: 0});
    return s;
  }
  let S = load() || seed(); save(S);

  const V = {
    nick(s) { s = (s || '').trim(); if (!s || s.length > 20) throw new HttpError(400, '닉네임을 1~20자로 입력해 주세요'); return s; },
    court(id) { const c = COURTS.find(x => x.id === id); if (!c) throw new HttpError(404, '없는 코트예요'); return c; },
  };
  const level = n => n < 5 ? {key: 'calm', label: '한산', hint: '여유가 있어요'} : n < 10 ? {key: 'mid', label: '보통', hint: '5대5 가능한 인원이에요'} : {key: 'busy', label: '혼잡', hint: '대기가 있을 수 있어요'};
  function status(cid) {
    const t = nowMs();
    const nIn = S.checkins.filter(x => x.court === cid && !x.out && x.t > t - 3 * HOUR).length;
    const r = S.reports.filter(x => x.court === cid && x.t > t - 30 * MIN).sort((a, b) => b.t - a.t)[0];
    const n = Math.max(nIn, r ? r.count : 0);
    return {checked_in: nIn, reported: r ? r.count : null, report_ago: r ? agoMin(r.t) : null, people: n, ...level(n)};
  }
  function conditions(cid) {
    const t = nowMs(), g = {};
    S.conds.filter(x => x.court === cid && x.t > t - 2 * HOUR).forEach(x => { const o = g[x.tag] || (g[x.tag] = {n: 0, ago: 1e9}); o.n++; o.ago = Math.min(o.ago, agoMin(x.t)); });
    if (g.lights_on && g.lights_off) delete g[g.lights_on.ago > g.lights_off.ago ? 'lights_on' : 'lights_off'];
    return Object.entries(g).map(([tag, v]) => ({tag, label: COND_TAGS[tag], ...v}));
  }
  const openPost = p => p.play_at > kstStr(nowMs() - 3 * HOUR);
  const postView = p => ({id: p.id, court_id: p.court, nickname: p.nick, title: p.title, when_text: p.play_at.slice(11), need: p.capacity - 1, link: p.link, play_at: p.play_at,
    capacity: p.capacity, level: p.level, fmt: p.fmt, created: '', court_name: V.court(p.court).name, ago: agoMin(p.created), joined: [...p.joined]});
  const posts = f => S.posts.filter(p => openPost(p) && (!f || f(p))).sort((a, b) => a.play_at.localeCompare(b.play_at) || a.id - b.id).map(postView);
  const fitView = f => ({id: f.id, court_id: f.court, nickname: f.nick, shoes: f.shoes, shoe_size: f.size, top: f.top, bottom: f.bottom, extra: f.extra, comment: f.comment, grip: f.grip,
    photo: f.photo, reports: f.reports, court_name: f.court ? V.court(f.court).name : '', ago: agoMin(f.created), likes: f.likes.length, liked_by: [...f.likes]});
  const fits = f => S.fits.filter(x => x.reports < HIDE_AT && (!f || f(x))).sort((a, b) => b.id - a.id).slice(0, 50).map(fitView);
  function hourly(cid) {
    const byH = {}, rep = S.reports.filter(x => x.court === cid), ci = S.checkins.filter(x => x.court === cid), avg = {};
    rep.forEach(x => { const h = +kstStr(x.t).slice(11, 13); (byH[h] = byH[h] || []).push(x.count); });
    Object.entries(byH).forEach(([h, a]) => avg[h] = a.reduce((p, c) => p + c, 0) / a.length);
    const dh = {}; ci.forEach(x => { const k = kstStr(x.t), h = +k.slice(11, 13), d = k.slice(0, 10); dh[h] = dh[h] || {}; dh[h][d] = (dh[h][d] || 0) + 1; });
    Object.entries(dh).forEach(([h, days]) => { const v = Object.values(days); avg[h] = Math.max(avg[h] || 0, v.reduce((p, c) => p + c, 0) / v.length); });
    return {samples: rep.length + ci.length, hours: Array.from({length: 24}, (_, h) => Math.round((avg[h] || 0) * 10) / 10)};
  }
  function topShoes(cid) {
    const g = {};
    S.fits.filter(f => f.court === cid && f.reports < HIDE_AT).forEach(f => { const k = f.shoes.trim().toLowerCase(), o = g[k] || (g[k] = {shoes: f.shoes, n: 0, gs: [], id: 0}); o.n++; if (f.id > o.id) { o.id = f.id; o.shoes = f.shoes; } if (f.grip) o.gs.push(f.grip); });
    return Object.values(g).sort((a, b) => b.n - a.n || b.id - a.id).slice(0, 3).map(o => ({shoes: o.shoes, n: o.n, grip: o.gs.length ? Math.round(o.gs.reduce((p, c) => p + c, 0) / o.gs.length * 10) / 10 : null}));
  }

  function route(method, path, q, body) {
    let m;
    if (method === 'GET') {
      if (path === 'api/meta') return {levels: LEVELS, formats: FORMATS, now_kst: kstStr() + ':00'};
      if (path === 'api/courts') return COURTS.map(c => ({...c, ...status(c.id), conditions: conditions(c.id), open_posts: S.posts.filter(p => p.court === c.id && openPost(p)).length}));
      if ((m = path.match(/^api\/courts\/([^/]+)$/))) {
        const c = V.court(m[1]), t = nowMs();
        return {...c, ...status(c.id), conditions: conditions(c.id), people_list: S.checkins.filter(x => x.court === c.id && !x.out && x.t > t - 3 * HOUR).map(x => x.nick),
          posts: posts(p => p.court === c.id), hourly: hourly(c.id), top_shoes: topShoes(c.id)};
      }
      if (path === 'api/posts') return posts();
      if (path === 'api/fits') return fits(q.court_id ? f => f.court === q.court_id : null);
      if (path === 'api/me') {
        const n = (q.nickname || '').trim(), t = nowMs();
        const ci = S.checkins.filter(x => x.nick === n && !x.out && x.t > t - 3 * HOUR).sort((a, b) => b.t - a.t)[0];
        return {checkin: ci ? {court_id: ci.court, name: V.court(ci.court).name, ago: agoMin(ci.t)} : null, posts: posts(p => p.joined.includes(n))};
      }
      if (path === 'api/me/fits') return fits(f => f.nick === (q.nickname || '').trim());
    } else {
      if (path === 'api/nick') return {ok: true, nickname: V.nick(body.nickname)};
      if ((m = path.match(/^api\/courts\/([^/]+)\/(checkin|checkout|report|condition|posts)$/))) {
        const c = V.court(m[1]), act = m[2];
        if (act === 'checkin') { const n = V.nick(body.nickname); S.checkins.forEach(x => { if (x.nick === n && !x.out) x.out = true; }); S.checkins.push({court: c.id, nick: n, t: nowMs(), out: false}); }
        else if (act === 'checkout') S.checkins.forEach(x => { if (x.court === c.id && x.nick === (body.nickname || '').trim() && !x.out) x.out = true; });
        else if (act === 'report') { if (!(body.count >= 0 && body.count <= 40)) throw new HttpError(400, '인원은 0~40명 사이로 입력해 주세요'); S.reports.push({court: c.id, count: Math.floor(body.count), t: nowMs()}); }
        else if (act === 'condition') { if (!COND_TAGS[body.tag]) throw new HttpError(400, '알 수 없는 상태예요'); S.conds.push({court: c.id, tag: body.tag, t: nowMs()}); }
        else {
          const n = V.nick(body.nickname), title = (body.title || '').trim(), link = (body.link || '').trim();
          if (!title || title.length > 60) throw new HttpError(400, '제목을 1~60자로 입력해 주세요');
          if (!(body.capacity >= 2 && body.capacity <= 30)) throw new HttpError(400, '전체 인원은 2~30명이에요');
          if (!FORMATS.includes(body.fmt) || !LEVELS.includes(body.level)) throw new HttpError(400, '형식 또는 레벨이 올바르지 않아요');
          if (!/^\d{4}-\d{2}-\d{2}$/.test(body.play_date || '') || !/^([01]\d|2[0-3]):[0-5]\d$/.test(body.play_time || '')) throw new HttpError(400, '날짜와 시간을 확인해 주세요');
          if (link && !/^https:\/\/\S{3,200}$/.test(link)) throw new HttpError(400, '오픈채팅 링크는 https:// 로 시작해야 해요');
          const at = body.play_date + ' ' + body.play_time;
          if (!(at > kstStr(nowMs() - 30 * MIN) && at < kstStr(nowMs() + 15 * 24 * HOUR))) throw new HttpError(400, '경기 시간은 지금부터 14일 안으로 정해 주세요');
          S.posts.push({id: ++S.seq, court: c.id, nick: n, title, play_at: at, capacity: Math.floor(body.capacity), fmt: body.fmt, level: body.level, link, created: nowMs(), joined: [n]});
        }
        return {ok: true};
      }
      if ((m = path.match(/^api\/posts\/(\d+)\/(join|leave|delete)$/))) {
        const p = S.posts.find(x => x.id === +m[1]); if (!p) { if (m[2] === 'join') throw new HttpError(404, '없는 글이에요'); return {ok: true}; }
        const n = (body.nickname || '').trim();
        if (m[2] === 'join') { const nn = V.nick(n); if (!p.joined.includes(nn)) { if (p.joined.length >= p.capacity) throw new HttpError(400, '이미 마감된 게임이에요'); p.joined.push(nn); } }
        else if (m[2] === 'leave') p.joined = p.joined.filter(x => x !== n);
        else if (p.nick === n) S.posts = S.posts.filter(x => x !== p);
        return {ok: true};
      }
      if (path === 'api/fits') {
        const n = V.nick(body.nickname), shoes = (body.shoes || '').trim();
        if (!shoes || shoes.length > 50) throw new HttpError(400, '신발 이름을 1~50자로 입력해 주세요');
        const grip = body.grip | 0; if (grip < 0 || grip > 5) throw new HttpError(400, '접지력은 1~5점이에요');
        if (body.court_id) V.court(body.court_id);
        if (body.photo && (!/^data:image\/jpeg;base64,[A-Za-z0-9+/=]+$/.test(body.photo) || body.photo.length > 900000)) throw new HttpError(400, '사진은 JPEG만, 용량이 너무 크면 올릴 수 없습니다');
        const cl = (v, k) => (v || '').trim().slice(0, k);
        S.fits.push({id: ++S.seq, court: body.court_id || '', nick: n, shoes: cl(shoes, 50), size: cl(body.shoe_size, 12), top: cl(body.top, 40), bottom: cl(body.bottom, 40), extra: cl(body.extra, 60), comment: cl(body.comment, 120), grip, photo: body.photo || '', created: nowMs(), likes: [], reports: 0});
        return {ok: true};
      }
      if ((m = path.match(/^api\/fits\/(\d+)\/(like|report|delete)$/))) {
        const f = S.fits.find(x => x.id === +m[1]); if (!f) return {ok: true};
        if (m[2] === 'like') { const n = V.nick(body.nickname); f.likes = f.likes.includes(n) ? f.likes.filter(x => x !== n) : [...f.likes, n]; }
        else if (m[2] === 'report') { if (!S.fitReported.includes(f.id)) { S.fitReported.push(f.id); f.reports++; } }
        else if (f.nick === (body.nickname || '').trim()) S.fits = S.fits.filter(x => x !== f);
        return {ok: true};
      }
    }
    throw new HttpError(404, '찾을 수 없어요');
  }

  window.fetch = async function (input, init = {}) {
    const url = typeof input === 'string' ? input : input.url;
    const u = new URL(url, 'http://demo.local/');
    const path = u.pathname.replace(/^\/+/, '').replace(/^.*?(api\/)/, '$1');
    if (!/^api\//.test(path)) return realFetch(input, init);
    const method = (init.method || 'GET').toUpperCase(), q = Object.fromEntries(u.searchParams);
    let body = {}; try { body = init.body ? JSON.parse(init.body) : {}; } catch (e) {}
    try {
      S = load() || S;
      const out = route(method, path, q, body);
      if (method !== 'GET') save(S);
      return new Response(JSON.stringify(out), {status: 200, headers: {'Content-Type': 'application/json'}});
    } catch (e) {
      const code = e instanceof HttpError ? e.code : 500;
      return new Response(JSON.stringify({detail: e instanceof HttpError ? e.message : '오류가 발생했어요'}), {status: code, headers: {'Content-Type': 'application/json'}});
    }
  };
  window.__resetDemo = () => { try { localStorage.removeItem(KEY); } catch (e) {} mem.s = null; location.reload(); };
})();
