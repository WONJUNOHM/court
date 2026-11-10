-- 코트 한눈에 — Supabase(Postgres) 스키마
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 Run. 여러 번 실행해도 안전합니다(코트 목록은 매번 갱신).
-- 원칙: 표는 RLS 를 켜고 정책을 두지 않아 브라우저(anon)가 직접 읽거나 쓰지 못한다.
--       앱은 아래 api_* 함수만 호출하고, 함수 안에서 main.py 와 같은 규칙(검증·만료·닉네임 주인 확인)을 지킨다.

create table if not exists courts(
  id text primary key, name text not null, area text not null, address text default '', hoops text default '',
  surface text default '', lights text default '', phone text default '', map_query text default '', note text default '',
  sort int default 0);
alter table courts add column if not exists district text default '';
alter table courts add column if not exists lat double precision;   -- 지도 위치 (지금은 쓰지 않음, 지도를 붙일 때 사용)
alter table courts add column if not exists lng double precision;
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
-- 착장 공개 상태: visible(공개) · pending(관리자 확인 대기) · hidden(관리자가 숨김)
alter table fits add column if not exists status text not null default 'visible';
-- 관리자용: 설정 · 관리자 비밀번호 · 이용 정지 · 지울 사진 목록
create table if not exists settings(id int primary key default 1 check (id = 1),
  require_approval boolean not null default false, hide_at int not null default 3);
insert into settings(id) values (1) on conflict (id) do nothing;
create table if not exists admin_keys(id int primary key default 1 check (id = 1), pw_hash text not null);
create table if not exists bans(nickname text primary key, key_hash text default '', reason text default '', created timestamptz default now());
create table if not exists photo_trash(name text primary key, created timestamptz default now());
-- 이용자가 제보한 새 코트: 관리자가 승인하면 courts 로 옮기고, 거절하면 지운다
create table if not exists court_suggestions(id bigserial primary key, nickname text not null, name text not null, district text not null,
  address text default '', hoops text default '', surface text default '', note text default '', lat double precision, lng double precision,
  created timestamptz default now());
create index if not exists checkins_court on checkins(court_id, created);
create index if not exists reports_court on reports(court_id, created);
create index if not exists conditions_court on conditions(court_id, created);
create index if not exists posts_play on posts(play_at);
create index if not exists hits_k on hits(k, t);

do $$ declare t text; begin
  foreach t in array array['courts','nicks','checkins','reports','conditions','posts','post_joins','fits','fit_likes','fit_reports','hits',
                           'settings','admin_keys','bans','photo_trash','court_suggestions'] loop
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
  if s = '' or char_length(s) > 20 then perform _err('닉네임을 1~20자로 입력해 주세요'); end if;
  return s;
end $$;

-- 개인정보처리방침의 보관 기간이 지난 기록을 지운다 (쓰기 요청 100번에 한 번꼴로 실행)
alter table nicks add column if not exists last_seen timestamptz default now();
create or replace function _cleanup() returns void language plpgsql security definer set search_path = public as $$
begin
  delete from checkins   where created < now() - interval '1 year';
  delete from reports    where created < now() - interval '1 year';
  delete from conditions where created < now() - interval '1 year';
  delete from posts      where play_at < _kst() - interval '30 days';   -- 참가 기록도 함께 지워짐
  -- 1년 동안 안 쓴 닉네임: 올린 착장이 남아 있으면 남의 글을 지울 수 없게 닉네임을 계속 묶어 둔다
  delete from nicks n where coalesce(n.last_seen, n.created) < now() - interval '1 year'
    and not exists (select 1 from fits f where f.nickname = n.nickname)
    and not exists (select 1 from bans b where b.nickname = n.nickname);
  delete from photo_trash where created < now() - interval '30 days';
  delete from court_suggestions where created < now() - interval '90 days';
end $$;

-- 쓰기 요청 제한: 기기 키당 1분에 60회
create or replace function _limit(k text) returns void language plpgsql security definer set search_path = public as $$
declare h text := md5(coalesce(k, ''));
begin
  if (select count(*) from hits where hits.k = h and t > now() - interval '1 minute') >= 60 then
    perform _err('요청이 너무 많아요. 잠시 후 다시 시도해 주세요');
  end if;
  insert into hits(k) values (h);
  if random() < 0.02 then delete from hits where t < now() - interval '10 minutes'; end if;
  if random() < 0.01 then perform _cleanup(); end if;
end $$;

-- 닉네임을 처음 쓴 기기(비밀 키)에 묶는다
create or replace function _owner(n text, k text) returns text language plpgsql security definer set search_path = public as $$
declare s text := _nick(n); h text; cur text;
begin
  k := btrim(coalesce(k, ''));
  if char_length(k) < 16 or char_length(k) > 128 then perform _err('앱을 새로고침한 뒤 다시 시도해 주세요'); end if;
  perform _limit(k);
  h := encode(sha256(convert_to(k, 'UTF8')), 'hex');
  select key_hash into cur from nicks where nickname = s;
  if cur is null then insert into nicks(nickname, key_hash) values (s, h) on conflict do nothing;
    select key_hash into cur from nicks where nickname = s; end if;
  if cur <> h then perform _err('다른 기기에서 이미 쓰는 닉네임이에요. 다른 닉네임을 정해 주세요'); end if;
  if exists (select 1 from bans where bans.nickname = s or (bans.key_hash <> '' and bans.key_hash = h)) then
    perform _err('이용이 제한된 닉네임이에요'); end if;
  update nicks set last_seen = now() where nickname = s and (last_seen is null or last_seen < now() - interval '1 day');
  return s;
end $$;

-- 신고가 이만큼 쌓이면 착장이 자동으로 숨겨진다 (관리자 페이지에서 바꿈)
create or replace function _hide_at() returns int language sql stable security definer set search_path = public as $$
  select coalesce((select hide_at from settings where id = 1), 3) $$;

create or replace function _court(cid text) returns void language plpgsql security definer set search_path = public as $$
begin if not exists (select 1 from courts where id = cid) then perform _err('없는 코트예요'); end if; end $$;

create or replace function _status(cid text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n_in int; r record; n int;
begin
  select count(*) into n_in from checkins where court_id = cid and not out and created > now() - interval '3 hours';
  select count, _ago(created) ago into r from reports where court_id = cid and created > now() - interval '30 minutes' order by id desc limit 1;
  n := greatest(n_in, coalesce(r.count, 0));
  return jsonb_build_object('checked_in', n_in, 'reported', r.count, 'report_ago', r.ago, 'people', n)
    || case when n < 5 then '{"key":"calm","label":"한산","hint":"여유가 있어요"}'::jsonb
            when n < 10 then '{"key":"mid","label":"보통","hint":"5대5 가능한 인원이에요"}'::jsonb
            else '{"key":"busy","label":"혼잡","hint":"대기가 있을 수 있어요"}'::jsonb end;
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
    'when_text', to_char(p.play_at, 'HH24:MI'), 'need', p.capacity - 1, 'has_link', p.link <> '', 'play_at', to_char(p.play_at, 'YYYY-MM-DD HH24:MI'),
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
    from fits f where f.status = 'visible' and f.reports < _hide_at() and (cid is null or f.court_id = cid) and (who is null or f.nickname = who)
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
  if c.id is null then perform _err('없는 코트예요'); end if;
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
        from fits where court_id = cid and status = 'visible' and reports < _hide_at() group by lower(btrim(shoes)) order by n desc, last desc limit 3) s), '[]'));
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
  if count is null or count < 0 or count > 40 then perform _err('인원은 0~40명 사이로 입력해 주세요'); end if;
  insert into reports(court_id, count) values (cid, count);
  return '{"ok":true}';
end $$;

create or replace function api_condition(cid text, tag text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform _limit(key); perform _court(cid);
  if tag is null or tag not in ('lights_on', 'lights_off', 'wet', 'waiting', 'ball') then perform _err('알 수 없는 상태예요'); end if;
  insert into conditions(court_id, tag) values (cid, tag);
  return '{"ok":true}';
end $$;

create or replace function api_new_post(cid text, nickname text, key text, title text, play_date text, play_time text,
  capacity int, fmt text, level text, link text default '') returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); t text := btrim(coalesce(title, '')); l text := btrim(coalesce(link, '')); at timestamp; pid bigint;
begin
  perform _court(cid);
  if t = '' or char_length(t) > 60 then perform _err('제목을 1~60자로 입력해 주세요'); end if;
  if capacity is null or capacity < 2 or capacity > 30 then perform _err('전체 인원은 2~30명이에요'); end if;
  if fmt is null or fmt not in ('3vs3', '5vs5', '자유') or level is null or level not in ('입문', '초급', '중급', '상급', '누구나') then
    perform _err('형식 또는 레벨이 올바르지 않아요'); end if;
  if coalesce(play_date, '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(play_time, '') !~ '^([01]\d|2[0-3]):[0-5]\d$' then
    perform _err('날짜와 시간을 확인해 주세요'); end if;
  if l <> '' and l !~ '^https://\S{3,200}$' then perform _err('오픈채팅 링크는 https:// 로 시작해야 해요'); end if;
  begin at := (play_date || ' ' || play_time)::timestamp; exception when others then perform _err('날짜와 시간을 확인해 주세요'); end;
  if at <= _kst() - interval '30 minutes' or at >= _kst() + interval '15 days' then perform _err('경기 시간은 지금부터 14일 안으로 정해 주세요'); end if;
  insert into posts(court_id, nickname, title, play_at, capacity, level, fmt, link) values (cid, n, t, at, capacity, level, fmt, l) returning id into pid;
  insert into post_joins(post_id, nickname) values (pid, n);
  return '{"ok":true}';
end $$;

-- 오픈채팅 링크는 참가한 사람(모집자 포함)에게만 알려 준다
create or replace function api_post_link(pid bigint, nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); l text;
begin
  select p.link into l from posts p where p.id = pid
    and exists (select 1 from post_joins j where j.post_id = p.id and j.nickname = n);
  if l is null or l = '' then perform _err('참가한 사람만 볼 수 있어요'); end if;
  return jsonb_build_object('link', l);
end $$;

create or replace function api_post_action(pid bigint, act text, nickname text, key text) returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); p posts;
begin
  select * into p from posts where id = pid for update;
  if p.id is null then if act = 'join' then perform _err('없는 글이에요'); end if; return '{"ok":true}'; end if;
  if act = 'join' then
    if not exists (select 1 from post_joins where post_id = pid and post_joins.nickname = n) then
      if (select count(*) from post_joins where post_id = pid) >= p.capacity then perform _err('이미 마감된 게임이에요'); end if;
      insert into post_joins(post_id, nickname) values (pid, n);
    end if;
  elsif act = 'leave' then delete from post_joins where post_id = pid and post_joins.nickname = n;
  elsif act = 'delete' then delete from posts where id = pid and posts.nickname = n;
  else perform _err('알 수 없는 요청이에요'); end if;
  return '{"ok":true}';
end $$;

create or replace function api_new_fit(nickname text, key text, court_id text, shoes text, shoe_size text default '', top text default '',
  bottom text default '', extra text default '', comment text default '', grip int default 0, photo text default '')
  returns jsonb language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); s text := btrim(coalesce(shoes, '')); ph text := coalesce(photo, '');
  st text := case when (select require_approval from settings where id = 1) then 'pending' else 'visible' end;
begin
  if s = '' or char_length(s) > 50 then perform _err('신발 이름을 1~50자로 입력해 주세요'); end if;
  if grip is null or grip < 0 or grip > 5 then perform _err('접지력은 1~5점이에요'); end if;
  if coalesce(court_id, '') <> '' then perform _court(court_id); end if;
  -- 사진은 앱이 Storage(fits 버킷)에 먼저 올리고 그 공개 주소만 넘긴다
  if ph <> '' and ph !~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/fits/[0-9a-f-]{36}\.jpg$' then
    perform _err('사진을 다시 올려 주세요'); end if;
  insert into fits(court_id, nickname, shoes, shoe_size, top, bottom, extra, comment, grip, photo, status)
  values (coalesce(court_id, ''), n, left(s, 50), left(btrim(coalesce(shoe_size, '')), 12), left(btrim(coalesce(top, '')), 40),
    left(btrim(coalesce(bottom, '')), 40), left(btrim(coalesce(extra, '')), 60), left(btrim(coalesce(comment, '')), 120), grip, ph, st);
  return jsonb_build_object('ok', true, 'pending', st = 'pending');
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
  else perform _err('알 수 없는 요청이에요'); end if;
  return '{"ok":true}';
end $$;

-- 새 코트 제보 (닉네임 주인 확인, 대기 3건까지, 한국 안의 좌표만)
create or replace function api_suggest_court(nickname text, key text, name text, district text, address text default '', hoops text default '',
  surface text default '', note text default '', lat double precision default null, lng double precision default null) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare n text := _owner(nickname, key); nm text := btrim(coalesce(name, '')); d text := btrim(coalesce(district, ''));
begin
  if char_length(nm) < 2 or char_length(nm) > 30 then perform _err('코트 이름을 2~30자로 입력해 주세요'); end if;
  if char_length(d) < 1 or char_length(d) > 12 then perform _err('지역(예: 마포구)을 입력해 주세요'); end if;
  if (lat is null) <> (lng is null) or (lat is not null and (lat not between 33 and 39 or lng not between 124 and 132)) then
    perform _err('위치 정보가 올바르지 않아요'); end if;
  if lat is null and btrim(coalesce(address, '')) = '' then perform _err('주소나 찾아가는 방법을 적어 주세요'); end if;
  if exists (select 1 from courts c where regexp_replace(lower(c.name), '\s', '', 'g') = regexp_replace(lower(nm), '\s', '', 'g')) then
    perform _err('이미 등록된 코트예요'); end if;
  if (select count(*) from court_suggestions s where s.nickname = n) >= 3 then
    perform _err('확인 중인 제보가 3건 있어요. 처리된 뒤에 또 올려 주세요'); end if;
  insert into court_suggestions(nickname, name, district, address, hoops, surface, note, lat, lng)
  values (n, nm, d, left(btrim(coalesce(address, '')), 60), left(btrim(coalesce(hoops, '')), 30), left(btrim(coalesce(surface, '')), 10),
    left(btrim(coalesce(note, '')), 80), lat, lng);
  return '{"ok":true}';
end $$;

-- ---------- 관리자 (admin.html 에서 호출, 모두 관리자 비밀번호 확인) ----------
-- 처음 한 번, SQL Editor 에서:  select _admin_set_password('나만 아는 긴 비밀번호');
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function _admin_set_password(new_pw text) returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if char_length(coalesce(new_pw, '')) < 8 then perform _err('비밀번호는 8자 이상으로 정해 주세요'); end if;
  insert into admin_keys(id, pw_hash) values (1, crypt(new_pw, gen_salt('bf')))
  on conflict (id) do update set pw_hash = excluded.pw_hash;
  return '관리자 비밀번호를 설정했어요';
end $$;

-- 맞으면 null, 틀리면 오류 문구. 틀린 기록이 남아야 하므로 예외 대신 문구를 돌려준다(10분에 10번 틀리면 잠금).
create or replace function _admin(pw text) returns text language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  if (select count(*) from hits where k = 'admin-fail' and t > now() - interval '10 minutes') >= 10 then
    return '비밀번호를 여러 번 틀렸어요. 10분 뒤 다시 시도해 주세요'; end if;
  select pw_hash into h from admin_keys where id = 1;
  if h is null then return '관리자 비밀번호가 아직 설정되지 않았어요 (SQL Editor 에서 설정)'; end if;
  if crypt(coalesce(pw, ''), h) <> h then insert into hits(k) values ('admin-fail'); return '비밀번호가 맞지 않아요'; end if;
  return null;
end $$;

create or replace function _photo_name(url text) returns text language sql immutable as $$
  select substring(coalesce(url, '') from '/fits/([0-9a-f-]{36}\.jpg)$') $$;

create or replace function api_admin_overview(pw text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw); s settings;
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  select * into s from settings where id = 1;
  return jsonb_build_object(
    'reported', (select count(*) from fits where reports > 0 and status <> 'hidden'),
    'pending',  (select count(*) from fits where status = 'pending'),
    'hidden',   (select count(*) from fits where status = 'hidden' or reports >= s.hide_at),
    'fits',     (select count(*) from fits),
    'posts',    (select count(*) from _open_posts()),
    'users',    (select count(*) from nicks),
    'banned',   (select count(*) from bans),
    'suggestions', (select count(*) from court_suggestions),
    'require_approval', s.require_approval, 'hide_at', s.hide_at);
end $$;

create or replace function api_admin_fits(pw text, tab text default 'reported', q text default '') returns jsonb
  language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw); lim int := _hide_at(); qq text := '%' || btrim(coalesce(q, '')) || '%';
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  return coalesce((select jsonb_agg(x.j order by x.ord1 desc, x.id desc) from (
    select f.id, case when tab = 'reported' then f.reports else 0 end ord1,
      jsonb_build_object('id', f.id, 'nickname', f.nickname, 'shoes', f.shoes, 'shoe_size', f.shoe_size, 'top', f.top, 'bottom', f.bottom,
        'extra', f.extra, 'comment', f.comment, 'photo', f.photo, 'status', f.status, 'reports', f.reports, 'auto_hidden', f.reports >= lim,
        'court_name', coalesce((select name from courts where id = f.court_id), ''), 'ago', _ago(f.created),
        'banned', exists (select 1 from bans b where b.nickname = f.nickname)) j
    from fits f
    where case tab when 'reported' then f.reports > 0 and f.status <> 'hidden'
                      when 'pending'  then f.status = 'pending'
                      when 'hidden'   then f.status = 'hidden' or f.reports >= lim
                      else true end
      and (btrim(coalesce(q, '')) = '' or f.nickname ilike qq or f.shoes ilike qq or f.comment ilike qq)
    order by ord1 desc, f.id desc limit 200) x), '[]');
end $$;

create or replace function api_admin_fit(pw text, fid bigint, act text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw); ph text;
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if act = 'show' then          -- 공개 (신고 기록도 비움)
    update fits set status = 'visible', reports = 0 where id = fid; delete from fit_reports where fit_id = fid;
  elsif act = 'hide' then update fits set status = 'hidden' where id = fid;
  elsif act = 'delete' then     -- 글 삭제 + 사진을 지울 수 있게 표시 (실제 파일은 관리자 페이지가 바로 지움)
    select _photo_name(photo) into ph from fits where id = fid;
    if ph is not null then insert into photo_trash(name) values (ph) on conflict do nothing; end if;
    delete from fits where id = fid;
    return jsonb_build_object('ok', true, 'photo', ph);
  else return jsonb_build_object('error', '알 수 없는 요청이에요'); end if;
  return '{"ok":true}';
end $$;

create or replace function api_admin_posts(pw text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  return coalesce((select jsonb_agg(_post_json(p) || jsonb_build_object('ended', p.play_at <= _kst() - interval '3 hours') order by p.play_at desc)
    from (select * from posts order by play_at desc limit 200) p), '[]');
end $$;

create or replace function api_admin_post(pw text, pid bigint, act text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if act = 'delete' then delete from posts where id = pid; else return jsonb_build_object('error', '알 수 없는 요청이에요'); end if;
  return '{"ok":true}';
end $$;

create or replace function api_admin_users(pw text, q text default '', tab text default 'all') returns jsonb
  language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw); qq text := '%' || btrim(coalesce(q, '')) || '%';
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  return coalesce((select jsonb_agg(x.j order by x.rep desc, x.created desc) from (
    select n.created, coalesce((select sum(reports) from fits where nickname = n.nickname), 0) rep,
      jsonb_build_object('nickname', n.nickname, 'ago', _ago(n.created),
        'fits', (select count(*) from fits where nickname = n.nickname),
        'posts', (select count(*) from posts where nickname = n.nickname),
        'reports', coalesce((select sum(reports) from fits where nickname = n.nickname), 0),
        'banned', b.nickname is not null, 'ban_reason', b.reason) j
    from nicks n left join bans b on b.nickname = n.nickname
    where (btrim(coalesce(q, '')) = '' or n.nickname ilike qq)
      and (tab <> 'banned' or b.nickname is not null)
    order by rep desc, n.created desc limit 300) x), '[]');
end $$;

create or replace function api_admin_ban(pw text, nickname text, reason text default '', wipe boolean default false) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw); n text := btrim(coalesce(nickname, ''));
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if n = '' then return jsonb_build_object('error', '닉네임이 비어 있어요'); end if;
  insert into bans(nickname, key_hash, reason)
  values (n, coalesce((select key_hash from nicks where nicks.nickname = n), ''), left(btrim(coalesce(reason, '')), 100))
  on conflict on constraint bans_pkey do update set reason = excluded.reason, key_hash = excluded.key_hash;
  if wipe then   -- 올린 착장은 숨기고, 모집글은 지운다
    update fits set status = 'hidden' where fits.nickname = n;
    delete from posts where posts.nickname = n;
  end if;
  return '{"ok":true}';
end $$;

create or replace function api_admin_unban(pw text, nickname text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  delete from bans where bans.nickname = btrim(coalesce(api_admin_unban.nickname, ''));
  return '{"ok":true}';
end $$;

create or replace function api_admin_settings(pw text, require_approval boolean, hide_at int) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if hide_at is null or hide_at < 1 or hide_at > 50 then return jsonb_build_object('error', '자동 숨김 신고 수는 1~50 사이예요'); end if;
  update settings set require_approval = coalesce(api_admin_settings.require_approval, false), hide_at = api_admin_settings.hide_at where id = 1;
  return '{"ok":true}';
end $$;

create or replace function api_admin_suggestions(pw text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  return coalesce((select jsonb_agg(to_jsonb(s) || jsonb_build_object('ago', _ago(s.created)) order by s.id desc) from court_suggestions s), '[]');
end $$;

-- 승인(approve): 입력란에서 고친 값으로 courts 에 넣는다 / 거절(reject): 지운다
create or replace function api_admin_suggestion(pw text, sid bigint, act text, name text default '', district text default '', address text default '',
  hoops text default '', surface text default '', note text default '', lat double precision default null, lng double precision default null) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw); nm text := btrim(coalesce(name, '')); d text := btrim(coalesce(district, ''));
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if act = 'reject' then delete from court_suggestions where id = sid; return '{"ok":true}'; end if;
  if act <> 'approve' then return jsonb_build_object('error', '알 수 없는 요청이에요'); end if;
  if not exists (select 1 from court_suggestions where id = sid) then return jsonb_build_object('error', '이미 처리된 제보예요'); end if;
  if char_length(nm) < 2 or char_length(d) < 1 then return jsonb_build_object('error', '이름과 지역은 꼭 필요해요'); end if;
  if (lat is null) <> (lng is null) or (lat is not null and (lat not between 33 and 39 or lng not between 124 and 132)) then
    return jsonb_build_object('error', '좌표가 한국 밖이에요'); end if;
  insert into courts(id, name, area, address, hoops, surface, map_query, note, sort, district, lat, lng)
  values ('u' || sid, left(nm, 30), left(d, 12), left(btrim(coalesce(address, '')), 60), left(btrim(coalesce(hoops, '')), 30),
    left(btrim(coalesce(surface, '')), 10), left(nm, 30), left(btrim(coalesce(note, '')), 80), 1000 + sid, left(d, 12), lat, lng);
  delete from court_suggestions where id = sid;
  return '{"ok":true}';
end $$;

create or replace function api_admin_courts(pw text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'district', c.district, 'lat', c.lat, 'lng', c.lng,
    'user_added', c.id like 'u%' and c.id ~ '^u[0-9]+$') order by c.sort, c.id) from courts c), '[]');
end $$;

-- 코트 위치 고치기 / 이용자가 제보해 만든 코트 지우기
create or replace function api_admin_court(pw text, cid text, act text, lat double precision default null, lng double precision default null) returns jsonb
  language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if act = 'locate' then
    if (lat is null) <> (lng is null) or (lat is not null and (lat not between 33 and 39 or lng not between 124 and 132)) then
      return jsonb_build_object('error', '좌표가 한국 밖이에요'); end if;
    update courts set lat = api_admin_court.lat, lng = api_admin_court.lng where id = cid;
  elsif act = 'delete' then
    if cid !~ '^u[0-9]+$' then return jsonb_build_object('error', '기본 코트는 지울 수 없어요'); end if;
    delete from courts where id = cid;
  else return jsonb_build_object('error', '알 수 없는 요청이에요'); end if;
  return '{"ok":true}';
end $$;

create or replace function api_admin_password(pw text, new_pw text) returns jsonb language plpgsql security definer set search_path = public as $$
declare e text := _admin(pw);
begin
  if e is not null then return jsonb_build_object('error', e); end if;
  if char_length(coalesce(new_pw, '')) < 8 then return jsonb_build_object('error', '새 비밀번호는 8자 이상이에요'); end if;
  perform _admin_set_password(new_pw);
  return '{"ok":true}';
end $$;

-- 관리자가 지운 착장의 사진 파일만 Storage 에서 지울 수 있게 확인해 주는 함수 (아래 정책에서 사용)
create or replace function fits_trashed(n text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from photo_trash where name = n) $$;
revoke all on function fits_trashed(text) from public;
grant execute on function fits_trashed(text) to anon, authenticated;

-- ---------- 권한: anon 은 api_* 만 실행 ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig, p.proname from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and (p.proname like 'api\_%' or p.proname like '\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'api\_%' then execute format('grant execute on function %s to anon, authenticated', f.sig); end if;
  end loop;
end $$;

-- ---------- 사진 저장소: 공개 읽기, JPEG 600KB 이하만 업로드, 수정 불가 ----------
-- 삭제는 관리자가 지운 착장의 사진(photo_trash 에 있는 것)만 가능
do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
    values ('fits', 'fits', true, 614400, array['image/jpeg'])
    on conflict (id) do update set public = true, file_size_limit = 614400, allowed_mime_types = array['image/jpeg'];
    drop policy if exists "fits upload" on storage.objects;
    create policy "fits upload" on storage.objects for insert to anon, authenticated
      with check (bucket_id = 'fits' and name ~ '^[0-9a-f-]{36}\.jpg$');
    drop policy if exists "fits trash select" on storage.objects;
    drop policy if exists "fits trash delete" on storage.objects;
    create policy "fits trash select" on storage.objects for select to anon, authenticated
      using (bucket_id = 'fits' and public.fits_trashed(name));
    create policy "fits trash delete" on storage.objects for delete to anon, authenticated
      using (bucket_id = 'fits' and public.fits_trashed(name));
  end if;
end $$;
