"""Tests d'acquittement Pesto: sources PowerShell et miroir Python _acknowledged."""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import update_installation as update

WAD = ROOT / 'wad'

_ACK_KEYS = ['Schema', 'Utc', 'By', 'Reason', 'Phase', 'ResultCode', 'Observation']


def _read_wad(name):
    return (WAD / name).read_text(encoding='utf-8-sig')


def _strip_powershell_full_line_comments(text):
    return '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))


def _function_body(text, name):
    pattern = re.compile(
        r'(?im)^[ \t]*function\s+' + re.escape(name) + r'\b[\s\S]*?(?=^[ \t]*function\s+|\Z)'
    )
    match = pattern.search(text)
    if not match:
        raise AssertionError('Fonction PowerShell %s introuvable' % name)
    return match.group(0)


def _quoted_values(text):
    values = []
    for match in re.finditer(r"'([^']*)'|\"([^\"]*)\"", text):
        values.append(match.group(1) if match.group(1) is not None else match.group(2))
    return values


class AcknowledgementSourceTests(unittest.TestCase):
    def test_contracts_assert_acknowledgement_closed_object_exact_keys(self):
        body = _function_body(_read_wad('Pesto-Contracts.ps1'), 'Assert-PestoAcknowledgement')
        match = re.search(r'Assert-PestoClosedObject\s+[^@]*@\(([^)]*)\)', body, re.DOTALL)
        self.assertIsNotNone(match, 'Assert-PestoClosedObject introuvable dans Assert-PestoAcknowledgement')
        keys = _quoted_values(match.group(1))
        self.assertEqual(keys, _ACK_KEYS)

    def test_policy_test_acknowledged_receipt_compares_phase_and_result_code_case_sensitive(self):
        body = _function_body(_read_wad('Pesto-Policy.ps1'), 'Test-PestoAcknowledgedReceipt')
        self.assertRegex(body, r'Phase[\s\S]{0,120}-cne|-cne[\s\S]{0,120}Phase')
        self.assertIn('[long]$code -eq [long]$ack.ResultCode', body)

    def test_set_operation_acknowledgement_does_not_mutate_receipt_and_uses_post_mutation_mutex(self):
        body = _function_body(_read_wad('Pesto-Interventions.ps1'), 'Set-PestoOperationAcknowledgement')
        body = _strip_powershell_full_line_comments(body)
        forbidden = (
            r'\.Phase\s*(?:\+=|=(?!=))',
            r'\.ResultCode\s*(?:\+=|=(?!=))',
            r'\.Rename\s*(?:\+=|=(?!=))',
            r'\.Move\s*(?:\+=|=(?!=))',
            r'\.Entra\s*(?:\+=|=(?!=))',
            r'\.Protection\s*(?:\+=|=(?!=))',
            r'\.ResultMessage\s*(?:\+=|=(?!=))',
        )
        for pattern in forbidden:
            self.assertNotRegex(body, pattern)
        self.assertIn('Global\\GP_PostMutation_v1', body)
        self.assertIn('WaitOne(0)', body)

    def test_core_worker_core_names_include_acknowledgement_functions(self):
        core = _read_wad('Pesto-Core.ps1')
        core = _strip_powershell_full_line_comments(core)
        names = set()
        for match in re.finditer(r'\$script:PestoWorkerCoreNames\s*(?:=|\+=)\s*@\(([^)]*)\)', core, re.DOTALL):
            names.update(_quoted_values(match.group(1)))
        self.assertIn('Test-PestoAcknowledgedReceipt', names)
        self.assertIn('Assert-PestoAcknowledgement', names)

    def test_core_find_name_exposes_safety_ack_button(self):
        core = _read_wad('Pesto-Core.ps1')
        self.assertIn('BtnSafetyAck', core)
        self.assertIn('FindName', core)
        self.assertRegex(core, r'FindName[\s\S]{0,100000}BtnSafetyAck|BtnSafetyAck[\s\S]{0,100000}FindName')

    def test_shell_safety_ack_button_has_accessibility_and_disabled_tooltip(self):
        xaml = _read_wad('Pesto-Shell.xaml')
        match = re.search(
            r"<(?P<tag>[\w:.-]+)[^>]*\b(?:x:)?Name\s*=\s*[\"']BtnSafetyAck[\"'][^>]*>",
            xaml,
            re.DOTALL,
        )
        self.assertIsNotNone(match, 'BtnSafetyAck introuvable dans Pesto-Shell.xaml')
        tag = match.group('tag')
        opening_start = match.start()
        closing = re.search(r'</%s>' % re.escape(tag), xaml[opening_start:], re.IGNORECASE)
        block = xaml[opening_start:opening_start + closing.end()] if closing else match.group(0)

        self.assertRegex(block, r'\bToolTip\s*=|<[\w:.-]+\.ToolTip\b')
        self.assertRegex(block, r'AutomationProperties\.HelpText\s*=|<[\w:.-]+\.AutomationProperties\.HelpText\b')
        self.assertRegex(block, r'ToolTipService\.ShowOnDisabled\s*=\s*["\']True["\']')
        self.assertRegex(block, r'AutomationProperties\.AutomationId\s*=|<[\w:.-]+\.AutomationProperties\.AutomationId\b')

    def test_operations_dsregcmd_timeouts_and_retry(self):
        ops = _read_wad('Pesto-Operations.ps1')
        for needle in (
            "-Argument '/status' -TimeoutSec 90",
            "-Argument '/status' -TimeoutSec 120",
            'foreach($attempt in 1..2)',
            '-TimeoutSec 450',
        ):
            self.assertIn(needle, ops)

    def test_inspection_wait_for_exit_120000(self):
        self.assertIn('WaitForExit(120000)', _read_wad('Pesto-Inspection.ps1'))


class AcknowledgedPythonMirrorTests(unittest.TestCase):
    def base_state(self):
        return {
            'Phase': 'Uncertain',
            'ResultCode': 97,
            'Acknowledged': {
                'Schema': 1,
                'Utc': '2026-10-15T12:00:00.0000000Z',
                'By': 'LABO\\tech',
                'Reason': 'Poste relu',
                'Phase': 'Uncertain',
                'ResultCode': 97,
                'Observation': None,
            },
        }

    def test_acknowledged_accepts_closed_valid_acknowledgement(self):
        self.assertTrue(update._acknowledged(self.base_state()))

    def test_acknowledged_rejects_different_ack_phase(self):
        state = self.base_state()
        state['Acknowledged']['Phase'] = 'Running'
        self.assertFalse(update._acknowledged(state))

    def test_acknowledged_rejects_different_result_code(self):
        state = self.base_state()
        state['Acknowledged']['ResultCode'] = 98
        self.assertFalse(update._acknowledged(state))

    def test_acknowledged_rejects_extra_field(self):
        state = self.base_state()
        state['Acknowledged']['Extra'] = 1
        self.assertFalse(update._acknowledged(state))

    def test_acknowledged_rejects_short_reason(self):
        state = self.base_state()
        state['Acknowledged']['Reason'] = 'ok'
        self.assertFalse(update._acknowledged(state))

    def test_acknowledged_rejects_boolean_schema(self):
        state = self.base_state()
        state['Acknowledged']['Schema'] = True
        self.assertFalse(update._acknowledged(state))

    def test_acknowledged_rejects_invalid_utc(self):
        state = self.base_state()
        state['Acknowledged']['Utc'] = 'hier'
        self.assertFalse(update._acknowledged(state))

    def test_acknowledged_accepts_missing_result_code_values(self):
        state = self.base_state()
        state.pop('ResultCode')
        state['Acknowledged']['ResultCode'] = None
        self.assertTrue(update._acknowledged(state))

        state = self.base_state()
        state['ResultCode'] = None
        state['Acknowledged']['ResultCode'] = None
        self.assertTrue(update._acknowledged(state))

    def test_queue_closed_phases_include_acknowledged(self):
        self.assertIn('acknowledged', update._QUEUE_CLOSED_PHASES)


if __name__ == '__main__':
    unittest.main(verbosity=2)
