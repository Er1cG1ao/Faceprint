#!/usr/bin/env python3
"""Select an existing Apple codesigning identity; never export keys or log in."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / '.signing.local.json'

def identities(valid_only=True):
    result = subprocess.run(['/usr/bin/security', 'find-identity', *(['-v'] if valid_only else []), '-p', 'codesigning'],
                            check=True, text=True, capture_output=True)
    return [(sha.upper(), name) for sha, name in re.findall(r'\b([0-9A-Fa-f]{40})\s+"([^"]+)"', result.stdout)
            if name.startswith(('Apple Development:', 'Developer ID Application:'))]

def save(value):
    temporary = CONFIG.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.chmod(0o600)
    temporary.replace(CONFIG)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--identity', help='Exact certificate name or SHA-1 fingerprint already in your keychain')
    parser.add_argument('--resolve', action='store_true', help='Resolve the build identity, without changing configuration')
    parser.add_argument('--require', action='store_true', help='Require stable signing even while account setup is pending')
    args = parser.parse_args()
    if args.require:
        config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
        config['required'] = True
        config.setdefault('identity', None)
        save(config)
        print('Stable signing is required for this checkout. No signing key was created or exported.')
        return
    if args.resolve:
        config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
        selected = os.environ.get('FACEPRINT_SIGN_IDENTITY') or config.get('identity') or '-'
        if selected == '-':
            if config.get('required') and os.environ.get('FACEPRINT_ALLOW_ADHOC') != '1':
                raise SystemExit('Signing is not configured. Create Apple Development in Xcode, then run python3 Tools/configure-signing.py.')
            print('-')
            return
        matches = [(sha, name) for sha, name in identities() if sha == selected.upper() or name == selected]
        if len(matches) != 1:
            raise SystemExit('The selected Apple signing identity is unavailable or ambiguous. Build stopped; no ad hoc fallback.')
        print(matches[0][0])
        return
    candidates = identities()
    if args.identity:
        candidates = [(sha, name) for sha, name in candidates if sha == args.identity.upper() or name == args.identity]
    if not candidates:
        if identities(valid_only=False):
            raise SystemExit('An Apple certificate/private-key pair exists, but macOS does not mark it valid. Verify certificate dates and the Apple WWDR intermediate chain; do not recreate the key unnecessarily.')
        raise SystemExit('No matching Apple signing identity. Install Xcode, sign in under Settings > Accounts, then Manage Certificates > + > Apple Development.')
    if len(candidates) != 1:
        print('Multiple signing identities are available. Choose one with --identity SHA1:', file=sys.stderr)
        for sha, name in candidates:
            print(f'  {sha}  {name}', file=sys.stderr)
        raise SystemExit(1)
    sha, name = candidates[0]
    save({'required': True, 'identity': sha, 'name': name})
    print('Selected ' + name)
    print('Future builds use this existing keychain identity and refuse silent ad hoc fallback.')

if __name__ == '__main__':
    main()
