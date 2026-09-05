#!/usr/bin/env python3
"""Exercise installer replacement and rollback in temporary directories."""

from pathlib import Path
import subprocess
import tempfile
import unittest


INSTALLER = Path(__file__).resolve().parent.parent / 'install.sh'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix='McBopomofo install tests ')
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.functions = self.root / 'functions.sh'
        self.functions.write_text(INSTALLER.read_text().rsplit('main "$@"', 1)[0])
        self.source = self.root / 'staged.app'
        self.destination = self.root / 'installed.app'
        self.backup = self.root / 'backup.app'

    def bundle(self, path, contents):
        path.mkdir()
        (path / 'version').write_text(contents)

    def activate(self):
        return subprocess.run(
            ['sh', '-c', '. "$1"; activate_bundle "$2" "$3" "$4"', 'test-install',
             str(self.functions), str(self.source), str(self.destination), str(self.backup)],
            capture_output=True, text=True)

    def test_replacement_keeps_backup(self):
        self.bundle(self.source, 'new')
        self.bundle(self.destination, 'old')
        result = self.activate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / 'version').read_text(), 'new')
        self.assertEqual((self.backup / 'version').read_text(), 'old')
        self.assertFalse(self.source.exists())

    def test_fresh_install(self):
        self.bundle(self.source, 'new')
        result = self.activate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / 'version').read_text(), 'new')
        self.assertFalse(self.backup.exists())

    def test_failed_activation_restores_original(self):
        self.bundle(self.destination, 'old')
        result = self.activate()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.destination / 'version').read_text(), 'old')
        self.assertFalse(self.backup.exists())

    def test_failed_backup_does_not_replace_original(self):
        self.bundle(self.source, 'new')
        self.bundle(self.destination, 'old')
        self.backup = self.root / 'missing directory' / 'backup.app'
        result = self.activate()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.destination / 'version').read_text(), 'old')
        self.assertEqual((self.source / 'version').read_text(), 'new')

    def test_interrupted_replacement_restores_original(self):
        self.bundle(self.backup, 'old')
        self.bundle(self.source, 'new')
        result = subprocess.run(
            ['sh', '-c', '. "$1"; cleanup_install "$2" "$3" "$4"', 'test-install',
             str(self.functions), str(self.source), str(self.destination), str(self.backup)],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / 'version').read_text(), 'old')
        self.assertFalse(self.source.exists())

    def test_help_does_not_build_or_install(self):
        result = subprocess.run(['sh', str(INSTALLER), '--help'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn('--skip-build', result.stdout)

    def test_unknown_argument_is_rejected(self):
        result = subprocess.run(['sh', str(INSTALLER), '--unknown'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_extra_argument_is_rejected(self):
        result = subprocess.run(
            ['sh', str(INSTALLER), '--skip-build', '--check'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)


if __name__ == '__main__':
    unittest.main()
