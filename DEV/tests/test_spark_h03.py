import re, sys, tempfile, unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

import update_installation
from update_installation import _pesto_session_mutex_name, _check_pesto_session_lock, apply_update


class TestPestoSessionLock(unittest.TestCase):
    def test_mutex_name_matches_powershell(self):
        # Value of the real Pesto-Startup.ps1 expression ([BitConverter]::ToString -> uppercase hex)
        # for 'C:\Program Files\Pesto' and $Demo absent. Win32 object names are case-sensitive.
        self.assertEqual(_pesto_session_mutex_name(r'C:\Program Files\Pesto', False),
                         'Global\\GP_Session_467FB15D9BD46BD922E5F844')
        self.assertNotEqual(_pesto_session_mutex_name(r'C:\Program Files\Pesto', True),
                            _pesto_session_mutex_name(r'C:\Program Files\Pesto', False))

    def test_mutex_name_fixed_vector(self):
        # Vecteur calculé sous pwsh 7.4 avec la formule de Pesto-Startup.ps1 pour 'C:\\Pesto\\Install' et $Demo absent.
        self.assertEqual(_pesto_session_mutex_name('C:\\Pesto\\Install', False),
                         'Global\\GP_Session_0CB133A024FBF5F3B6C3D1D2')

    def test_mutex_name_case_insensitive_root(self):
        self.assertEqual(_pesto_session_mutex_name('C:\\Pesto\\Install', False),
                         _pesto_session_mutex_name('c:\\pesto\\install', False))

    @unittest.skipIf(sys.platform == 'win32', 'Plateforme : contrôle du comportement hors Windows.')
    def test_check_lock_non_windows_is_noop(self):
        _check_pesto_session_lock(Path('/tmp/fake'))

    def _run_check(self, handles, last_error=2):
        kernel = mock.MagicMock()
        kernel.OpenMutexW.side_effect = list(handles)
        with mock.patch.object(update_installation.os, 'name', 'nt'), \
             mock.patch.object(update_installation.ctypes, 'WinDLL', create=True, return_value=kernel), \
             mock.patch.object(update_installation.ctypes, 'get_last_error', create=True, return_value=last_error):
            try:
                _check_pesto_session_lock(Path('/opt/Pesto'))
            finally:
                self.calls = kernel.OpenMutexW.call_args_list
                self.closed = kernel.CloseHandle.call_count

    def test_open_session_refuses(self):
        with self.assertRaises(ValueError) as cm:
            self._run_check([1234, None])
        self.assertIn('Pesto est ouvert depuis ce dossier', str(cm.exception))
        self.assertEqual(self.closed, 1)
        self.assertEqual(self.calls[0].args[0], 0x00100000)
        self.assertRegex(self.calls[0].args[2], r'^Global\\GP_Session_[0-9A-F]{24}$')

    def test_absent_session_allows(self):
        self._run_check([None, None], last_error=2)
        self.assertEqual(len(self.calls), 2)

    def test_access_denied_is_not_absent(self):
        with self.assertRaises(ValueError) as cm:
            self._run_check([None, None], last_error=5)
        self.assertIn('Impossible de vérifier', str(cm.exception))


class TestSessionRefusalReleasesUpdateLock(unittest.TestCase):
    # The plan is a double: only the ordering between the session check and the
    # O_EXCL fence is under test, independently of the runtime manifest state.
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dest = Path(self.tmp.name) / 'installed'
        self.dest.mkdir()
        plan = {'Source': str(ROOT), 'Destination': str(self.dest), 'ManagedInstallation': False}
        patcher = mock.patch.object(update_installation, 'plan_update', return_value=plan)
        patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def test_refusal_before_fence_leaves_no_lock(self):
        with mock.patch.object(update_installation, '_check_pesto_session_lock',
                               side_effect=ValueError('Pesto est ouvert depuis ce dossier')):
            with self.assertRaises(ValueError):
                apply_update(ROOT, self.dest)
        self.assertFalse((self.dest / '.pesto-update.lock').exists())

    def test_refusal_after_fence_releases_lock(self):
        calls = []

        def second_call_refuses(destination):
            calls.append(destination)
            if len(calls) == 2:
                # The fence exists while the second check runs: new Pesto launches are refused.
                self.assertTrue((self.dest / '.pesto-update.lock').exists())
                raise ValueError('Pesto est ouvert depuis ce dossier')

        with mock.patch.object(update_installation, '_check_pesto_session_lock', side_effect=second_call_refuses):
            with self.assertRaises(ValueError):
                apply_update(ROOT, self.dest)
        self.assertEqual(len(calls), 2)
        self.assertFalse((self.dest / '.pesto-update.lock').exists())


if __name__ == '__main__':
    unittest.main()
