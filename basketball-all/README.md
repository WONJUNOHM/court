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

## GitHub Pages 데모
`docs/` 폴더는 서버 없이 브라우저만으로 도는 체험판입니다 (`python3 demo/build.py`로 `static/`에서 다시 만듭니다).
`main`에 푸시하면 `.github/workflows/pages.yml`이 자동으로 배포합니다 (Settings → Pages 의 Source는 **GitHub Actions**). 데이터는 각자의 브라우저에만 저장됩니다.
