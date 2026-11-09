import sys,unittest
sys.path.insert(0,r'C:\PestoTest-run\python-549a4aa\DEV\tests')
print('Python',sys.version,'isolated=',sys.flags.isolated,'ignore_environment=',sys.flags.ignore_environment,flush=True)
import ctypes
names=['test_ps51_compat.PowerShell51CompatTests.test_parser_passes_keep_only_ps1_extension',
       'test_update_queues.UserQueueTests.test_command_line_preview_prints_clear_warning',
       'test_update_queues.UserQueueTests.test_command_line_with_ansi_code_page_and_foreign_profile_path']
suite=unittest.defaultTestLoader.loadTestsFromNames(names)
result=unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(not result.wasSuccessful())
