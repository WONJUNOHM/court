/* Supabase 백엔드: 앱의 api/* 요청을 Supabase 의 api_* 함수 호출로 바꿔 준다.
   규칙(검증·만료·닉네임 주인 확인)은 모두 DB 함수(supabase/schema.sql) 안에 있다.
   아래 키는 브라우저에 공개해도 되는 publishable 키다. 표는 RLS 로 막혀 있어 함수로만 접근된다. */
(function () {
  const URL_ = '__SUPABASE_URL__', KEY = '__SUPABASE_KEY__';
  const realFetch = window.fetch.bind(window);
  const H = {apikey: KEY, 'Content-Type': 'application/json'};
  class HttpError extends Error { constructor(code, msg) { super(msg); this.code = code; } }

  async function rpc(fn, args = {}) {
    let r;
    try { r = await realFetch(`${URL_}/rest/v1/rpc/${fn}`, {method: 'POST', headers: H, body: JSON.stringify(args)}); }
    catch (e) { throw new HttpError(503, '서버에 연결할 수 없어요. 인터넷 연결을 확인해 주세요'); }
    const d = await r.json().catch(() => null);
    if (!r.ok) throw new HttpError(r.status === 401 ? 403 : 400, (d && d.message) || '요청에 실패했어요');
    return d;
  }

  async function uploadPhoto(dataUrl) {
    const m = /^data:image\/jpeg;base64,([A-Za-z0-9+/=]+)$/.exec(dataUrl || '');
    if (!m) throw new HttpError(400, '사진은 JPEG만 올릴 수 있어요');
    const bin = atob(m[1]), bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    if (bytes.length > 600 * 1024) throw new HttpError(400, '사진 용량이 너무 커요');
    const name = crypto.randomUUID() + '.jpg';
    const r = await realFetch(`${URL_}/storage/v1/object/fits/${name}`, {method: 'POST', headers: {apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'image/jpeg'}, body: bytes})
      .catch(() => null);
    if (!r || !r.ok) throw new HttpError(400, '사진을 올리지 못했어요. 잠시 후 다시 시도해 주세요');
    return `${URL_}/storage/v1/object/public/fits/${name}`;
  }

  async function route(method, path, q, b) {
    let m;
    const key = b.key || '';
    if (method === 'GET') {
      if (path === 'api/meta') return rpc('api_meta');
      if (path === 'api/courts') return rpc('api_courts');
      if ((m = path.match(/^api\/courts\/([^/]+)$/))) return rpc('api_court', {cid: decodeURIComponent(m[1])});
      if (path === 'api/posts') return rpc('api_posts');
      if (path === 'api/fits') return rpc('api_fits', {court_id: q.court_id || ''});
      if (path === 'api/me') return rpc('api_me', {nickname: q.nickname || ''});
      if (path === 'api/me/fits') return rpc('api_my_fits', {nickname: q.nickname || ''});
    } else {
      if (path === 'api/nick') return rpc('api_nick', {nickname: b.nickname, key});
      if (path === 'api/suggest') return rpc('api_suggest_court', {nickname: b.nickname, key, name: b.name, district: b.district, address: b.address || '', hoops: b.hoops || '',
        surface: b.surface || '', note: b.note || '', lat: b.lat ?? null, lng: b.lng ?? null});
      if ((m = path.match(/^api\/courts\/([^/]+)\/(checkin|checkout|report|condition|posts)$/))) {
        const cid = decodeURIComponent(m[1]);
        if (m[2] === 'checkin' || m[2] === 'checkout') return rpc('api_' + m[2], {cid, nickname: b.nickname, key});
        if (m[2] === 'report') return rpc('api_report', {cid, count: Math.floor(b.count), key});
        if (m[2] === 'condition') return rpc('api_condition', {cid, tag: b.tag, key});
        return rpc('api_new_post', {cid, nickname: b.nickname, key, title: b.title, play_date: b.play_date, play_time: b.play_time,
          capacity: Math.floor(b.capacity), fmt: b.fmt, level: b.level, link: b.link || ''});
      }
      if ((m = path.match(/^api\/posts\/(\d+)\/(join|leave|delete)$/))) return rpc('api_post_action', {pid: +m[1], act: m[2], nickname: b.nickname || '', key});
      if (path === 'api/fits') {
        // 닉네임 주인부터 확인한 뒤 사진을 올린다(남의 닉네임으로 사진만 쌓이는 것 방지)
        await rpc('api_nick', {nickname: b.nickname, key});
        const photo = b.photo ? await uploadPhoto(b.photo) : '';
        return rpc('api_new_fit', {nickname: b.nickname, key, court_id: b.court_id || '', shoes: b.shoes, shoe_size: b.shoe_size || '', top: b.top || '',
          bottom: b.bottom || '', extra: b.extra || '', comment: b.comment || '', grip: b.grip | 0, photo});
      }
      if ((m = path.match(/^api\/fits\/(\d+)\/(like|report|delete)$/))) return rpc('api_fit_action', {fid: +m[1], act: m[2], nickname: b.nickname || '', key});
    }
    throw new HttpError(404, '찾을 수 없어요');
  }

  window.fetch = async function (input, init = {}) {
    const url = typeof input === 'string' ? input : input.url;
    const u = new URL(url, location.href);
    if (u.origin !== location.origin) return realFetch(input, init);
    const path = u.pathname.replace(/^.*?(api\/)/, '$1');
    if (!/^api\//.test(path)) return realFetch(input, init);
    const method = (init.method || 'GET').toUpperCase(), q = Object.fromEntries(u.searchParams);
    let body = {}; try { body = init.body ? JSON.parse(init.body) : {}; } catch (e) {}
    try {
      const out = await route(method, path, q, body);
      return new Response(JSON.stringify(out), {status: 200, headers: {'Content-Type': 'application/json'}});
    } catch (e) {
      const code = e instanceof HttpError ? e.code : 500;
      return new Response(JSON.stringify({detail: e instanceof HttpError ? e.message : '오류가 발생했어요'}), {status: code, headers: {'Content-Type': 'application/json'}});
    }
  };
})();
