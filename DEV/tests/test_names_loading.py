"""Checks on the actual Names implementation and packaging. Not WPF execution."""
from pathlib import Path
import unittest,sys,re,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'));sys.path.insert(0,str(ROOT/'tools'))
from ps_lexical import functions,tokens
from refresh_manifest import verify_native_binding
class NamesLoading(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.core=(ROOT/'wad/Pesto-Core.ps1').read_text('utf-8-sig')
  cls.directory=(ROOT/'wad/Pesto-Directory.ps1').read_text('utf-8-sig')
  cls.fns={n:cls.core[a:b] for n,(a,b) in functions(cls.core).items()}
  cls.xml=ET.parse(ROOT/'wad/Pesto-Shell.xaml')
  cls.nodes={e.get('{http://schemas.microsoft.com/winfx/2006/xaml}Name'):e for e in cls.xml.iter() if e.get('{http://schemas.microsoft.com/winfx/2006/xaml}Name')}
 def test_progress_controls_are_bound_in_the_script(self):
  for n in ('NmLoadingPanel','NmLoadingTitle','NmLoadingDetail','NmLoadingElapsed','NmLoadingBar','NmViewNote','NmBtnRetryNames'):
   self.assertIn(n,self.nodes);self.assertIn("'"+n+"'",self.core)
 def test_background_calculation_contains_no_ui_or_ad(self):
  code=self.fns['Invoke-PestoBuildNamesView']
  self.assertNotRegex(code,r'\$(?:script:)?Nm(?:Grid|Cmb|Lbl)|Get-AD\w+|Write-Log|Start-Process|Restart-Computer')
  self.assertIn("-Name 'NamesProjection'",self.fns['Update-NameGrid'])
  self.assertNotIn('for ($i=',self.fns['Update-NameGrid'])
 def test_progress_indeterminate_and_clock_not_guessed(self):
  self.assertIn("IsIndeterminate=($State -eq 'Loading')",self.fns['Set-PestoNamesViewState'])
  self.assertIn('Diagnostics.Stopwatch',self.fns['Set-PestoNamesViewState'])
  self.assertIn('if($total -gt 0)',self.fns['Update-PestoNamesLoadProgress'])
  self.assertIn('IsIndeterminate=($total -le 0)',self.fns['Update-PestoNamesLoadProgress'])
 def test_directory_progress_streams_counts_not_partial_results(self):
  self.assertIn('$readRoot++',self.directory);self.assertIn('$readNames++',self.directory)
  self.assertIn('Progress.State=',self.directory)
  self.assertNotIn('$NmGrid',self.directory)
  self.assertIn('Get-ADComputer -Filter *',self.directory)
  self.assertIn('-ErrorAction Stop @adp | ForEach-Object',self.directory)
 def test_no_projection_of_partial_inventory(self):
  code=self.fns['Update-NameGrid']
  self.assertLess(code.index("'DirectoryRefresh'"),code.index("-Name 'NamesProjection'"))
  self.assertIn('-not $script:InventoryLoaded -and -not $script:GUI',code)
 def test_no_stale_callback_after_filter_or_scan(self):
  self.assertIn('$Context.Generation -ne [int]$script:NmViewGeneration',self.fns['Complete-PestoNamesProjection'])
  self.assertIn('ReferenceEquals($Context.Source,$script:ComputersNoms)',self.fns['Complete-PestoNamesProjection'])
  event=self.core.split('$NmTxtSearch.Add_TextChanged({',1)[1].split('\n})',1)[0]
  self.assertLess(event.index('NmViewGeneration'),event.index('NmSearchTimer.Start'))
  self.assertIn("Stop-PestoAsyncOperation 'NamesProjection'",event)
 def test_copy_export_blocked_until_ready(self):
  self.assertIn('-not $script:NmViewReady',self.fns['Copy-NmName'])
  self.assertIn('-not $script:NmViewReady',self.fns['Export-NameView'])
  self.assertIn("$NmGrid.ItemsSource=@()",self.fns['Set-PestoNamesViewState'])
 def test_empty_error_ready_distinct(self):
  code=self.fns['Set-PestoNamesViewState']
  for state in ('Loading','Ready','Empty','Error','NotLoaded'):self.assertIn("'"+state+"'",code)
  self.assertIn('-State Empty',self.fns['Complete-PestoNamesProjection'])
  self.assertIn('-State Error',self.fns['Fail-PestoNamesProjection'])
 def test_render_size_bounded_and_disclosed(self):
  self.assertIn('PageSize=250',self.fns['Update-NameGrid'])
  self.assertIn('MaxRows=250',self.fns['Update-NameGrid'])
  self.assertIn('$rows.Count -lt $size',self.fns['Invoke-PestoBuildNamesView'])
  self.assertIn('$size -gt 500',self.fns['Invoke-PestoBuildNamesView'])
  self.assertIn('$totalWork -gt 2000000',self.fns['Invoke-PestoBuildNamesView'])
  self.assertIn('$Result.Total',self.fns['Complete-PestoNamesProjection'])
 def test_timer_cleanup_and_generation_named_handler(self):
  self.assertIn('${function:Update-PestoNamesLoadProgress}',self.fns['Set-PestoNamesViewState'])
  self.assertRegex(self.core,r'\$Win\.Add_Closed\(\{[\s\S]{0,160}Stop-PestoNamesLoadTimer')
  self.assertNotIn('GetNewClosure',self.fns['Set-PestoNamesViewState'])
 def test_dev_native_test_included_not_runtime_requirement(self):
  self.assertTrue((ROOT/'TEST_NOMS.cmd').exists());self.assertTrue((ROOT/'tests/Run-NamesLoadingTests.ps1').exists())
  tokens((ROOT/'tests/Run-NamesLoadingTests.ps1').read_text('utf-8-sig'))
  names=verify_native_binding(ROOT)
  self.assertNotIn('TEST_NOMS.cmd',names);self.assertNotIn('tests/Run-NamesLoadingTests.ps1',names)
 def test_no_double_cr_in_new_sources(self):
  for path in ('wad/Pesto-Core.ps1','wad/Pesto-Directory.ps1','wad/Pesto-Shell.xaml','tests/Run-NamesLoadingTests.ps1'):
   self.assertNotIn(b'\r\r\n',(ROOT/path).read_bytes())
if __name__=='__main__':unittest.main(verbosity=2)
