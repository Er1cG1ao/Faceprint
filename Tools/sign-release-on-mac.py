#!/usr/bin/env python3
"""Sign a verified Faceprint release using THIS Mac's existing Apple identity.

No certificate/private-key export, account login, installation or upload occurs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
API = 'https://api.github.com/repos/Er1cG1ao/Faceprint/releases/'
ALLOWED = {'api.github.com', 'github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}
MAX_ARCHIVE = 512 * 1024 * 1024
BUNDLE_ID = 'io.github.er1cg1ao.faceprint'

class Redirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        from urllib.parse import urlsplit
        url = urlsplit(newurl)
        if url.scheme != 'https' or url.hostname not in ALLOWED or url.username or url.password or url.port:
            raise RuntimeError('Unexpected update download redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

OPENER = urllib.request.build_opener(Redirects())

def run(*args, capture=False):
    return subprocess.run([str(x) for x in args], check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout

def version(value):
    value = value.removeprefix('v') if hasattr(value, 'removeprefix') else (value[1:] if value.startswith('v') else value)
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', value):
        raise RuntimeError('Expected a stable X.Y.Z version')
    return value

def stamp(app, number, build):
    path = app / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    if info.get('CFBundleIdentifier') != BUNDLE_ID or info.get('CFBundleExecutable') != 'Faceprint':
        raise RuntimeError('Unexpected application metadata')
    info['CFBundleShortVersionString'] = number
    info['CFBundleVersion'] = str(build)
    path.write_bytes(plistlib.dumps(info, sort_keys=False))

def sign(app, identity):
    helper = app / 'Contents/Helpers/FaceprintUpdateInstaller'
    if not helper.is_file():
        raise RuntimeError('This release does not contain the update installer')
    # Only remove resource-fork/Finder metadata that codesign cannot seal.
    # Do not alter Gatekeeper settings, TCC or keychain trust.
    for attribute in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
        subprocess.run(['/usr/bin/xattr', '-dr', attribute, str(app)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run('/usr/bin/codesign', '--force', '--sign', identity, '--identifier', BUNDLE_ID + '.updater',
        '--options', 'runtime', helper)
    run('/usr/bin/codesign', '--force', '--sign', identity, '--options', 'runtime',
        '--entitlements', ROOT / 'entitlements.plist', app)
    run('/usr/bin/codesign', '--verify', '--strict', '--deep', app)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', help='Existing certificate SHA-1 or exact name; required only if multiple identities exist')
    parser.add_argument('--source-version', help='GitHub source release; default is the latest stable release')
    parser.add_argument('--version', help='Output version; default increments the source patch version')
    parser.add_argument('--output', type=Path, help='New output directory; default is a unique folder under Downloads')
    args = parser.parse_args()
    selector = ROOT / 'Tools/configure-signing.py'
    setup = [sys.executable, str(selector)]
    if args.identity:
        setup += ['--identity', args.identity]
    run(*setup)
    identity = run(sys.executable, selector, '--resolve', capture=True).strip()
    if identity == '-':
        raise RuntimeError('This workflow requires a real Apple signing identity')
    cache = ROOT / '.build-cache'
    cache.mkdir(exist_ok=True)
    checker = cache / 'SigningIdentityCheck'
    run('/usr/bin/xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
        '-module-cache-path', cache, ROOT / 'Sources/UpdateCore.swift',
        ROOT / 'Tools/SigningIdentityCheck.swift', '-o', checker)

    endpoint = 'tags/v' + version(args.source_version) if args.source_version else 'latest'
    req = urllib.request.Request(API + endpoint, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'Faceprint-local-signing'})
    with OPENER.open(req, timeout=30) as response:
        data = response.read(2 * 1024 * 1024 + 1)
    if len(data) > 2 * 1024 * 1024:
        raise RuntimeError('Release metadata is too large')
    release = json.loads(data)
    if release.get('draft') or release.get('prerelease'):
        raise RuntimeError('A stable published source release is required')
    source = version(release['tag_name'])
    parts = [int(x) for x in source.split('.')]
    target = version(args.version) if args.version else f'{parts[0]}.{parts[1]}.{parts[2] + 1}'
    if tuple(map(int, target.split('.'))) <= tuple(parts):
        raise RuntimeError('The signed output version must be newer for in-app update testing')
    filename = f'Faceprint-{source}-macos-arm64.zip'
    assets = [x for x in release.get('assets', []) if x.get('name') == filename]
    if len(assets) != 1:
        raise RuntimeError('Expected exactly one compatible source archive')
    asset = assets[0]
    expected = asset.get('digest', '')
    if not re.fullmatch(r'sha256:[0-9a-fA-F]{64}', expected) or not (0 < asset.get('size', 0) <= MAX_ARCHIVE):
        raise RuntimeError('GitHub SHA-256 or archive size is invalid')
    expected_url = f'https://github.com/Er1cG1ao/Faceprint/releases/download/v{source}/{filename}'
    if asset.get('browser_download_url') != expected_url:
        raise RuntimeError('Unexpected repository download URL')
    if source == '1.6.0' and expected.lower() != 'sha256:3dbeeb2057c01a2e7afe85bcfb47166f9b2a27adbd238997dedc3a51980f2093':
        raise RuntimeError('The reviewed 1.6.0 source archive has changed')

    with tempfile.TemporaryDirectory(prefix='faceprint-signing-') as temporary:
        work = Path(temporary)
        archive = work / 'source.zip'
        digest = hashlib.sha256()
        count = 0
        print(f'Downloading verified Faceprint {source}…', flush=True)
        with OPENER.open(expected_url, timeout=120) as response, archive.open('wb') as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                count += len(chunk)
                if count > asset['size'] or count > MAX_ARCHIVE:
                    raise RuntimeError('Archive exceeds its expected size')
                digest.update(chunk)
                output.write(chunk)
        if count != asset['size'] or digest.hexdigest() != expected[7:].lower():
            raise RuntimeError('Source archive integrity check failed')
        run(checker, '--inspect-archive', archive)
        extracted = work / 'extracted'
        extracted.mkdir()
        run('/usr/bin/ditto', '-x', '-k', archive, extracted)
        app = extracted / 'Faceprint.app'
        run('/usr/bin/codesign', '--verify', '--strict', '--deep', app)
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleShortVersionString') != source or info.get('CFBundleIdentifier') != BUNDLE_ID:
            raise RuntimeError('Source bundle does not match the release')
        build = int(info['CFBundleVersion']) + 1
        stamp(app, target, build)
        sign(app, identity)
        baseline = ROOT / '.signing.requirement'
        run(checker, app, baseline)

        # Different Info.plist/version => different content and code hash, while
        # both apps must satisfy each other's unchanged signed requirements.
        probe = work / 'NextVersion.app'
        shutil.copytree(app, probe)
        next_parts = [int(x) for x in target.split('.')]
        next_version = f'{next_parts[0]}.{next_parts[1]}.{next_parts[2] + 1}'
        stamp(probe, next_version, build + 1)
        sign(probe, identity)
        run(checker, probe, baseline, app)

        output = args.output.expanduser() if args.output else Path.home() / 'Downloads' / (
            f'Faceprint-signed-{target}-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
        output.mkdir(parents=True, exist_ok=False)
        final_app = output / 'Faceprint.app'
        shutil.copytree(app, final_app)
        final_zip = output / f'Faceprint-{target}-macos-arm64.zip'
        run('/usr/bin/ditto', '-c', '-k', '--norsrc', '--noextattr', '--noqtn', '--keepParent', final_app, final_zip)
        run(checker, '--inspect-archive', final_zip)
        run('/usr/bin/codesign', '--verify', '--strict', '--deep', final_app)
        report = {'version': target, 'build': build, 'source_version': source,
                  'source_sha256': expected[7:].lower(), 'archive': final_zip.name,
                  'sha256': hashlib.sha256(final_zip.read_bytes()).hexdigest(),
                  'size': final_zip.stat().st_size, 'cross_version_identity_verified': True,
                  'private_keys_exported': False}
        (output / 'signing-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('\nSIGNED PACKAGE READY: ' + str(final_zip))
        print('Two different versions passed mutual signature-identity checks.')
        print('No private key was exported. Send only the signed ZIP and optional report for release upload.')
        print('The first ad hoc → certificate installation may still need one final permission grant.')

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print('Signing stopped: ' + str(error), file=sys.stderr)
        raise SystemExit(1)
