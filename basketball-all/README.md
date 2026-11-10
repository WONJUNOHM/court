# 코트 한눈에

동네 농구장(망원유수지·한강공원 농구장)의 혼잡도 확인, 게임 모집, 착장(신발·복장) 기록 앱.
FastAPI + SQLite + 바닐라 JS (빌드 과정 없음).

## 실행

    pip install -r requirements.txt
    uvicorn main:app --host 0.0.0.0 --port 8000

`bball.db`(SQLite)는 처음 실행할 때 자동으로 만들어집니다. 업로드 사진은 `static/uploads/`에 저장됩니다.

## 알아둘 점
- 로그인이 없고 닉네임만 씁니다. 닉네임은 처음 쓴 기기(브라우저에 저장된 비밀 키)에 묶이므로, 다른 사람이 같은 닉네임으로 글을 지우거나 체크인할 수 없습니다. 브라우저 데이터를 지우면 그 닉네임은 다시 쓸 수 없습니다.
- 일부 호스팅(Render 등 무료 플랜)은 디스크가 초기화되므로 DB와 업로드 폴더에 영구 디스크가 필요합니다.
- 코트 정보(`main.py`의 `COURTS`)는 공개 자료 기준이며 비어 있는 항목은 확인되지 않은 정보입니다.
- 사진은 모두 CC0이며 출처는 `static/img/credits.json`에 있습니다.

## 실제 서비스 (GitHub Pages + Supabase)
주소: https://hangangcourt.vercel.app (Vercel, `basketball-all/docs` 배포) · 예전 주소 https://wonjunohm.github.io/court/ 도 동작

- 화면은 `docs/`(GitHub Pages), 데이터는 Supabase(서울) 프로젝트 `court`에 저장되어 모든 이용자가 같은 정보를 봅니다.
- DB 설정은 `supabase/schema.sql` 하나에 있습니다. Supabase → SQL Editor 에 붙여넣고 Run (여러 번 실행해도 안전).
  표는 RLS로 막혀 있고, 앱은 `api_*` 함수만 호출합니다. 규칙(검증·만료·닉네임 주인 확인)은 함수 안에 있습니다.
- 사진은 Storage `fits` 버킷(공개 읽기, JPEG 600KB 이하 업로드만)에 저장됩니다.
- `static/`을 고친 뒤 `python3 demo/build.py`로 `docs/`를 다시 만들고 푸시하면 자동 배포됩니다.
  브라우저에만 저장되는 체험판이 필요하면 `python3 demo/build.py --demo 출력폴더`.
- `main.py`(FastAPI + SQLite)는 내 컴퓨터에서 개발·테스트할 때 쓰는 서버입니다.
