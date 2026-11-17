"""Regression: macOS security -v includes revoked identities in its valid list."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import subprocess
import json
import os
import sys
import tempfile

spec = importlib.util.spec_from_file_location('configure_signing', Path(__file__).resolve().parents[1] / 'Tools/configure-signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

OLD = 'AC3AD1EBFC9BB088CC0A5875DFF1607FFFFF6B92'
NEW = '99F4562390898BB4980D2D36D1A5A05AECBC5938'
NAME = 'Apple Development: eric15810870801@outlook.com (SCKUN748QT)'
OUTPUT = f'  1) {OLD} "{NAME}" (CSSMERR_TP_CERT_REVOKED)\n  2) {NEW} "{NAME}"\n  2 valid identities found\n'


class SigningSelectionTest(unittest.TestCase):
    def test_revoked_identity_excluded_despite_valid_count(self):
        result = subprocess.CompletedProcess([], 0, stdout=OUTPUT)
        with patch.object(signing.subprocess, 'run', return_value=result):
            self.assertEqual(signing.identities(), [(NEW, NAME)])

    def test_invalid_identity_remains_visible_for_diagnosis(self):
        self.assertEqual(signing.parse_identities(OUTPUT, valid_only=False), [(OLD, NAME), (NEW, NAME)])

    def test_pinned_revoked_identity_stops_without_switching(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / 'signing.json'
            config.write_text(json.dumps({'required': True, 'identity': OLD}))
            result = subprocess.CompletedProcess([], 0, stdout=OUTPUT)
            with patch.object(signing, 'CONFIG', config), patch.object(signing.subprocess, 'run', return_value=result), patch.object(sys, 'argv', ['configure-signing.py', '--resolve']), patch.dict(os.environ, {}, clear=True):
                with self.assertRaisesRegex(SystemExit, 'unavailable or ambiguous'):
                    signing.main()
            self.assertEqual(json.loads(config.read_text())['identity'], OLD)

    def test_other_failure_statuses_fail_closed(self):
        for status in ['CSSMERR_TP_CERT_EXPIRED', 'CSSMERR_TP_NOT_TRUSTED', 'unknown error']:
            self.assertEqual(signing.parse_identities(f'1) {OLD} "{NAME}" ({status})'), [])

    def test_other_certificate_types_and_summary_ignored(self):
        self.assertEqual(signing.parse_identities(f'1) {OLD} "Apple Distribution: Example"\n2 valid identities found'), [])


if __name__ == '__main__':
    unittest.main()
