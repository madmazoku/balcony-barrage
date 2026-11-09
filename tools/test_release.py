import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import release


class ReleaseTests(unittest.TestCase):
    def test_tag_format(self):
        for tag in ['0.13.0-preview', '1.2.3', '2.0.0-beta.1']:
            self.assertIsNotNone(release.version(tag))
        for tag in ['v1.2.3', '1.2', '01.2.3', '1.2.3-', '1.2.3/evil', '1.2.3-../evil', '1.2.3-x_y', '1.2.3-01']:
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
                release.stamp('0.13.0-preview', 42)
                self.assertIn('0.13.0-preview', Path('project.godot').read_text())
                self.assertIn('version/code=42', Path('export_presets.cfg').read_text())
                self.assertIn('application/file_version="0.13.0.0"', Path('export_presets.cfg').read_text())
            finally:
                os.chdir(original)

    def test_unaccepted_tag_commit_fails(self):
        with patch.dict(release.os.environ, RELEASE_TAG='1.2.3'), patch.object(release, 'run', side_effect=RuntimeError('not accepted')) as run:
            with patch('sys.argv', ['release.py', 'validate-tag']), self.assertRaises(RuntimeError):
                release.main()
            self.assertEqual(run.call_args.args, ('git', 'merge-base', '--is-ancestor', 'HEAD', 'origin/master'))


if __name__ == '__main__':
    unittest.main()
