"""Audit statique d'accessibilité des XAML de wad/ (fichiers .xaml et here-strings des .ps1).

Chaque document est analysé par xml.etree.ElementTree (variables PowerShell retirées des here-strings @"..."@).
Le parcours ne descend pas dans ControlTemplate, DataTemplate, HierarchicalDataTemplate ni ItemsPanelTemplate.
Les identifiants ne dépendent pas des numéros de ligne : chemin relatif à DEV, document, puis x:Name ou balise et rang.
Le rapport est écrit dans tests/results/ (ignoré par Git). tests/a11y-baseline.json liste les écarts connus et
relus ; le test échoue si cette base manque ou si un nouvel écart apparaît.
"""
import json
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
WAD = DEV / 'wad'
BASELINE = DEV / 'tests' / 'a11y-baseline.json'
REPORT = DEV / 'tests' / 'results' / 'a11y-report.json'

PRESENTATION = 'http://schemas.microsoft.com/winfx/2006/xaml/presentation'
XAML = 'http://schemas.microsoft.com/winfx/2006/xaml'
TEMPLATES = {'ControlTemplate', 'DataTemplate', 'HierarchicalDataTemplate', 'ItemsPanelTemplate'}
INTERACTIVE = {'Button', 'ToggleButton', 'CheckBox', 'RadioButton', 'ComboBox', 'TextBox', 'PasswordBox', 'ListBox',
               'DataGrid', 'TreeView', 'Slider', 'Hyperlink', 'TabItem'}
# Ces contrôles n'ont pas de contenu textuel qui leur donne un nom : il faut un nom ou une étiquette explicite.
NEEDS_EXPLICIT = {'TextBox', 'PasswordBox', 'ComboBox', 'ListBox', 'DataGrid', 'TreeView', 'Slider'}
HERE_STRING = re.compile(r"@(['\"])\r?\n(.*?)\r?\n\1@", re.S)
PS_VARIABLE = re.compile(r'\$\([^()]*(?:\([^()]*\)[^()]*)*\)|\$\{[^}]*\}|\$[A-Za-z_][\w:]*(?:\.[A-Za-z_]\w*)*')
RUNTIME_SETNAME = re.compile(r'AutomationProperties\]::SetName\(\s*\$\w+\.(\w+)')


def local(tag):
    return tag.rsplit('}', 1)[-1] if isinstance(tag, str) else ''


def attr(element, name):
    """Attribut par nom local (AutomationProperties.Name, x:Name, Content...)."""
    for key, value in element.attrib.items():
        if local(key) == name:
            return value
    return None


def has_text(element):
    if (element.text or '').strip():
        return True
    for child in element:
        name = local(child.tag)
        if name in TEMPLATES:
            continue
        if name in ('TextBlock', 'AccessText', 'Label') and (attr(child, 'Text') or attr(child, 'Content') or has_text(child)):
            return True
        if name == 'Run' and (attr(child, 'Text') or (child.text or '').strip()):
            return True
        if name.endswith('.Header') or name.endswith('.Content') or '.' not in name:
            if has_text(child):
                return True
        if (child.tail or '').strip():
            return True
    return False


def documents(path):
    """(étiquette du document, racine XML) pour chaque XAML WPF du fichier."""
    text = path.read_text(encoding='utf-8-sig')
    if path.suffix == '.xaml':
        candidates = [(None, text)]
    else:
        candidates = [(m.group(1), m.group(2)) for m in HERE_STRING.finditer(text)]
    found = []
    ordinal = 0
    for quote, body in candidates:
        source = body.strip()
        if not source.startswith('<') or PRESENTATION not in source:
            continue
        if quote == '"':
            source = PS_VARIABLE.sub('PSVAR', source)
        root = ET.fromstring(source)  # Un XAML illisible fait échouer l'audit : jamais ignoré.
        if not root.tag.startswith('{' + PRESENTATION + '}'):
            continue
        ordinal += 1
        label = attr(root, 'Name') or '%s%d' % (local(root.tag), ordinal)
        found.append((label, root))
    return found


def walk(element):
    """Éléments hors gabarits, dans l'ordre du document."""
    for child in element:
        if local(child.tag) in TEMPLATES:
            continue
        yield child
        yield from walk(child)


def audit():
    runtime_named = set()
    for path in WAD.glob('*.ps1'):
        if path.name != 'Pesto.Engine.Runtime.ps1':
            runtime_named.update(RUNTIME_SETNAME.findall(path.read_text(encoding='utf-8-sig')))
    report, gaps = {}, {}
    sources = sorted(p for p in WAD.iterdir() if p.suffix in ('.xaml', '.ps1') and p.name != 'Pesto.Engine.Runtime.ps1')
    for path in sources:
        relative = path.relative_to(DEV).as_posix()
        for label, root in documents(path):
            key = relative + '#' + label
            counters, ids, entries, warnings = {}, {}, [], []
            elements = [e for e in [root] + list(walk(root)) if local(e.tag) in INTERACTIVE]
            for element in elements:
                tag = local(element.tag)
                name = attr(element, 'Name')
                if name:
                    element_id = '%s:%s' % (tag, name)
                else:
                    counters[tag] = counters.get(tag, 0) + 1
                    element_id = '%s[%d]' % (tag, counters[tag])
                explicit = attr(element, 'AutomationProperties.Name') or attr(element, 'AutomationProperties.LabeledBy') \
                    or (name and name in runtime_named)
                textual = tag not in NEEDS_EXPLICIT and (attr(element, 'Content') or attr(element, 'Header') or has_text(element))
                if not explicit and not textual:
                    entries.append((element_id, tag + ' sans nom accessible (Name, LabeledBy, contenu ou SetName)'))
                if attr(element, 'IsTabStop') == 'False' or attr(element, 'Focusable') == 'False':
                    entries.append((element_id + ':focus', tag + ' interactif retiré du parcours clavier'))
                automation_id = attr(element, 'AutomationProperties.AutomationId')
                if automation_id:
                    if automation_id in ids:
                        entries.append(('AutomationId:' + automation_id, 'AutomationId en double'))
                    ids[automation_id] = element_id
                if attr(element, 'ToolTip') and not attr(element, 'AutomationProperties.HelpText'):
                    warnings.append(element_id + ' : ToolTip sans HelpText')
            for element_id, reason in entries:
                gaps[key + '/' + element_id] = reason
            report[key] = {'interactive': len(elements), 'gaps': [key + '/' + e for e, _ in entries], 'warnings': warnings}
    return report, gaps


class TestA11yStatic(unittest.TestCase):
    def test_audit_against_reviewed_baseline(self):
        report, gaps = audit()
        # Le parcours atteint bien la fenêtre principale (l'ancien compteur de profondeur la laissait à 0).
        self.assertIn('wad/Pesto-Shell.xaml#Window1', report)
        self.assertGreater(report['wad/Pesto-Shell.xaml#Window1']['interactive'], 100)
        self.assertTrue(all(not k.startswith('/') and '/Users/' not in k for k in gaps))
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps({'documents': report, 'gaps': gaps}, indent=2, ensure_ascii=False), encoding='utf-8')
        if not BASELINE.is_file():
            self.fail('tests/a11y-baseline.json absent : relire le rapport ' + str(REPORT) + ' puis créer la base.')
        baseline = json.loads(BASELINE.read_text(encoding='utf-8-sig'))
        known = baseline.get('Gaps', {})
        new = sorted(set(gaps) - set(known))
        self.assertEqual(new, [], "Nouveaux écarts d'accessibilité (corriger le XAML, ou relire et justifier dans la base)")
        fixed = sorted(set(known) - set(gaps))
        if fixed:
            print('Écarts corrigés, à retirer de tests/a11y-baseline.json : ' + ', '.join(fixed))

    def test_template_content_is_not_audited(self):
        root = ET.fromstring('<Window xmlns="%s" xmlns:x="%s"><Window.Resources><ControlTemplate x:Key="t">'
                             '<Button/></ControlTemplate><DataTemplate x:Key="d"><TextBox/></DataTemplate></Window.Resources>'
                             '<StackPanel><Button Content="OK"/><TextBox x:Name="Saisie"/></StackPanel></Window>' % (PRESENTATION, XAML))
        self.assertEqual([local(e.tag) for e in walk(root) if local(e.tag) in INTERACTIVE], ['Button', 'TextBox'])


if __name__ == '__main__':
    unittest.main()
