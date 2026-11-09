import io
import json
from content_build import select_catalog, prepared_project
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import release


class ReleaseTests(unittest.TestCase):
    def test_tag_format(self):
        for tag in ['0.13.0-preview', '1.2.3', '2.0.0-Alpha_01--test', '1.2.3-01', '1.2.3-_', '1.2.3--', '1.2.3-' + 'a' * 81]:
            with self.subTest(tag=tag):
                self.assertIsNotNone(release.version(tag))
        for tag in ['v1.2.3', '1.2', '01.2.3', '1.2.3-', '1.2.3/evil', '1.2.3-../evil', '1.2.3-beta.1', '1.2.3-x y', '1.2.3-x+y', '1.2.3-кириллица', '1.2.3-x\\y', '1.2.3-x\n', '1.2.٣', '65536.0.0']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.version(tag)

    def test_unsafe_archives_rejected(self):
        for name in ['../escape', '/escape', 'C:/escape', '..\\escape']:
            data = io.BytesIO()
            with zipfile.ZipFile(data, 'w') as z:
                z.writestr(name, 'bad')
            data.seek(0)
            with tempfile.TemporaryDirectory() as root, self.assertRaises(ValueError):
                release.extract_web(data, Path(root))

    def test_complete_archive_required(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as z:
            z.writestr('index.html', 'incomplete')
        data.seek(0)
        with tempfile.TemporaryDirectory() as root, self.assertRaises(ValueError):
            release.extract_web(data, Path(root))

    def test_complete_archive_preserves_paths(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as z:
            for name in ['index.html', 'index.js', 'index.wasm', 'index.pck']:
                z.writestr(name, name)
        data.seek(0)
        with tempfile.TemporaryDirectory() as root:
            release.extract_web(data, Path(root))
            self.assertEqual((Path(root) / 'index.pck').read_text(), 'index.pck')

    def test_stamp_full_version_and_android_code(self):
        original = Path.cwd()
        with tempfile.TemporaryDirectory() as root:
            os.chdir(root)
            try:
                Path('project.godot').write_text('config/version="0.13.0"\n')
                Path('export_presets.cfg').write_text('version/name="0.13.0"\nversion/code=1\napplication/file_version="0.13.0.0"\napplication/product_version="0.13.0.0"\n')
                release.stamp('0.13.0-Alpha_01--test', 42)
                self.assertIn('0.13.0-Alpha_01--test', Path('project.godot').read_text())
                self.assertIn('version/name="0.13.0-Alpha_01--test"', Path('export_presets.cfg').read_text())
                self.assertIn('version/code=42', Path('export_presets.cfg').read_text())
                self.assertIn('application/file_version="0.13.0.0"', Path('export_presets.cfg').read_text())
            finally:
                os.chdir(original)

    def content_fixture(self, root):
        for id in ['rescue_rangers', 'forest_glade']:
            folder = root / 'assets/packs' / id
            folder.mkdir(parents=True)
            (folder / 'pack.tres').write_text('own pack')
            (folder / 'preview.png').write_bytes(b'own preview')
        (root / 'config').mkdir()
        (root / 'config/presentation.tres').write_text('path="res://assets/packs/rescue_rangers/pack.tres"')
        data = {'schema': 1, 'default_pack': 'rescue_rangers', 'restricted_packs': ['rescue_rangers'],
                'profiles': {'debug': ['rescue_rangers', 'forest_glade'], 'release': ['forest_glade']},
                'packs': [{'id': id, 'path': f'res://assets/packs/{id}/pack.tres',
                           'preview': f'res://assets/packs/{id}/preview.png', 'release_ready': id == 'forest_glade',
                           'status': 'ready'} for id in ['rescue_rangers', 'forest_glade']]}
        (root / 'config/pack_catalog.json').write_text(json.dumps(data))
        return data

    def test_release_physically_excludes_debug_content(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.content_fixture(root)
            original = (root / 'config/presentation.tres').read_bytes()
            with prepared_project(root, 'release') as (stage, ids):
                self.assertEqual(ids, ['forest_glade'])
                self.assertFalse((stage / 'assets/packs/rescue_rangers').exists())
                self.assertIn('forest_glade', (stage / 'config/presentation.tres').read_text())
                exported = json.loads((stage / 'config/pack_catalog.json').read_text())
                self.assertEqual(exported['default_pack'], 'forest_glade')
                self.assertEqual([p['id'] for p in exported['packs']], ['forest_glade'])
            self.assertEqual((root / 'config/presentation.tres').read_bytes(), original)
            self.assertTrue((root / 'assets/packs/rescue_rangers/pack.tres').exists())

    def test_debug_preserves_both_packs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.content_fixture(root)
            with prepared_project(root, 'debug') as (stage, ids):
                self.assertEqual(set(ids), {'rescue_rangers', 'forest_glade'})
                self.assertTrue((stage / 'assets/packs/rescue_rangers').exists())
                self.assertTrue((stage / 'assets/packs/forest_glade').exists())

    def test_release_rejects_restricted_pack(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = self.content_fixture(root)
            data['profiles']['release'] = ['rescue_rangers']
            data['packs'][0].update(release_ready=True, status='ready')
            with self.assertRaises(ValueError): select_catalog(root, 'release', data)

    def test_release_rejects_remaining_placeholder(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = self.content_fixture(root)
            forest = root / 'assets/packs/forest_glade'
            (forest / 'test.png').write_bytes(b'placeholder')
            (forest / 'migration.json').write_text(json.dumps({'release_ready': True,
                'entries': [{'path': 'test.png', 'placeholder': True, 'accepted': True},
                            {'path': 'preview.png', 'placeholder': False, 'accepted': True}]}))
            with self.assertRaises(ValueError): select_catalog(root, 'release', data)

    def test_release_rejects_empty_profile_and_cross_pack_reference(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            data = self.content_fixture(root)
            data['profiles']['release'] = []
            with self.assertRaises(ValueError): select_catalog(root, 'release', data)
            (root / 'assets/packs/forest_glade/pack.tres').write_text('path="res://assets/packs/rescue_rangers/secret.png"')
            with self.assertRaises(ValueError):
                with prepared_project(root, 'release'): pass

    def test_unaccepted_tag_commit_fails(self):
        with patch.dict(release.os.environ, RELEASE_TAG='1.2.3'), patch.object(release, 'run', side_effect=RuntimeError('not accepted')) as run:
            with patch('sys.argv', ['release.py', 'validate-tag']), self.assertRaises(RuntimeError):
                release.main()
            self.assertEqual(run.call_args.args, ('git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/master'))


if __name__ == '__main__':
    unittest.main()
