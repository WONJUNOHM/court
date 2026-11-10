"""static/ → docs/ : GitHub Pages 에 올라가는 웹앱을 만든다.
기본: Supabase 에 저장하는 실제 서비스판.  python3 demo/build.py
체험판(브라우저에만 저장): python3 demo/build.py --demo [출력폴더]
"""
import json, os, shutil, sys

SUPABASE_URL = 'https://hplueubmmzvytmozxmgf.supabase.co'
SUPABASE_KEY = 'sb_publishable_WciyhYis0lISAPIpySi-aQ_JjesGQsO'   # 공개용 키 (표는 RLS 로 막혀 있음)

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
args = [a for a in sys.argv[1:] if not a.startswith('--')]
demo = '--demo' in sys.argv
out = args[0] if args else os.path.join(root, 'docs')
shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
for f in ('manifest.webmanifest', 'sw.js', 'icon.svg'):
    shutil.copy(os.path.join(root, 'static', f), out)
shutil.copytree(os.path.join(root, 'static', 'img'), os.path.join(out, 'img'))
h = open(os.path.join(root, 'static', 'index.html'), encoding='utf-8').read()
if demo:
    courts = json.load(open(os.path.join(root, 'demo', 'courts.json'), encoding='utf-8'))
    backend = open(os.path.join(root, 'demo', 'demo-backend.js'), encoding='utf-8').read().replace('__COURTS__', json.dumps(courts, ensure_ascii=False))
    css = '.demo{background:#17191d;color:#fff;font-size:12.5px;line-height:1.5;padding:9px 16px;display:flex;gap:10px;align-items:center}.demo span{flex:1}.demo button{color:#ffb59a;font-weight:700;text-decoration:underline;text-underline-offset:3px;white-space:nowrap}'
    h = h.replace('</style>', css + '</style>', 1)
    h = h.replace('<div class="app">', '<div class="app"><div class="demo"><span>체험판이에요. 입력한 내용은 이 브라우저에만 저장돼요.</span><button onclick="if(confirm(\'처음 상태로 되돌릴까요?\'))__resetDemo()">초기화</button></div>', 1)
else:
    backend = open(os.path.join(root, 'demo', 'supabase-backend.js'), encoding='utf-8').read() \
        .replace('__SUPABASE_URL__', SUPABASE_URL).replace('__SUPABASE_KEY__', SUPABASE_KEY)
i = h.index('<script>')
h = h[:i] + '<script>\n' + backend + '\n</script>\n' + h[i:]
open(os.path.join(out, 'index.html'), 'w', encoding='utf-8').write(h)
print('built', 'demo' if demo else 'supabase', out)
