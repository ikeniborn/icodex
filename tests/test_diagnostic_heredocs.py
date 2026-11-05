#!/usr/bin/env python3
"""Exercise diagnostic access decisions through the actual hook."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
import importlib.util
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / '.codex-isolated/hooks/block-secrets.py'


def invoke(language, body):
    command = language + " <<'DIAG'\n" + body + '\nDIAG'
    payload = {'tool_name': 'Bash', 'tool_input': {'command': command}}
    env = {k: os.environ[k] for k in ('PATH', 'LANG') if k in os.environ}
    return subprocess.run([sys.executable, str(HOOK)], input=json.dumps(payload),
                          text=True, capture_output=True, cwd=ROOT, env=env, timeout=10)


class Decisions(unittest.TestCase):
    def decision(self, language, body, category=None):
        result = invoke(language, body)
        self.assertEqual(result.returncode, 2 if category else 0)
        if category:
            self.assertIn(category, result.stderr)
            self.assertIn('reason', json.loads(result.stdout))


class PythonDiagnosticTests(Decisions):
    def test_annotated(self):
        self.decision('python3', "text: str = 'README.md'\nprint(text)")

    def test_builtins_and_methods(self):
        for name in 'print len str int float bool list tuple dict set sorted enumerate range zip sum min max any all'.split():
            args = {'int': '1', 'float': '1', 'range': '2', 'dict': '', 'str': "'x'", 'bool': '1', 'print': "'x'"}.get(name, '[1]')
            with self.subTest(name=name):
                self.decision('python3', name + '(' + args + ')')
        methods = {'split': '', 'splitlines': '', 'strip': '', 'lstrip': '', 'rstrip': '',
                   'startswith': "'x'", 'endswith': "'x'", 'lower': '', 'upper': '', 'replace': "'x', 'y'"}
        for method, args in methods.items():
            with self.subTest(method=method):
                self.decision('python3', "'x'." + method + '(' + args + ')')
        for statement in ["d={}; print(d.items(), d.keys(), d.values(), d.get('x')); d.setdefault('x', 1)",
                          'x=[]; x.append(1)', 'x=set(); x.add(1)',
                          "x = 'a' if True else 'b'; print(f'{x}', x[0:1], 1+2, not False, 1 < 2, True and False)"]:
            self.decision('python3', statement)

    def test_analysis_reads_no_files(self):
        spec = importlib.util.spec_from_file_location('analysis_fixture', ROOT / '.codex-isolated/hooks/_diagnostic_heredoc.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch('builtins.open', side_effect=AssertionError('classification opened a file')), patch.object(Path, 'read_text', side_effect=AssertionError('classification read a file')):
            result = module.analyze_python("from pathlib import Path\nPath('does-not-exist.txt').read_text()", lambda path: (False, ''))
            self.assertIsNone(result[0])
    def test_operations(self):
        safe = [
            "p='README.md'\nq=Path(p)\nq.read_bytes()",
            "p=Path('.') / 'README.md'\np.exists()\np.is_file()\np.is_dir()",
            "print('/run/secrets/notice')",
            "items=Path('README.md').read_text().splitlines()\nfor line in items:\n print(line.strip().lower())",
            "print([line.strip() for line in Path('README.md').read_text().splitlines()])",
            "import json\nprint(json.dumps(json.loads('{}')))",
            "from collections import Counter\nprint(Counter(['a']).items())",
            "import pathlib\npathlib.Path('README.md').read_text()",
            "print({line for line in ['a']}, {line: 1 for line in ['a']}, list(n for n in range(2)))",
            "p=Path('README.md')\nif True:\n p=Path('README.md')\nelse:\n p=Path('README.md')\np.read_text()",
        ]
        for body in safe:
            with self.subTest(body=body):
                self.decision('python3', 'from pathlib import Path\n' + body)

    def test_adversarial(self):
        denied = [
            "reader=Path\nreader('README.md')",
            "import subprocess\nsubprocess.run(['true'])",
            "print.__globals__",
            "Path=print",
            "print=Path",
            "d={'reader':Path}",
            "p=Path('README.md')\ng=(p.read_text() for n in range(1))\np=Path('.env')\nprint(list(g))",
            "paths=['README.md']\na=paths\na[0]='.env'\nPath(paths[0]).read_text()",
            "def action():\n return 1",
            "unknown.read_text()",
            "sorted(['a'], key=Path)",
            "[n for Path in []]",
            "for print in []:\n print(1)",
            "p=Path('README.md')\nif True:\n p=Path('README.md')\nelse:\n p=Path('.env')\np.read_text()",
            "p=Path('README.md')\nfor n in []:\n p=Path('.env')\np.read_text()",
            "p=Path('README.md')\np.value=1",
            "x = (",
        ]
        for body in denied:
            with self.subTest(body=body):
                self.decision('python3', 'from pathlib import Path\n' + body, 'indeterminate_access')

    def test_dead_secret(self):
        self.decision('python3', "from pathlib import Path\nif False:\n Path('.env').read_text()", 'protected_path')
        self.decision('python3', "from pathlib import Path\nprint(value=Path('.env').read_text())", 'protected_path')
        self.decision('python3', "from pathlib import Path\nx: Path('.env').read_text() = 1", 'protected_path')
    def test_safe(self):
        self.decision('python3', "from pathlib import Path\ntext = Path('README.md').read_text()\nprint(len(text.splitlines()))")

    def test_protected(self):
        self.decision('python3', "from pathlib import Path\nPath('.env').read_text()", 'protected_path')

    def test_dynamic(self):
        self.decision('python3', "from pathlib import Path\nPath(Path('paths.txt').read_text()).read_text()", 'indeterminate_access')

    def test_loop(self):
        self.decision('python3', "from pathlib import Path\np = Path('README.md')\nfor n in range(2):\n p.read_text()\n p = Path('.env')", 'indeterminate_access')


class BashDiagnosticTests(Decisions):
    def test_flag_families(self):
        for cmd, flags in [('cat', 'nbsETvA'), ('wc', 'lwcmL'), ('ls', 'laAhdnistr1')]:
            for flag in flags:
                self.decision('bash', cmd + ' -' + flag + ' README.md')
        for cmd in ('head', 'tail'):
            for flag in ('n', 'c'):
                self.decision('bash', cmd + ' -' + flag + ' 2 README.md')

    def test_operations(self):
        for body in ["echo '/run/secrets/note'", "printf '%s' 'literal $value; text'", 'cat -n README.md',
                     'head -n 2 README.md', 'tail -c 4 README.md', 'ls -lah README.md',
                     '/usr/bin/wc -l README.md', 'pwd; echo done # ignored', "cat REA''DME.md"]:
            with self.subTest(body=body):
                self.decision('bash', body)

    def test_adversarial(self):
        for body in ['cat $(echo .env)', 'cat README*', 'cat README.md | wc -l',
                     'echo x > .env', 'unknown README.md', 'printf -v target text',
                     'wc --files0-from=README.md', 'echo `cat .env`']:
            with self.subTest(body=body):
                self.decision('bash', body, 'indeterminate_access')

    def test_printf_assignments(self):
        for body in ["printf -vtarget '%s' value", "printf '%n' 'array[$(cat .env)]'", "printf '%10n' target"]:
            with self.subTest(body=body):
                self.decision('bash', body, 'indeterminate_access')
    def test_safe(self):
        self.decision('bash', "wc -l README.md\nprintf '%s\\n' 'diagnostic complete'")

    def test_protected(self):
        self.decision('bash', 'cat .env', 'protected_path')

    def test_dynamic(self):
        self.decision('bash', 'cat "$diagnostic_path"', 'indeterminate_access')


class IntegrationTests(Decisions):
    def test_content_guard(self):
        token = 'sk-proj-' + 'A' * 36
        for language, body in [('python3', 'print(' + repr(token) + ')'), ('bash', 'echo ' + repr(token))]:
            self.decision(language, body)
            command = language + " <<'END'\n" + body + '\nEND'
            payload = {'tool_name': 'Bash', 'tool_input': {'command': command}}
            result = subprocess.run([sys.executable, str(HOOK.with_name('redact-secrets.py'))], input=json.dumps(payload), text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn(token, result.stdout + result.stderr)

    def test_envelopes(self):
        for language in ('python3', 'python3 -', '/usr/bin/python3', '/usr/bin/python3 -'):
            self.decision(language, 'print(1)')
        for language in ('bash', '/bin/bash', 'bash --noprofile', 'bash --norc', 'bash --noprofile --norc'):
            self.decision(language, 'echo done')

    def test_safe_reason(self):
        marker = 'DO_NOT_ECHO_7831'
        for language, body in [('python3', "from pathlib import Path\nPath('/run/secrets/" + marker + "').read_text()"), ('bash', 'cat /run/secrets/' + marker)]:
            result = invoke(language, body)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn(marker, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
