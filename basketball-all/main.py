"""코트 한눈에 — 동네 농구장 혼잡도 + 인원 모집 (FastAPI + SQLite).
실행: uvicorn main:app --host 127.0.0.1 --port 8000
"""
import base64, hashlib, hmac, os, re, sqlite3, time, uuid
from collections import defaultdict, deque
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "bball.db")
CHECKIN_HOURS = 3     # 체크인 자동 만료
REPORT_MINUTES = 30   # 인원 제보 유효 시간
COND_HOURS = 2        # 현장 상태 제보 유효 시간
POST_HOURS = 12       # 경기 시각이 없는 글의 유효 시간
PLAY_GRACE_HOURS = 3  # 경기 시작 후 이 시간까지 목록에 유지
LEVELS = ["입문", "초급", "중급", "상급", "누구나"]
FORMATS = ["3vs3", "5vs5", "자유"]
HIDE_AT = 3           # 착장 글 신고 누적 시 숨김
UPLOAD_DIR = os.path.join(HERE, "static", "uploads")
os.makedirs(UPLOAD_DIR, exist_ok=True)

# 출처: 서울 한강공원 누리집(농구장 보유 공원·문의 전화), 마포구청(망원유수지체육공원), 나무위키 야외 농구장 목록
# 확인되지 않은 항목(골대 수·바닥 등)은 비워 둔다. 좌표는 확인하지 못해 쓰지 않고, 지도 검색 링크만 쓴다.
# (id, 이름, 구역, 주소/위치, 골대 수 설명, 바닥, 조명, 전화, 지도 검색어, 메모, 자치구)
COURTS = [
    ("mangwon-yusuji", "망원유수지 농구장", "마포", "마포구 월드컵로25길 190 (망원유수지체육공원)", "농구장 3면", "", "", "02-3153-9873", "망원유수지체육공원 농구장", "상시 개방 · 주차 · 화장실 · 우천·기상특보 시 사용 제한", "마포구"),
    ("hg-mangwon", "망원한강공원 농구장", "한강", "망원한강공원", "골대 4개 (풀코트 2)", "고무", "조명 있음", "02-3780-0601", "망원한강공원 농구장", "화장실 · 급수대", "마포구"),
    ("hg-yanghwa", "양화한강공원 농구장", "한강", "양화한강공원", "", "", "", "", "양화한강공원 농구장", "", "영등포구"),
    ("hg-nanji", "난지한강공원 농구장", "한강", "난지한강공원", "", "", "", "02-3780-0611", "난지한강공원 농구장", "", "마포구"),
    ("hg-ichon", "이촌한강공원 농구장", "한강", "이촌한강공원", "", "", "", "02-3780-0551", "이촌한강공원 농구장", "", "용산구"),
    ("hg-banpo", "반포한강공원 농구장", "한강", "반포한강공원", "", "아스팔트", "", "02-3780-0541", "반포한강공원 농구장", "바닥이 거칠어 부상 주의. 인근 반포종합운동장을 더 많이 이용", "서초구"),
    ("hg-jamwon", "잠원한강공원 농구장", "한강", "잠원한강공원", "", "", "", "", "잠원한강공원 농구장", "", "서초구"),
    ("hg-ttukseom", "뚝섬한강공원 농구장", "한강", "뚝섬한강공원", "골대 8개 (4개씩 2곳)", "우레탄", "", "", "뚝섬한강공원 농구장", "뚝섬역 쪽과 먼 쪽 두 곳으로 나뉨 · 장애인 전용 농구장 별도", "광진구"),
    ("hg-jamsil", "잠실한강공원 농구장", "한강", "잠실한강공원", "", "", "", "02-3708-0511", "잠실한강공원 농구장", "", "송파구"),
    ("hg-gwangnaru", "광나루한강공원 농구장", "한강", "광나루한강공원", "", "", "", "02-3780-0501", "광나루한강공원 농구장", "", "강동구"),
]
COND_TAGS = {"lights_on": "조명 켜짐", "lights_off": "조명 꺼짐", "wet": "바닥 젖음", "waiting": "대기팀 있음", "ball": "공 빌려줌"}

app = FastAPI()


def db():
    c = sqlite3.connect(DB)
    c.row_factory = sqlite3.Row
    return c


with db() as c:
    c.executescript("""
    DROP TABLE IF EXISTS courts;
    CREATE TABLE courts(id TEXT PRIMARY KEY, name TEXT, area TEXT, address TEXT, hoops TEXT,
        surface TEXT, lights TEXT, phone TEXT, map_query TEXT, note TEXT, district TEXT);
    CREATE TABLE IF NOT EXISTS checkins(id INTEGER PRIMARY KEY, court_id TEXT, nickname TEXT,
        created TEXT DEFAULT CURRENT_TIMESTAMP, out INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS reports(id INTEGER PRIMARY KEY, court_id TEXT, count INTEGER,
        created TEXT DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE IF NOT EXISTS conditions(id INTEGER PRIMARY KEY, court_id TEXT, tag TEXT,
        created TEXT DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE IF NOT EXISTS posts(id INTEGER PRIMARY KEY, court_id TEXT, nickname TEXT, title TEXT,
        when_text TEXT, need INTEGER, created TEXT DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE IF NOT EXISTS post_joins(post_id INTEGER, nickname TEXT, UNIQUE(post_id, nickname));
    CREATE TABLE IF NOT EXISTS fits(id INTEGER PRIMARY KEY, court_id TEXT DEFAULT '', nickname TEXT, shoes TEXT, shoe_size TEXT,
        top TEXT, bottom TEXT, extra TEXT, comment TEXT, grip INTEGER, photo TEXT DEFAULT '', reports INTEGER DEFAULT 0,
        created TEXT DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE IF NOT EXISTS fit_likes(fit_id INTEGER, nickname TEXT, UNIQUE(fit_id, nickname));
    CREATE TABLE IF NOT EXISTS fit_reports(fit_id INTEGER, ip TEXT, UNIQUE(fit_id, ip));
    CREATE TABLE IF NOT EXISTS nicks(nickname TEXT PRIMARY KEY, key_hash TEXT, created TEXT DEFAULT CURRENT_TIMESTAMP);
    """)
    for col in ("link TEXT DEFAULT ''", "play_at TEXT DEFAULT ''", "capacity INTEGER DEFAULT 0",
                "level TEXT DEFAULT ''", "fmt TEXT DEFAULT ''"):
        try:
            c.execute(f"ALTER TABLE posts ADD COLUMN {col}")
        except sqlite3.OperationalError:
            pass
    c.executemany("INSERT INTO courts VALUES(?,?,?,?,?,?,?,?,?,?,?)", COURTS)

# ---- 간단한 요청 제한 (IP당 쓰기 60회/분) ----
_hits = defaultdict(deque)


@app.middleware("http")
async def limit(request: Request, call_next):
    if request.method != "GET":
        ip = request.client.host if request.client else "?"
        q, now = _hits[ip], time.time()
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) >= 60:
            return JSONResponse({"detail": "요청이 너무 많아요. 잠시 후 다시 시도해 주세요"}, status_code=429)
        q.append(now)
    return await call_next(request)


def level(n):
    if n < 5:
        return {"key": "calm", "label": "한산", "hint": "여유가 있어요"}
    if n < 10:
        return {"key": "mid", "label": "보통", "hint": "5대5 가능한 인원이에요"}
    return {"key": "busy", "label": "혼잡", "hint": "대기가 있을 수 있어요"}


def court_status(c, cid):
    n_in = c.execute(
        "SELECT COUNT(*) FROM checkins WHERE court_id=? AND out=0 AND created > datetime('now', ?)",
        (cid, f"-{CHECKIN_HOURS} hours")).fetchone()[0]
    r = c.execute(
        "SELECT count, CAST((julianday('now')-julianday(created))*1440 AS INT) ago FROM reports "
        "WHERE court_id=? AND created > datetime('now', ?) ORDER BY id DESC LIMIT 1",
        (cid, f"-{REPORT_MINUTES} minutes")).fetchone()
    n_rep = r["count"] if r else None
    n = max(n_in, n_rep or 0)
    return {"checked_in": n_in, "reported": n_rep, "report_ago": r["ago"] if r else None, "people": n, **level(n)}


def conditions(c, cid):
    rows = c.execute(
        "SELECT tag, COUNT(*) n, MIN(CAST((julianday('now')-julianday(created))*1440 AS INT)) ago FROM conditions "
        "WHERE court_id=? AND created > datetime('now', ?) GROUP BY tag", (cid, f"-{COND_HOURS} hours")).fetchall()
    d = {r["tag"]: {"n": r["n"], "ago": r["ago"]} for r in rows}
    # 조명 켜짐/꺼짐은 더 최근 제보가 이긴다
    if "lights_on" in d and "lights_off" in d:
        del d["lights_on" if d["lights_on"]["ago"] > d["lights_off"]["ago"] else "lights_off"]
    return [{"tag": t, "label": COND_TAGS[t], **v} for t, v in d.items()]


OPEN_POST = ("((p.play_at != '' AND p.play_at > datetime('now', '+9 hours', ?)) "
             "OR (p.play_at = '' AND p.created > datetime('now', ?)))")


def posts_of(c, where, args):
    out = []
    q = (f"SELECT p.*, ct.name court_name, CAST((julianday('now')-julianday(p.created))*1440 AS INT) ago "
         f"FROM posts p JOIN courts ct ON ct.id=p.court_id WHERE {OPEN_POST} {where} "
         f"ORDER BY CASE WHEN p.play_at='' THEN '9999' ELSE p.play_at END, p.id")
    for p in c.execute(q, (f"-{PLAY_GRACE_HOURS} hours", f"-{POST_HOURS} hours", *args)):
        d = dict(p)
        d["joined"] = [r["nickname"] for r in c.execute("SELECT nickname FROM post_joins WHERE post_id=? ORDER BY rowid", (p["id"],))]
        d["capacity"] = d["capacity"] or (d["need"] + 1)
        out.append(d)
    return out


class Nick(BaseModel):
    nickname: str
    key: str = ""


class Report(BaseModel):
    count: int


class Cond(BaseModel):
    tag: str


class Post(BaseModel):
    nickname: str
    key: str = ""
    title: str
    play_date: str          # YYYY-MM-DD (한국 시간)
    play_time: str          # HH:MM
    capacity: int = 10      # 본인 포함 전체 인원
    fmt: str = "자유"
    level: str = "누구나"
    link: str = ""


def nick(s):
    s = s.strip()
    if not s or len(s) > 20:
        raise HTTPException(400, "닉네임을 1~20자로 입력해 주세요")
    return s


def owner(c, name, key):
    """닉네임을 처음 쓴 기기(브라우저 키)에만 묶는다. 다른 키로 같은 닉네임을 쓰면 거절."""
    name = nick(name)
    key = (key or "").strip()
    if not 16 <= len(key) <= 128:
        raise HTTPException(400, "앱을 새로고침한 뒤 다시 시도해 주세요")
    h = hashlib.sha256(key.encode()).hexdigest()
    row = c.execute("SELECT key_hash FROM nicks WHERE nickname=?", (name,)).fetchone()
    if row is None:
        c.execute("INSERT INTO nicks(nickname, key_hash) VALUES(?,?)", (name, h))
    elif not hmac.compare_digest(row["key_hash"], h):
        raise HTTPException(403, "다른 기기에서 이미 쓰는 닉네임이에요. 다른 닉네임을 정해 주세요")
    return name


@app.post("/api/nick")
def claim_nick(n: Nick):
    with db() as c:
        return {"ok": True, "nickname": owner(c, n.nickname, n.key)}


def court_or_404(c, cid):
    if not c.execute("SELECT 1 FROM courts WHERE id=?", (cid,)).fetchone():
        raise HTTPException(404, "없는 코트예요")


def static(name, media=None):
    return FileResponse(os.path.join(HERE, "static", name), media_type=media, headers={"Cache-Control": "no-cache"})


@app.get("/")
def index():
    return static("index.html")


@app.get("/manifest.webmanifest")
def manifest():
    return static("manifest.webmanifest", "application/manifest+json")


@app.get("/sw.js")
def sw():
    return static("sw.js", "text/javascript")


@app.get("/icon.svg")
def icon():
    return static("icon.svg", "image/svg+xml")


@app.get("/api/courts")
def courts():
    with db() as c:
        out = []
        for ct in c.execute("SELECT * FROM courts"):
            d = dict(ct)
            d.update(court_status(c, ct["id"]))
            d["conditions"] = conditions(c, ct["id"])
            d["open_posts"] = c.execute(
                f"SELECT COUNT(*) FROM posts p WHERE p.court_id=? AND {OPEN_POST}",
                (ct["id"], f"-{PLAY_GRACE_HOURS} hours", f"-{POST_HOURS} hours")).fetchone()[0]
            out.append(d)
        return out


def hourly(c, cid):
    """시간대(KST)별 평균 인원. 체크인 기록과 제보를 합쳐 계산, 표본이 모자라면 빈 값."""
    avg = {}
    for h, a in c.execute(
            "SELECT strftime('%H', created, '+9 hours') h, AVG(count) a FROM reports WHERE court_id=? GROUP BY h", (cid,)):
        avg[int(h)] = a
    for h, a in c.execute(
            "SELECT h, AVG(n) FROM (SELECT strftime('%H', created, '+9 hours') h, date(created, '+9 hours') d, COUNT(*) n "
            "FROM checkins WHERE court_id=? GROUP BY h, d) GROUP BY h", (cid,)):
        avg[int(h)] = max(avg.get(int(h), 0), a)
    samples = c.execute("SELECT (SELECT COUNT(*) FROM reports WHERE court_id=?)+(SELECT COUNT(*) FROM checkins WHERE court_id=?)", (cid, cid)).fetchone()[0]
    return {"samples": samples, "hours": [round(avg.get(h, 0), 1) for h in range(24)]}


@app.get("/api/courts/{cid}")
def court(cid: str):
    with db() as c:
        court_or_404(c, cid)
        d = dict(c.execute("SELECT * FROM courts WHERE id=?", (cid,)).fetchone())
        d.update(court_status(c, cid))
        d["conditions"] = conditions(c, cid)
        d["people_list"] = [r["nickname"] for r in c.execute(
            "SELECT nickname FROM checkins WHERE court_id=? AND out=0 AND created > datetime('now', ?) ORDER BY id",
            (cid, f"-{CHECKIN_HOURS} hours"))]
        d["posts"] = posts_of(c, "AND p.court_id=?", (cid,))
        d["hourly"] = hourly(c, cid)
        d["top_shoes"] = [dict(r) for r in c.execute(
            "SELECT MAX(shoes) shoes, COUNT(*) n, ROUND(AVG(NULLIF(grip,0)),1) grip FROM fits "
            "WHERE court_id=? AND reports<? GROUP BY lower(trim(shoes)) ORDER BY n DESC, MAX(id) DESC LIMIT 3", (cid, HIDE_AT))]
        return d


@app.get("/api/posts")
def feed():
    with db() as c:
        return posts_of(c, "", ())


@app.get("/api/meta")
def meta():
    with db() as c:
        now = c.execute("SELECT datetime('now', '+9 hours')").fetchone()[0]
    return {"levels": LEVELS, "formats": FORMATS, "now_kst": now}


@app.get("/api/me")
def me(nickname: str):
    with db() as c:
        ci = c.execute(
            "SELECT k.court_id, ct.name, CAST((julianday('now')-julianday(k.created))*1440 AS INT) ago FROM checkins k "
            "JOIN courts ct ON ct.id=k.court_id WHERE k.nickname=? AND k.out=0 AND k.created > datetime('now', ?) "
            "ORDER BY k.id DESC LIMIT 1", (nickname.strip(), f"-{CHECKIN_HOURS} hours")).fetchone()
        mine = [p for p in posts_of(c, "", ()) if nickname.strip() in p["joined"]]
        return {"checkin": dict(ci) if ci else None, "posts": mine}


@app.post("/api/courts/{cid}/checkin")
def checkin(cid: str, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        court_or_404(c, cid)
        c.execute("UPDATE checkins SET out=1 WHERE nickname=? AND out=0", (name,))  # 다른 코트 체크인은 자동 해제
        c.execute("INSERT INTO checkins(court_id,nickname) VALUES(?,?)", (cid, name))
    return {"ok": True}


@app.post("/api/courts/{cid}/checkout")
def checkout(cid: str, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        c.execute("UPDATE checkins SET out=1 WHERE court_id=? AND nickname=? AND out=0", (cid, name))
    return {"ok": True}


@app.post("/api/courts/{cid}/report")
def report(cid: str, r: Report):
    if not 0 <= r.count <= 40:
        raise HTTPException(400, "인원은 0~40명 사이로 입력해 주세요")
    with db() as c:
        court_or_404(c, cid)
        c.execute("INSERT INTO reports(court_id,count) VALUES(?,?)", (cid, r.count))
    return {"ok": True}


@app.post("/api/courts/{cid}/condition")
def condition(cid: str, cd: Cond):
    if cd.tag not in COND_TAGS:
        raise HTTPException(400, "알 수 없는 상태예요")
    with db() as c:
        court_or_404(c, cid)
        c.execute("INSERT INTO conditions(court_id,tag) VALUES(?,?)", (cid, cd.tag))
    return {"ok": True}


@app.post("/api/courts/{cid}/posts")
def new_post(cid: str, p: Post):
    name = nick(p.nickname)
    title = p.title.strip()
    link = p.link.strip()
    if not title or len(title) > 60:
        raise HTTPException(400, "제목을 1~60자로 입력해 주세요")
    if not 2 <= p.capacity <= 30:
        raise HTTPException(400, "전체 인원은 2~30명이에요")
    if p.fmt not in FORMATS or p.level not in LEVELS:
        raise HTTPException(400, "형식 또는 레벨이 올바르지 않아요")
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", p.play_date) or not re.match(r"^([01]\d|2[0-3]):[0-5]\d$", p.play_time):
        raise HTTPException(400, "날짜와 시간을 확인해 주세요")
    if link and not re.match(r"^https://[^\s]{3,200}$", link):
        raise HTTPException(400, "오픈채팅 링크는 https:// 로 시작해야 해요")
    play_at = f"{p.play_date} {p.play_time}"
    with db() as c:
        owner(c, name, p.key)
        court_or_404(c, cid)
        ok = c.execute("SELECT ? > datetime('now', '+9 hours', '-30 minutes') AND ? < datetime('now', '+9 hours', '+15 days')",
                       (play_at, play_at)).fetchone()[0]
        if not ok:
            raise HTTPException(400, "경기 시간은 지금부터 14일 안으로 정해 주세요")
        cur = c.execute("INSERT INTO posts(court_id,nickname,title,when_text,need,link,play_at,capacity,level,fmt) VALUES(?,?,?,?,?,?,?,?,?,?)",
                        (cid, name, title, p.play_time, p.capacity - 1, link, play_at, p.capacity, p.level, p.fmt))
        c.execute("INSERT INTO post_joins VALUES(?,?)", (cur.lastrowid, name))
    return {"ok": True}


@app.post("/api/posts/{pid}/join")
def join_post(pid: int, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        row = c.execute("SELECT capacity, need FROM posts WHERE id=?", (pid,)).fetchone()
        if not row:
            raise HTTPException(404)
        cap = row["capacity"] or row["need"] + 1
        joined = [r["nickname"] for r in c.execute("SELECT nickname FROM post_joins WHERE post_id=?", (pid,))]
        if name not in joined and len(joined) >= cap:
            raise HTTPException(400, "이미 마감된 게임이에요")
        c.execute("INSERT OR IGNORE INTO post_joins VALUES(?,?)", (pid, name))
    return {"ok": True}


@app.post("/api/posts/{pid}/leave")
def leave_post(pid: int, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        c.execute("DELETE FROM post_joins WHERE post_id=? AND nickname=?", (pid, name))
    return {"ok": True}


@app.post("/api/posts/{pid}/delete")
def delete_post(pid: int, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        c.execute("DELETE FROM posts WHERE id=? AND nickname=?", (pid, name))
        c.execute("DELETE FROM post_joins WHERE post_id NOT IN (SELECT id FROM posts)")
    return {"ok": True}


# ---------------- 착장(신발·복장) ----------------
app.mount("/img", StaticFiles(directory=os.path.join(HERE, "static", "img")), name="img")
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


class Fit(BaseModel):
    nickname: str
    key: str = ""
    court_id: str = ""
    shoes: str
    shoe_size: str = ""
    top: str = ""
    bottom: str = ""
    extra: str = ""
    comment: str = ""
    grip: int = 0
    photo: str = ""  # data:image/jpeg;base64,... (클라이언트에서 축소·재인코딩)


def fits_of(c, where, args, limit=50):
    q = ("SELECT f.*, COALESCE(ct.name,'') court_name, CAST((julianday('now')-julianday(f.created))*1440 AS INT) ago, "
         "(SELECT COUNT(*) FROM fit_likes l WHERE l.fit_id=f.id) likes FROM fits f LEFT JOIN courts ct ON ct.id=f.court_id "
         f"WHERE f.reports<? {where} ORDER BY f.id DESC LIMIT ?")
    out = []
    for r in c.execute(q, (HIDE_AT, *args, limit)):
        d = dict(r)
        d["liked_by"] = [x["nickname"] for x in c.execute("SELECT nickname FROM fit_likes WHERE fit_id=?", (r["id"],))]
        out.append(d)
    return out


@app.get("/api/fits")
def fits(court_id: str = ""):
    with db() as c:
        return fits_of(c, "AND f.court_id=?" if court_id else "", (court_id,) if court_id else ())


@app.post("/api/fits")
def new_fit(f: Fit):
    name = nick(f.nickname)
    shoes = f.shoes.strip()
    if not shoes or len(shoes) > 50:
        raise HTTPException(400, "신발 이름을 1~50자로 입력해 주세요")
    if not 0 <= f.grip <= 5:
        raise HTTPException(400, "접지력은 1~5점이에요")
    clip = lambda s, n: s.strip()[:n]
    with db() as c:  # 사진을 저장하기 전에 닉네임 주인부터 확인
        owner(c, name, f.key)
    photo = ""
    if f.photo:
        m = re.match(r"^data:image/jpeg;base64,([A-Za-z0-9+/=]+)$", f.photo)
        if not m or len(f.photo) > 900_000:
            raise HTTPException(400, "사진은 JPEG만, 용량이 너무 크면 올릴 수 없습니다")
        raw = base64.b64decode(m.group(1))
        if raw[:3] != b"\xff\xd8\xff":
            raise HTTPException(400, "올바른 사진 파일이 아닙니다")
        fn = uuid.uuid4().hex + ".jpg"
        with open(os.path.join(UPLOAD_DIR, fn), "wb") as fh:
            fh.write(raw)
        photo = "uploads/" + fn
    with db() as c:
        if f.court_id:
            court_or_404(c, f.court_id)
        c.execute("INSERT INTO fits(court_id,nickname,shoes,shoe_size,top,bottom,extra,comment,grip,photo) VALUES(?,?,?,?,?,?,?,?,?,?)",
                  (f.court_id, name, clip(shoes, 50), clip(f.shoe_size, 12), clip(f.top, 40), clip(f.bottom, 40),
                   clip(f.extra, 60), clip(f.comment, 120), f.grip, photo))
    return {"ok": True}


@app.post("/api/fits/{fid}/like")
def like_fit(fid: int, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        if c.execute("SELECT 1 FROM fit_likes WHERE fit_id=? AND nickname=?", (fid, name)).fetchone():
            c.execute("DELETE FROM fit_likes WHERE fit_id=? AND nickname=?", (fid, name))
        else:
            c.execute("INSERT INTO fit_likes VALUES(?,?)", (fid, name))
    return {"ok": True}


@app.post("/api/fits/{fid}/report")
def report_fit(fid: int, request: Request):
    ip = request.client.host if request.client else "?"
    with db() as c:
        try:
            c.execute("INSERT INTO fit_reports VALUES(?,?)", (fid, ip))
        except sqlite3.IntegrityError:
            return {"ok": True}
        c.execute("UPDATE fits SET reports=reports+1 WHERE id=?", (fid,))
    return {"ok": True}


@app.post("/api/fits/{fid}/delete")
def delete_fit(fid: int, n: Nick):
    with db() as c:
        name = owner(c, n.nickname, n.key)
        row = c.execute("SELECT photo FROM fits WHERE id=? AND nickname=?", (fid, name)).fetchone()
        if row:
            c.execute("DELETE FROM fits WHERE id=?", (fid,))
            if row["photo"]:
                try:
                    os.remove(os.path.join(HERE, "static", row["photo"]))
                except OSError:
                    pass
    return {"ok": True}


@app.get("/api/me/fits")
def my_fits(nickname: str):
    with db() as c:
        return fits_of(c, "AND f.nickname=?", (nickname.strip(),))
