"""Verified Godot builds, immutable tag releases, and a complete versioned Pages site."""
import argparse
from contextlib import contextmanager
from content_build import prepared_project
import base64
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

TESTS = ('validate_foundation test_round test_controls test_asset_pack test_feedback '
         'test_motion test_defeat test_boss_actions test_ambient test_profile test_shell test_pack_selection').split()
REPO = 'madmazoku/balcony-barrage'
SITE = 'https://madmazoku.github.io/balcony-barrage'
TAG = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([A-Za-z0-9_-]+))?\Z')


def version(tag):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError('Expected x.y.z or x.y.z-[A-Za-z0-9_-]+; version numbers cannot have leading zeroes.')
    if any(int(n) > 65535 for n in match.groups()[:3]):
        raise ValueError('Version components exceed Windows limits.')
    return match


def run(*args, capture=False, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip() if capture else subprocess.run(args, check=True, **kwargs)


def gh(*args, capture=False):
    return run('gh', *args, capture=capture)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def godot(*args):
    result = subprocess.run([os.environ.get('GODOT', 'godot'), '--headless', '--path', os.environ.get('GODOT_PROJECT_PATH', '.'), *args],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
    if result.returncode or 'SCRIPT ERROR:' in result.stdout or re.search(r'(^|\n)ERROR:', result.stdout):
        print(result.stdout)
        raise RuntimeError('Godot import, check or export failed.')
    print(result.stdout[-1200:])


def checks():
    godot('--editor', '--import')
    for test in TESTS:
        godot('--script', f'res://tools/{test}.gd', '--quit-after', '600')
    run('python', '-m', 'unittest', 'discover', '-s', 'tools', '-p', 'test_release.py')


def replace_setting(path, key, literal):
    text = path.read_text(encoding='utf-8')
    line = key + '=' + literal
    text, count = re.subn(r'^' + re.escape(key) + r'\s*=.*$', lambda _: line, text, flags=re.M)
    if count != 1:
        raise ValueError(f'Missing or repeated setting: {key}')
    path.write_text(text, encoding='utf-8')


def stamp(tag, number):
    match = version(tag)
    if not 0 < number <= 2100000000:
        raise ValueError('Invalid Android version code.')
    replace_setting(Path('project.godot'), 'config/version', json.dumps(tag))
    path = Path('export_presets.cfg')
    replace_setting(path, 'version/name', json.dumps(tag))
    replace_setting(path, 'version/code', str(number))
    numeric = '.'.join(match.groups()[:3]) + '.0'
    replace_setting(path, 'application/file_version', json.dumps(numeric))
    replace_setting(path, 'application/product_version', json.dumps(numeric))


def signing():
    target = Path(os.environ['RUNNER_TEMP']) / 'android-release.p12'
    if os.environ.get('RELEASE_TAG'):
        target.write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'], validate=True))
        password = os.environ['ANDROID_KEYSTORE_PASSWORD']
        alias = os.environ['ANDROID_KEY_ALIAS']
    else:
        # Candidate builds never receive the repository's signing credentials.
        password, alias = 'candidate-only-password', 'candidate'
        env = dict(os.environ, CANDIDATE_PASSWORD=password)
        run('keytool', '-genkeypair', '-storetype', 'PKCS12', '-keystore', str(target),
            '-storepass:env', 'CANDIDATE_PASSWORD', '-keypass:env', 'CANDIDATE_PASSWORD',
            '-alias', alias, '-keyalg', 'RSA', '-keysize', '2048', '-validity', '30',
            '-dname', 'CN=Disposable CI Candidate', env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.environ.update(GODOT_ANDROID_KEYSTORE_RELEASE_PATH=str(target),
                      GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=password,
                      GODOT_ANDROID_KEYSTORE_RELEASE_USER=alias)
    return target


def configure_android():
    root = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'godot'
    path = root / 'editor_settings-4.7.tres'
    if not path.exists():
        raise RuntimeError('Import with Godot 4.7.2 before configuring Android.')
    text = path.read_text(encoding='utf-8')
    for key, value in {'export/android/android_sdk_path': os.environ['ANDROID_HOME'],
                       'export/android/java_sdk_path': os.environ['JAVA_HOME']}.items():
        pattern = r'^' + re.escape(key) + r'\s*=.*$'
        text = re.sub(pattern, '', text, flags=re.M)
        text = text.replace('[resource]', '[resource]\n' + key + ' = ' + json.dumps(value), 1)
    path.write_text(text, encoding='utf-8')


def zip_folder(source, output):
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(source.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(source).as_posix())


@contextmanager
def export_content(flavor):
    root = Path.cwd()
    previous = os.environ.get('GODOT_PROJECT_PATH')
    with prepared_project(root, flavor) as (project, ids):
        try:
            os.environ['GODOT_PROJECT_PATH'] = str(project)
            if project != root:
                godot('--editor', '--import')
            yield ids
        finally:
            if previous is None: os.environ.pop('GODOT_PROJECT_PATH', None)
            else: os.environ['GODOT_PROJECT_PATH'] = previous


def audit_apk_content(archive, ids):
    # Godot 4.7 APKs store individual assets with sparse-PCK metadata, not a .pck file.
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        if 'assets/assets.sparsepck' not in names:
            raise ValueError('Expected Godot 4.7 Android sparse-PCK metadata.')
        catalog = json.loads(z.read('assets/config/pack_catalog.json'))
        prefix = 'assets/assets/packs/'
        found = {name[len(prefix):].split('/', 1)[0] for name in names if name.startswith(prefix)}
        listed = [entry['id'] for entry in catalog['packs']]
        if found != set(ids) or sorted(listed) != sorted(ids) or catalog['default_pack'] not in ids:
            raise ValueError('Android assets/catalog do not match the selected content profile.')
    print('EXPORTED_CONTENT_OK APK ' + ','.join(sorted(found)))


def audit_content(archive, ids):
    if archive.suffix == '.apk':
        audit_apk_content(archive, ids)
        return
    # Web PCK or embedded Windows PCK, mounted in an empty project.
    with tempfile.TemporaryDirectory(prefix='balcony-audit-') as temp:
        root = Path(temp)
        resource_pack = archive.resolve()
        (root / 'project.godot').write_text('config_version=5\n')
        shutil.copyfile('tools/audit_export.gd', root / 'audit.gd')
        result = subprocess.run([os.environ.get('GODOT', 'godot'), '--headless', '--path', str(root),
                                 '--script', 'res://audit.gd', '--', str(resource_pack), ','.join(ids)],
                                capture_output=True, text=True, encoding='utf-8', errors='replace')
        print(result.stdout[-1200:])
        if result.returncode or 'EXPORTED_CONTENT_OK' not in result.stdout:
            raise RuntimeError('Export content audit failed: ' + result.stderr[-1200:])


def export_web(output):
    output.mkdir(parents=True, exist_ok=True)
    godot('--export-release', 'Web', str((output / 'index.html').resolve()))
    for name in ['index.html', 'index.js', 'index.wasm', 'index.pck']:
        if not (output / name).is_file() or not (output / name).stat().st_size:
            raise RuntimeError('Incomplete Web export: ' + name)
    v = re.search(r'^config/version="([^"]+)"', Path('project.godot').read_text(), re.M)[1]
    (output / 'version.txt').write_text(v + '\n')
    (output / 'commit.txt').write_text(run('git', 'rev-parse', 'HEAD', capture=True) + '\n')
    (output / '.nojekyll').touch()
    shutil.copyfile('licenses/Godot.txt', output / 'GODOT_LICENSE.txt')


def build(native, content=None):
    from content_build import select_catalog
    tag = os.environ.get('RELEASE_TAG', '')
    flavor = content or ('release' if tag else 'debug')
    if tag and flavor != 'release': raise ValueError('Published tags require release content.')
    # Fail closed before changing version files or restoring signing credentials.
    select_catalog(Path.cwd(), flavor)
    if tag:
        stamp(tag, int(os.environ['GITHUB_RUN_NUMBER']))
    Path('builds').mkdir(exist_ok=True)
    Path('builds/.gdignore').touch()
    checks()
    key = None
    if native:
        configure_android()
        key = signing()
    try:
        with export_content(flavor) as ids:
            export_web(Path('builds/web'))
            audit_content(Path('builds/web/index.pck'), ids)
            if not native: return
            Path('builds/windows').mkdir(parents=True, exist_ok=True)
            Path('builds/android').mkdir(parents=True, exist_ok=True)
            godot('--export-release', 'Windows', str(Path('builds/windows/balcony-barrage.exe').resolve()))
            audit_content(Path('builds/windows/balcony-barrage.exe'), ids)
            shutil.copyfile('licenses/Godot.txt', 'builds/windows/GODOT_LICENSE.txt')
            godot('--export-release', 'Android', str(Path('builds/android/balcony-barrage.apk').resolve()))
            audit_content(Path('builds/android/balcony-barrage.apk'), ids)
            sdk = Path(os.environ['ANDROID_HOME']) / 'build-tools/36.0.0'
            run(str(sdk / 'apksigner'), 'verify', '--verbose', '--print-certs', 'builds/android/balcony-barrage.apk')
            run(str(sdk / 'aapt'), 'dump', 'badging', 'builds/android/balcony-barrage.apk')
    finally:
        if key is not None: key.unlink(missing_ok=True)
    label = tag or 'candidate'
    out = Path('builds/release'); out.mkdir(parents=True, exist_ok=True)
    zip_folder(Path('builds/windows'), out / f'balcony-barrage-{label}-windows-x86_64.zip')
    zip_folder(Path('builds/web'), out / f'balcony-barrage-{label}-web.zip')
    shutil.copyfile('builds/android/balcony-barrage.apk', out / f'balcony-barrage-{label}-android.apk')
    metadata = {'schema': 1, 'tag': label, 'commit': run('git', 'rev-parse', 'HEAD', capture=True),
                'godot': '4.7.2', 'content_profile': flavor, 'packs': ids,
                'android_version_code': int(os.environ.get('GITHUB_RUN_NUMBER', '1'))}
    (out / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n')
    names = ['release.json', f'balcony-barrage-{label}-windows-x86_64.zip',
             f'balcony-barrage-{label}-web.zip', f'balcony-barrage-{label}-android.apk']
    (out / 'SHA256SUMS.txt').write_text(''.join(f'{digest(out / name)}  {name}\n' for name in sorted(names)))


def publish(tag):
    version(tag)
    out = Path('builds/release')
    required = {'release.json', 'SHA256SUMS.txt', f'balcony-barrage-{tag}-windows-x86_64.zip',
                f'balcony-barrage-{tag}-android.apk', f'balcony-barrage-{tag}-web.zip'}
    if not required.issubset(p.name for p in out.iterdir()):
        raise ValueError('Release requires Windows, Android, Web, metadata and checksums.')
    sums = dict(line.split('  ', 1)[::-1] for line in (out / 'SHA256SUMS.txt').read_text().splitlines())
    for name in required - {'SHA256SUMS.txt'}:
        if sums.get(name) != digest(out / name): raise ValueError('Build checksum mismatch.')
    current = json.loads((out / 'release.json').read_text())
    if current['tag'] != tag or current['commit'] != run('git', 'rev-parse', 'HEAD', capture=True):
        raise ValueError('Build metadata does not match the tag checkout.')
    if current.get('content_profile') != 'release':
        raise ValueError('Debug content cannot be published as a new release.')
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', REPO, '--json', 'isDraft,assets'], capture_output=True, text=True)
    if existing.returncode == 0 and not json.loads(existing.stdout)['isDraft']:
        if not required.issubset(a['name'] for a in json.loads(existing.stdout)['assets']):
            raise ValueError('Published release is incomplete; refusing to silently replace it.')
        # Published artifacts are immutable. A retry only rebuilds the Pages catalog.
        with tempfile.TemporaryDirectory() as temp:
            gh('release', 'download', tag, '--repo', REPO, '--pattern', 'release.json', '--dir', temp)
            old = json.loads((Path(temp) / 'release.json').read_text())
            if old['commit'] != run('git', 'rev-parse', 'HEAD', capture=True) or old['tag'] != tag:
                raise ValueError('Existing release belongs to another commit.')
        return
    notes = out / 'notes.md'
    notes.write_text(f'First downloadable test builds / тестовый выпуск.\n\n'
                     f'[Играть в {tag}]({SITE}/releases/{tag}/) · [Все версии]({SITE}/releases/)\n\n'
                     'Windows: распаковать ZIP и открыть balcony-barrage.exe. Android: установить APK. '
                     'Web ZIP: запуск через HTTP/HTTPS сервер.\n\n'
                     'Меню и сохранение готовы. Звук, окончательный баланс и физическая проверка Android ещё впереди.\n', encoding='utf-8')
    if existing.returncode:
        gh('release', 'create', tag, '--repo', REPO, '--verify-tag', '--draft', '--title', tag, '--notes-file', str(notes))
    files = [str(out / name) for name in sorted(required)]
    gh('release', 'upload', tag, *files, '--repo', REPO, '--clobber')
    latest = not bool(version(tag)[4])
    if latest:
        published = json.loads(gh('release', 'list', '--repo', REPO, '--limit', '1000', '--json', 'tagName,isPrerelease,isDraft', capture=True))
        for item in published:
            try: older = version(item['tagName'])
            except ValueError: continue
            if not item['isDraft'] and not item['isPrerelease'] and tuple(map(int, older.groups()[:3])) > tuple(map(int, version(tag).groups()[:3])):
                latest = False
    gh('release', 'edit', tag, '--repo', REPO, '--draft=false', '--prerelease=' + str(bool(version(tag)[4])).lower(),
       '--latest=' + str(latest).lower())


def extract_web(archive, destination):
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            parts = item.filename.replace('\\', '/').split('/')
            if item.filename.startswith(('/', '\\')) or ':' in item.filename or '..' in parts or (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe Web archive entry.')
        if sum(i.file_size for i in z.infolist()) > 200 * 1024 * 1024:
            raise ValueError('Web archive exceeds size budget.')
        if not {'index.html', 'index.js', 'index.wasm', 'index.pck'}.issubset(z.namelist()):
            raise ValueError('Incomplete archived Web build.')
        z.extractall(destination)


def site():
    dest = Path('builds/site')
    shutil.copytree('builds/web', dest, dirs_exist_ok=True)
    catalog = []
    releases = json.loads(gh('api', f'repos/{REPO}/releases?per_page=100', '--paginate', '--slurp', capture=True))
    for release in [r for page in releases for r in page if not r['draft']]:
        tag = release['tag_name']
        try: version(tag)
        except ValueError: continue
        names = {a['name'] for a in release['assets']}
        web = f'balcony-barrage-{tag}-web.zip'
        if not {'release.json', 'SHA256SUMS.txt', web}.issubset(names): continue
        with tempfile.TemporaryDirectory() as temp:
            for name in ['release.json', 'SHA256SUMS.txt', web]:
                gh('release', 'download', tag, '--repo', REPO, '--pattern', name, '--dir', temp)
            root = Path(temp)
            sums = dict(line.split('  ', 1)[::-1] for line in (root / 'SHA256SUMS.txt').read_text().splitlines())
            for name in ['release.json', web]:
                if sums.get(name) != digest(root / name): raise ValueError('Release checksum mismatch.')
            metadata = json.loads((root / 'release.json').read_text())
            if metadata['tag'] != tag or not re.fullmatch(r'[0-9a-f]{40}', metadata['commit']):
                raise ValueError('Invalid release metadata.')
            target = dest / 'releases' / tag
            target.mkdir(parents=True, exist_ok=True)
            extract_web(root / web, target)
            if (target / 'version.txt').read_text().strip() != tag or (target / 'commit.txt').read_text().strip() != metadata['commit']:
                raise ValueError('Archived game does not match release metadata.')
        catalog.append((tag, release['html_url']))
    archive = dest / 'releases'; archive.mkdir(exist_ok=True)
    links = ''.join(f'<li><a href="{html.escape(t)}/">Играть: {html.escape(t)}</a> · <a href="{html.escape(u)}">Скачать</a></li>' for t, u in catalog)
    (archive / 'index.html').write_text('<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
                                      '<title>Balcony Barrage — версии</title><style>body{max-width:850px;margin:4rem auto;padding:1rem;background:#241a16;color:#fff2d8;font:20px system-ui}a{color:#eac37d}li{margin:1rem 0}</style>'
                                      '<h1>Balcony Barrage — версии</h1><p><a href="../">Текущая принятая версия</a></p><ul>' + links + '</ul></html>', encoding='utf-8')
    if sum(p.stat().st_size for p in dest.rglob('*') if p.is_file()) > 950 * 1024 * 1024:
        raise ValueError('Pages exceeds its size budget; no old versions were deleted.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['validate-tag', 'check', 'build', 'web', 'site', 'publish'])
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--content', choices=['debug', 'release'])
    args = parser.parse_args()
    if args.command == 'validate-tag':
        tag = os.environ.get('RELEASE_TAG', '')
        if tag:
            version(tag)
            run('git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/master')
    elif args.command == 'check': checks()
    elif args.command == 'build': build(args.native, args.content)
    elif args.command == 'web':
        with export_content(args.content or 'debug') as ids:
            export_web(Path('builds/web'))
            audit_content(Path('builds/web/index.pck'), ids)
    elif args.command == 'site': site()
    elif args.command == 'publish': publish(os.environ['RELEASE_TAG'])


if __name__ == '__main__':
    main()
