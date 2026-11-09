"""Explicit debug/release content composition, with isolated release staging."""
from contextlib import contextmanager
import json
from pathlib import Path
import re
import shutil
import tempfile

CATALOG = Path('config/pack_catalog.json')


def select_catalog(root, flavor, data=None):
    data = json.loads((root / CATALOG).read_text(encoding='utf-8')) if data is None else data
    if flavor not in ('debug', 'release') or data.get('schema') != 1:
        raise ValueError('Invalid content profile/catalog.')
    entries = data['packs']
    by_id = {p['id']: p for p in entries}
    if len(by_id) != len(entries): raise ValueError('Duplicate pack ID.')
    ids = data['profiles'][flavor]
    if not ids or len(ids) != len(set(ids)):
        raise ValueError('No approved packs for this content profile; finish and accept the forest pack before a public release.')
    chosen = []
    for id in ids:
        if id not in by_id or not re.fullmatch(r'[a-z0-9_-]+', id): raise ValueError('Invalid pack ID.')
        entry = by_id[id]
        prefix = 'res://assets/packs/' + id + '/'
        if entry['path'] != prefix + 'pack.tres' or not entry['preview'].startswith(prefix):
            raise ValueError('Pack references must stay in their own directory.')
        folder = root / 'assets/packs' / id
        if not (folder / 'pack.tres').is_file(): raise ValueError('Missing pack: ' + id)
        preview = root / entry['preview'].removeprefix('res://')
        if not preview.resolve().is_relative_to(folder.resolve()) or not preview.is_file():
            raise ValueError('Missing or external pack preview: ' + id)
        if flavor == 'release':
            if id in data.get('restricted_packs', []) or entry.get('release_ready') is not True or entry.get('status') != 'ready':
                raise ValueError('Pack is not approved for release: ' + id)
            migration_path = folder / 'migration.json'
            if entry.get('migration') and entry['migration'] != prefix + 'migration.json':
                raise ValueError('Invalid migration manifest path.')
            if entry.get('migration') and not migration_path.is_file():
                raise ValueError('Missing migration manifest.')
            if migration_path.exists():
                migration = json.loads(migration_path.read_text(encoding='utf-8'))
                items = migration['entries']
                images = {p.relative_to(folder).as_posix() for p in folder.rglob('*.png')}
                if migration.get('release_ready') is not True or len(items) != len(images) or {p['path'] for p in items} != images or any(p.get('placeholder') is not False or p.get('accepted') is not True for p in items):
                    raise ValueError('Unaccepted images or placeholders remain: ' + id)
        chosen.append(entry)
    default = data['default_pack'] if data['default_pack'] in ids else ids[0]
    result = dict(data, default_pack=default, packs=chosen,
                  profiles={'debug': ids, 'release': ids if flavor == 'release' else data['profiles']['release']})
    return result


@contextmanager
def prepared_project(root, flavor, data=None):
    root = root.resolve()
    catalog = select_catalog(root, flavor, data)
    ids = {p['id'] for p in catalog['packs']}
    # Copy only permitted pack directories. The working project is never rewritten.
    with tempfile.TemporaryDirectory(prefix='balcony-content-') as temp:
        stage = Path(temp)
        def ignore(folder, names):
            path = Path(folder)
            if path == root:
                return set(names) & {'.git', '.godot', '.github', '.agents', 'art', 'docs', 'tools', 'builds', 'exports', 'android'}
            if path == root / 'assets/packs': return set(names) - ids
            return {n for n in names if n == '__pycache__' or n.endswith(('.log', '.tmp', '.pyc'))}
        shutil.copytree(root, stage, ignore=ignore, dirs_exist_ok=True)
        (stage / CATALOG).write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding='utf-8')
        presentation = stage / 'config/presentation.tres'
        text = presentation.read_text(encoding='utf-8')
        text = re.sub(r'res://assets/packs/[^/]+/pack\.tres', 'res://assets/packs/' + catalog['default_pack'] + '/pack.tres', text)
        presentation.write_text(text, encoding='utf-8')
        for file in stage.rglob('*.tres'):
            for id in re.findall(r'res://assets/packs/([^/]+)/', file.read_text(encoding='utf-8')):
                if id not in ids: raise ValueError('Cross-pack dependency in public export: ' + str(file.relative_to(stage)))
        yield stage, sorted(ids)
