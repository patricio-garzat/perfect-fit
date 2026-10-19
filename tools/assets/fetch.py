# Downloads the Poly Haven (CC0) sources into assets-src/polyhaven/ (see ASSET_SOURCES.md).
#   python3 tools/assets/fetch.py            (from the PerfectFit folder: everything the game uses)
#   python3 tools/assets/fetch.py <outroot> <model|tex|hdri> <id>...
import json, sys, os, hashlib, urllib.request
UA={'User-Agent':'BluBerGames-PerfectFit/0.1 (asset download for game prototype)'}
def op(u): return urllib.request.urlopen(urllib.request.Request(u, headers=UA))
# usage: ph_dl.py <outroot> <kind:model|tex|hdri> <id>...
if len(sys.argv) == 1:
    root = 'assets-src/polyhaven'
    jobs = [('models', 'model', ['mid_century_lounge_chair', 'modern_coffee_table_01', 'coffee_table_round_01', 'wooden_display_shelves_01',
                                 'vintage_wooden_drawer_01', 'potted_plant_04', 'calathea_orbifolia_01', 'ceramic_vase_01']),
            ('tex', 'tex', ['wood_floor', 'white_plaster_02', 'rough_linen', 'wool_boucle', 'white_oak_veneer']),
            ('hdri', 'hdri', ['white_home_studio'])]
    for sub, k, ids in jobs: os.system(f'{sys.executable} -I {__file__} {root}/{sub} {k} ' + ' '.join(ids))
    sys.exit(0)
out, kind, ids = sys.argv[1], sys.argv[2], sys.argv[3:]
def get(url, path, md5=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = op(url).read()
    if md5 and hashlib.md5(data).hexdigest() != md5: raise SystemExit('md5 mismatch ' + url)
    open(path, 'wb').write(data); return len(data)
log = []
for a in ids:
    files = json.load(op(f'https://api.polyhaven.com/files/{a}'))
    info = json.load(op(f'https://api.polyhaven.com/info/{a}'))
    d = os.path.join(out, a); total = 0
    if kind == 'model':
        e = files['usd']['1k']['usd']
        total += get(e['url'], os.path.join(d, os.path.basename(e['url'])), e['md5'])
        for rel, v in e.get('include', {}).items(): total += get(v['url'], os.path.join(d, rel), v['md5'])
        # jpg normal map (USD bundle ships EXR normals)
        g = files['gltf']['1k']['gltf']['include']
        for rel, v in g.items():
            if 'nor_gl' in rel: total += get(v['url'], os.path.join(d, 'jpg', os.path.basename(rel)), v['md5'])
    elif kind == 'tex':
        for m in ['Diffuse', 'nor_gl', 'Rough']:
            v = files[m]['1k']['jpg']; total += get(v['url'], os.path.join(d, os.path.basename(v['url'])), v['md5'])
    elif kind == 'hdri':
        v = files['hdri']['1k']['hdr']; total += get(v['url'], os.path.join(d, os.path.basename(v['url'])), v['md5'])
    url = f'https://polyhaven.com/a/{a}'
    log.append({'id': a, 'name': info.get('name'), 'authors': list(info.get('authors', {}).keys()), 'url': url, 'bytes': total})
    print(a, round(total/1e6, 2), 'MB', flush=True)
json.dump(log, open(os.path.join(out, f'_log_{kind}.json'), 'w'), indent=1)
