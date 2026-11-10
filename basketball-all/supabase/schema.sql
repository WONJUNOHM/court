-- 코트 한눈에 — Supabase(Postgres) 스키마
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 Run. 여러 번 실행해도 안전합니다(코트 목록은 매번 갱신).
-- 원칙: 표는 RLS 를 켜고 정책을 두지 않아 브라우저(anon)가 직접 읽거나 쓰지 못한다.
--       앱은 아래 api_* 함수만 호출하고, 함수 안에서 main.py 와 같은 규칙(검증·만료·닉네임 주인 확인)을 지킨다.

create table if not exists courts(
  id text primary key, name text not null, area text not null, address text default '', hoops text default '',
  surface text default '', lights text default '', phone text default '', map_query text default '', note text default '',
  sort int default 0);
alter table courts add column if not exists district text default '';
create table if not exists nicks(nickname text primary key, key_hash text not null, created timestamptz default now());
create table if not exists checkins(id bigserial primary key, court_id text references courts on delete cascade, nickname text not null,
  created timestamptz default now(), out boolean default false);
create table if not exists reports(id bigserial primary key, court_id text references courts on delete cascade, count int not null,
  created timestamptz default now());
create table if not exists conditions(id bigserial primary key, court_id text references courts on delete cascade, tag text not null,
  created timestamptz default now());
create table if not exists posts(id bigserial primary key, court_id text references courts on delete cascade, nickname text not null,
  title text not null, play_at timestamp not null, capacity int not null, level text not null, fmt text not null, link text default '',
  created timestamptz default now());
create table if not exists post_joins(post_id bigint references posts on delete cascade, nickname text, joined timestamptz default now(),
  primary key(post_id, nickname));
create table if not exists fits(id bigserial primary key, court_id text default '', nickname text not null, shoes text not null,
  shoe_size text default '', top text default '', bottom text default '', extra text default '', comment text default '',
  grip int default 0, photo text default '', reports int default 0, created timestamptz default now());
create table if not exists fit_likes(fit_id bigint references fits on delete cascade, nickname text, primary key(fit_id, nickname));
create table if not exists fit_reports(fit_id bigint references fits on delete cascade, reporter text, primary key(fit_id, reporter));
create table if not exists hits(k text, t timestamptz default now());
create index if not exists checkins_court on checkins(court_id, created);
create index if not exists reports_court on reports(court_id, created);
create index if not exists conditions_court on conditions(court_id, created);
create index if not exists posts_play on posts(play_at);
create index if not exists hits_k on hits(k, t);

do $$ declare t text; begin
  foreach t in array array['courts','nicks','checkins','reports','conditions','posts','post_joins','fits','fit_likes','fit_reports','hits'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);
  end loop;
end $$;

insert into courts(id,name,area,address,hoops,surface,lights,phone,map_query,note,sort,district) values
 ('mangwon-yusuji','망원유수지 농구장','마포','마포구 월드컵로25길 190 (망원유수지체육공원)','농구장 3면','','','02-3153-9873','망원유수지체육공원 농구장','상시 개방 · 주차 · 화장실 · 우천·기상특보 시 사용 제한',1,'마포구'),
 ('hg-mangwon','망원한강공원 농구장','한강','망원한강공원','골대 4개 (풀코트 2)','고무','조명 있음','02-3780-0601','망원한강공원 농구장','화장실 · 급수대',2,'마포구'),
 ('hg-yanghwa','양화한강공원 농구장','한강','양화한강공원','','','','','양화한강공원 농구장','',3,'영등포구'),
 ('hg-nanji','난지한강공원 농구장','한강','난지한강공원','','','','02-3780-0611','난지한강공원 농구장','',4,'마포구'),
 ('hg-ichon','이촌한강공원 농구장','한강','이촌한강공원','','','','02-3780-0551','이촌한강공원 농구장','',5,'용산구'),
 ('hg-banpo','반포한강공원 농구장','한강','반포한강공원','','아스팔트','','02-3780-0541','반포한강공원 농구장','바닥이 거칠어 부상 주의. 인근 반포종합운동장을 더 많이 이용',6,'서초구'),
 ('hg-jamwon','잠원한강공원 농구장','한강','잠원한강공원','','','','','잠원한강공원 농구장','',7,'서초구'),
 ('hg-ttukseom','뚝섬한강공원 농구장','한강','뚝섬한강공원','골대 8개 (4개씩 2곳)','우레탄','','','뚝섬한강공원 농구장','뚝섬역 쪽과 먼 쪽 두 곳으로 나뉨 · 장애인 전용 농구장 별도',8,'광진구'),
 ('hg-jamsil','잠실한강공원 농구장','한강','잠실한강공원','','','','02-3708-0511','잠실한강공원 농구장','',9,'송파구'),
 ('hg-gwangnaru','광나루한강공원 농구장','한강','광나루한강공원','','','','02-3780-0501','광나루한강공원 농구장','',10,'강동구')
on conflict (id) do update set name=excluded.name, area=excluded.area, address=excluded.address, hoops=excluded.hoops,
  surface=excluded.surface, lights=excluded.lights, phone=excluded.phone, map_query=excluded.map_query, note=excluded.note, sort=excluded.sort, district=excluded.district;

-- ---------- 내부 도우미 (anon 에게 열지 않음) ----------
create or replace function _kst() returns timestamp language sql stable as $$ select (now() at time zone 'Asia/Seoul') $$;
create or replace function _ago(t timestamptz) returns int language sql stable as $$ select greatest(0, floor(extract(epoch from now()-t)/60))::int $$;
create or replace function _err(msg text) returns void language plpgsql as $$ begin raise exception using message = msg, errcode = 'P0001'; end $$;

create or replace function _nick(n text) returns text language plpgsql as $$
declare s text := btrim(coalesce(n, ''));
begin
  if s = '' or char_length(s) > 20 then perform _err('닉네임을 1~20자로 입력해 주십시오'); end if;
  return s;
end $$;

-- 쓰기 요청 제한: 기기 키당 1분에 60회
create or replace function _limit(k text) returns void language plpgsql security definer set search_path = public as $$
declare h text := md5(coalesce(k, ''));
begin
  if (select count(*) from hits where hits.k = h and t > now() - interval '1 minute') >= 60 then
    perform _err('요청이 너무 많습니다. 잠시 후 다시 시도해 주십시오');
  end if;
  insert into hits(k) values (h);
  if random() < 0.02 then delete from hits where t < now() - interval '10 minutes'; end if;
end $$;

-- 닉네임을 처음 쓴 기기(비밀 키)에 묶는다
create or replace function _owner(n text, k text) returns text language plpgsql security definer set search_path = public as $$
declare s text := _nick(n); h text; cur text;
begin
  k := btrim(coalesce(k, ''));
  if char_length(k) < 16 or char_length(k) > 128 then perform _err('앱을 새로고침한 뒤 다시 시도해 주십시오'); end if;
  perform _limit(k);
  h := encode(sha256(convert_to(k, 'UTF8')), 'hex');
  select key_hash into cur from nicks where nickname = s;
  if cur is null then insert into nicks(nickname, key_hash) values (s, h) on conflict do nothing;
    select key_hash into cur from nicks where nickname = s; end if;
  if cur <> h then perform _err('다른 기기에서 이미 쓰고 있는 닉네임입니다. 다른 닉네임을 정해 주십시오'); end if;
  return s;
end $$;

create or replace function _court(cid text) returns void language plpgsql security definer set search_path = public as $$
begin if not exists (select 1 from courts where id = cid) then perform _err('없는 코트입니다'); end if; end $$;

create or replace function _status(cid text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n_in int; r record; n int;
begin
  select count(*) into n_in from checkins where court_id = cid and not out and created > now() - interval '3 hours';
  select count, _ago(created) ago into r from reports where court_id = cid and created > now() - interval '30 minutes' order by id desc limit 1;
  n := greatest(n_in, coalesce(r.count, 0));
  return jsonb_build_object('checked_in', n_in, 'reported', r.count, 'report_ago', r.ago, 'people', n)
    || case when n < 5 then '{"key":"calm","label":"한산","hint":"여유가 있습니다"}'::jsonb
            when n < 10 then '{"key":"mid","label":"보통","hint":"5대5 가능한 인원입니다"}'::jsonb
            else '{"key":"busy","label":"혼잡","hint":"대기가 있을 수 있습니다"}'::jsonb end;
end $$;

create or replace function _conditions(cid text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d jsonb := '{}'; r record; labels jsonb := '{"lights_on":"조명 켜짐","lights_off":"조명 꺼짐","wet":"바닥 젖음","waiting":"대기팀 있음","ball":"공 빌려줌"}';
begin
  for r in select tag, count(*) n, min(_ago(created)) ago from conditions where court_id = cid and created > now() - interval '2 hours' group by tag loop
    d := d || jsonb_build_object(r.tag, jsonb_build_object('tag', r.tag, 'label', labels->>r.tag, 'n', r.n, 'ago', r.ago));
  end loop;
  if d ? 'lights_on' and d ? 'lights_off' then   -- 더 최근 제보가 이긴다
    d := d - (case when (d->'lights_on'->>'ago')::int > (d->'lights_off'->>'ago')::int then 'lights_on' else 'lights_off' end);
  end if;
  return coalesce((select jsonb_agg(v) from jsonb_each(d) e(k, v)), '[]');
end $$;

create or replace function _open_posts() returns setof posts language sql stable security definer set search_path = public as $$
  select * from posts where play_at > _kst() - interval '3 hours' $$;

create or replace function _post_json(p posts) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', p.id, 'court_id', p.court_id, 'nickname', p.nickname, 'title', p.title,
    'when_text', to_char(p.play_at, 'HH24:MI'), 'need', p.capacity - 1, 'link', p.link, 'play_at', to_char(p.play_at, 'YYYY-MM-DD HH24:MI'),
    'capacity', p.capacity, 'level', p.level, 'fmt', p.fmt, 'created', '', 'court_name', (select name from courts where id = p.court_id),
    'ago', _ago(p.created),
    'joined', coalesce((select jsonb_agg(nickname order by joined) from post_joins where post_id = p.id), '[]')) $$;

create or replace function _posts(cid text, who text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(_post_json(p) order by p.play_at, p.id), '[]') from _open_posts() p
  where (cid is null or p.court_id = cid)
    and (who is null or exists (select 1 from post_joins j where j.post_id = p.id and j.nickname = who)) $$;

create or replace function _fits(cid text, who text) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.id desc), '[]') from (
    select f.id, jsonb_build_object('id', f.id, 'court_id', f.court_id, 'nickname', f.nickname, 'shoes', f.shoes, 'shoe_size', f.shoe_size,
      'top', f.top, 'bottom', f.bottom, 'extra', f.extra, 'comment', f.comment, 'grip', f.grip, 'photo', f.photo, 'reports', f.reports,
      'court_name', coalesce((select name from courts where id = f.court_id), ''), 'ago', _ago(f.created),
      'likes', (select count(*) from fit_likes l where l.fit_id = f.id),
      'liked_by', coalesce((select jsonb_agg(nickname) from fit_likes l where l.fit_id = f.id), '[]')) j
    from fits f where f.reports < 3 and (cid is null or f.court_id = cid) and (who is null or f.nickname = who)
    order by f.id desc limit 50) x $$;

-- ---------- 읽기 API ----------
create or replace function api_meta() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('levels', '["입문","초급","중급","상급","누구나"]'::jsonb, 'formats', '["3vs3","5vs5","자유"]'::jsonb,
    'now_kst', to_char(_kst(), 'YYYY-MM-DD HH24:MI:SS')) $$;

create or replace function api_courts() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(c) - 'sort' || _status(c.id) || jsonb_build_object('conditions', _conditions(c.id),
    'open_posts', (select count(*) from _open_posts() p where p.court_id = c.id)) order by c.sort), '[]') from courts c $$;

create or replace function api_court(cid text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c courts; hours jsonb; samples int;
begin
  select * into c from courts where id = cid;
  if c.id is null then perform _err('없는 코트입니다'); end if;
  -- 시간대(KST)별 평균 인원: 제보 평균과 하루 체크인 수 평균 중 큰 값
  with rep as (select extract(hour from created at time zone 'Asia/Seoul')::int h, avg(count) a from reports where court_id = cid group by 1),
       ci as (select h, avg(n) a from (select extract(hour from created at time zone 'Asia/Seoul')::int h, (created at time zone 'Asia/Seoul')::date d, count(*) n
              from checkins where court_id = cid group by 1, 2) s group by h)
  select jsonb_agg(round(greatest(coalesce(rep.a, 0), coalesce(ci.a, 0))::numeric, 1) order by g.h) into hours
  from generate_series(0, 23) g(h) left join rep on rep.h = g.h left join ci on ci.h = g.h;
  select (select count(*) from reports where court_id = cid) + (select count(*) from checkins where court_id = cid) into samples;
  return to_jsonb(c) - 'sort' || _status(cid) || jsonb_build_object(
    'conditions', _conditions(cid),
    'people_list', coalesce((select jsonb_agg(nickname order by id) from checkins where court_id = cid and not out and created > now() - interval '3 hours'), '[]'),
    'posts', _posts(cid, null),
    'hourly', jsonb_build_object('samples', samples, 'hours', hours),
    'top_shoes', coalesce((select jsonb_agg(jsonb_build_object('shoes', s.shoes, 'n', s.n, 'grip', s.grip) order by s.n desc, s.last desc) from (
        select (array_agg(shoes order by id desc))[1] shoes, count(*) n, round(avg(nullif(grip, 0))::numeric, 1) grip, max(id) last
        from fits where court_id = cid and reports < 3 group by lower(btrim(shoes)) order by n desc, last desc limit 3) s), '[]'));
end $$;

create or replace function api_posts() returns jsonb language sql stable security definer set search_path = public as $$ select _posts(null, null) $$;

create or replace function api_me(nickname text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n text := btrim(coalesce(nickname, '')); ci jsonb;
begin
  select jsonb_build_object('court_id', k.court_id, 'name', c.name, 'ago', _ago(k.created)) into ci
  from checkins k join courts c on c.id = k.court_id
  where k.nickname = n and not k.out and k.created > now() - interval '3 hours' order by k.id desc limit 1;
  return jsonb_build_object('checkin', ci, 'posts', _posts(null, n));
end $$;

create or replace function api_fits(court_id text default '') returns jsonb language sql stable security definer set search_path = public as $$
  select _fits(nullif(court_id, ''), null) $$;
create or replace function api_my_fits(nickname text) returns jsonb language sql stable security definer set search_path = public as $$
  select _fits(null, btrim(coalesce(nickname, ''))) $$;

-- ---------- 쓰기 API (모두 닉네임 주인 확인) ----------
create or replace function api_nick(nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
begin return jsonb_build_object('ok', true, 'nickname', _owner(nickname, key)); end $$;

create or replace function api_checkin(cid text, nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key);
begin
  perform _court(cid);
  update checkins set out = true where checkins.nickname = n and not out;   -- 다른 코트 체크인은 자동 해제
  insert into checkins(court_id, nickname) values (cid, n);
  return '{"ok":true}';
end $$;

create or replace function api_checkout(cid text, nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key);
begin update checkins set out = true where court_id = cid and checkins.nickname = n and not out; return '{"ok":true}'; end $$;

create or replace function api_report(cid text, count int, key text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform _limit(key); perform _court(cid);
  if count is null or count < 0 or count > 40 then perform _err('인원은 0~40명 사이로 입력해 주십시오'); end if;
  insert into reports(court_id, count) values (cid, count);
  return '{"ok":true}';
end $$;

create or replace function api_condition(cid text, tag text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform _limit(key); perform _court(cid);
  if tag is null or tag not in ('lights_on', 'lights_off', 'wet', 'waiting', 'ball') then perform _err('알 수 없는 상태입니다'); end if;
  insert into conditions(court_id, tag) values (cid, tag);
  return '{"ok":true}';
end $$;

create or replace function api_new_post(cid text, nickname text, key text, title text, play_date text, play_time text,
  capacity int, fmt text, level text, link text default '') returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); t text := btrim(coalesce(title, '')); l text := btrim(coalesce(link, '')); at timestamp; pid bigint;
begin
  perform _court(cid);
  if t = '' or char_length(t) > 60 then perform _err('제목을 1~60자로 입력해 주십시오'); end if;
  if capacity is null or capacity < 2 or capacity > 30 then perform _err('전체 인원은 2~30명입니다'); end if;
  if fmt is null or fmt not in ('3vs3', '5vs5', '자유') or level is null or level not in ('입문', '초급', '중급', '상급', '누구나') then
    perform _err('형식 또는 레벨이 올바르지 않습니다'); end if;
  if coalesce(play_date, '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(play_time, '') !~ '^([01]\d|2[0-3]):[0-5]\d$' then
    perform _err('날짜와 시간을 확인해 주십시오'); end if;
  if l <> '' and l !~ '^https://\S{3,200}$' then perform _err('오픈채팅 링크는 https:// 로 시작해야 합니다'); end if;
  begin at := (play_date || ' ' || play_time)::timestamp; exception when others then perform _err('날짜와 시간을 확인해 주십시오'); end;
  if at <= _kst() - interval '30 minutes' or at >= _kst() + interval '15 days' then perform _err('경기 시간은 지금부터 14일 안으로 정해 주십시오'); end if;
  insert into posts(court_id, nickname, title, play_at, capacity, level, fmt, link) values (cid, n, t, at, capacity, level, fmt, l) returning id into pid;
  insert into post_joins(post_id, nickname) values (pid, n);
  return '{"ok":true}';
end $$;

create or replace function api_post_action(pid bigint, act text, nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); p posts;
begin
  select * into p from posts where id = pid for update;
  if p.id is null then if act = 'join' then perform _err('없는 글입니다'); end if; return '{"ok":true}'; end if;
  if act = 'join' then
    if not exists (select 1 from post_joins where post_id = pid and post_joins.nickname = n) then
      if (select count(*) from post_joins where post_id = pid) >= p.capacity then perform _err('이미 마감된 게임입니다'); end if;
      insert into post_joins(post_id, nickname) values (pid, n);
    end if;
  elsif act = 'leave' then delete from post_joins where post_id = pid and post_joins.nickname = n;
  elsif act = 'delete' then delete from posts where id = pid and posts.nickname = n;
  else perform _err('알 수 없는 요청입니다'); end if;
  return '{"ok":true}';
end $$;

create or replace function api_new_fit(nickname text, key text, court_id text, shoes text, shoe_size text default '', top text default '',
  bottom text default '', extra text default '', comment text default '', grip int default 0, photo text default '')
  returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); s text := btrim(coalesce(shoes, '')); ph text := coalesce(photo, '');
begin
  if s = '' or char_length(s) > 50 then perform _err('신발 이름을 1~50자로 입력해 주십시오'); end if;
  if grip is null or grip < 0 or grip > 5 then perform _err('접지력은 1~5점입니다'); end if;
  if coalesce(court_id, '') <> '' then perform _court(court_id); end if;
  -- 사진은 앱이 Storage(fits 버킷)에 먼저 올리고 그 공개 주소만 넘긴다
  if ph <> '' and ph !~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/fits/[0-9a-f-]{36}\.jpg$' then
    perform _err('사진을 다시 올려 주십시오'); end if;
  insert into fits(court_id, nickname, shoes, shoe_size, top, bottom, extra, comment, grip, photo)
  values (coalesce(court_id, ''), n, left(s, 50), left(btrim(coalesce(shoe_size, '')), 12), left(btrim(coalesce(top, '')), 40),
    left(btrim(coalesce(bottom, '')), 40), left(btrim(coalesce(extra, '')), 60), left(btrim(coalesce(comment, '')), 120), grip, ph);
  return '{"ok":true}';
end $$;

create or replace function api_fit_action(fid bigint, act text, nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n text; h text;
begin
  if act = 'report' then   -- 신고는 닉네임 없이도 가능, 기기당 한 번
    perform _limit(key);
    h := md5(coalesce(key, ''));
    insert into fit_reports(fit_id, reporter) select fid, h where exists (select 1 from fits where id = fid) on conflict do nothing;
    if found then update fits set reports = reports + 1 where id = fid; end if;
    return '{"ok":true}';
  end if;
  n := _owner(nickname, key);
  if act = 'like' then
    if exists (select 1 from fit_likes where fit_id = fid and fit_likes.nickname = n) then delete from fit_likes where fit_id = fid and fit_likes.nickname = n;
    elsif exists (select 1 from fits where id = fid) then insert into fit_likes(fit_id, nickname) values (fid, n); end if;
  elsif act = 'delete' then delete from fits where id = fid and fits.nickname = n;
  else perform _err('알 수 없는 요청입니다'); end if;
  return '{"ok":true}';
end $$;

-- ---------- 권한: anon 은 api_* 만 실행 ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and (p.proname like 'api\_%' or p.proname like '\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'api\_%' then execute format('grant execute on function %s to anon, authenticated', f.sig); end if;
  end loop;
end $$;

-- ---------- 사진 저장소: 공개 읽기, JPEG 600KB 이하만 업로드, 수정·삭제 불가 ----------
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
    values ('fits', 'fits', true, 614400, array['image/jpeg'])
    on conflict (id) do update set public = true, file_size_limit = 614400, allowed_mime_types = array['image/jpeg'];
    drop policy if exists "fits upload" on storage.objects;
    create policy "fits upload" on storage.objects for insert to anon, authenticated
      with check (bucket_id = 'fits' and name ~ '^[0-9a-f-]{36}\.jpg$');
  end if;
end $$;
