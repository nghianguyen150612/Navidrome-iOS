#!/usr/bin/env python3
"""Offline P001 contract checks. Does not build, install or run Navidrome."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/ios'
BASE = '101145742f4762164202cb4858c9126258bdc463'
DOCUMENTS = {'ARCHITECTURE.md', 'COMPATIBILITY.md', 'BUILD_PLAN.md',
             'INSTALLER_CONTRACT.md', 'ROADMAP.md', 'P001_MANIFEST.md', 'audit.json'}
ALLOWED = {'docs/ios/' + name for name in DOCUMENTS} | {
    'scripts/ios/validate_p001.py', '.github/workflows/ios-p001.yml'}


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def require(condition, message):
    if not condition:
        raise SystemExit('FAIL: ' + message)


def main():
    audit = json.loads((DOCS / 'audit.json').read_text())
    require(audit['baseline_sha'] == BASE and audit['baseline_tag'] == 'v0.64.2',
            'unexpected baseline')
    require(git('rev-parse', 'v0.64.2^{commit}').decode().strip() == BASE,
            'tag does not resolve to baseline')
    require(subprocess.call(['git', '-C', str(ROOT), 'merge-base', '--is-ancestor',
                             BASE, 'HEAD']) == 0, 'baseline is not an ancestor')
    # Include index, tracked working tree and new files so local pre-commit runs
    # cannot hide an accidental source edit behind staging choices.
    changed = set(git('diff', '--name-only', '-z', BASE).decode().split('\0'))
    changed.update(git('ls-files', '--others', '--exclude-standard', '-z').decode().split('\0'))
    changed.discard('')
    require(changed <= ALLOWED, 'out-of-scope changes: ' + repr(sorted(changed - ALLOWED)))
    for path, digest in audit['baseline_files'].items():
        require(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest,
                'baseline file hash changed: ' + path)
        require(hashlib.sha256(git('show', BASE + ':' + path)).hexdigest() == digest,
                'inventory hash disagrees with baseline: ' + path)
    mod = (ROOT / 'go.mod').read_text()
    modules = []
    for line in mod.splitlines():
        match = re.match(r'\s+([^\s]+)\s+(v\S+)(.*)$', line)
        if match:
            modules.append(dict(module=match[1], version=match[2],
                                indirect='// indirect' in match[3]))
    require(modules == audit['modules'], 'module inventory drift')
    require([s for s in mod.splitlines() if s.startswith('replace ')] == audit['replacements'],
            'replacement inventory drift')
    require(re.search(r'^go ' + re.escape(audit['go_directive']) + r'$', mod, re.M),
            'Go directive drift')
    for name in DOCUMENTS:
        path = DOCS / name
        require(path.is_file() and path.stat().st_size > 100, 'missing/empty document: ' + name)
        if path.suffix == '.md':
            text = path.read_text()
            require(not re.search(r'\b(TODO|TBD|FIXME)\b', text), 'unfinished placeholder: ' + name)
            for link in re.findall(r'\]\(([^)]+)\)', text):
                if '://' not in link:
                    require((path.parent / link.split('#')[0]).exists(), 'broken link: ' + link)
    contract = (DOCS / 'INSTALLER_CONTRACT.md').read_text()
    for path in ['/usr/local/bin/navidrome', '/usr/local/bin/navidrome-ios',
                 '/usr/local/bin/nd', '/var/lib/navidrome-ios/manager.sh',
                 '/var/lib/navidrome-ios/install-state',
                 '/var/lib/navidrome-ios/config/navidrome.toml',
                 '/var/lib/navidrome-ios/backup/',
                 '/Library/LaunchDaemons/com.navidrome.ios.plist',
                 '/var/log/navidrome-ios/', '/private/var/mnt/Music', '/mnt/Music',
                 '/private/var/mnt/Music/library', '/private/var/mnt/Music/data',
                 '/private/var/mnt/Music/cache']:
        require(path in contract, 'missing canonical path: ' + path)
    require('127.0.0.1' in contract and '4533' in contract, 'missing network defaults')
    rows = re.findall(r'^\| P(\d{3}) \| (.*?) \| (.*?) \| (.*?) \|$',
                      (DOCS / 'ROADMAP.md').read_text(), re.M)
    require([int(row[0]) for row in rows] == list(range(1, 25)), 'roadmap must contain P001–P024')
    for number, scope, dependencies, gate in rows:
        require(len(scope) > 5 and len(gate) > 20, 'missing acceptance gate: ' + number)
        require(all(int(dep) < int(number) for dep in re.findall(r'P(\d{3})', dependencies)),
                'roadmap has forward/circular dependency: ' + number)
    subprocess.run(['git', '-C', str(ROOT), 'diff', '--check', BASE], check=True)
    print('PASS: baseline ancestry, P001 isolation, source hashes, complete module inventory,')
    print('      document links, canonical paths/network defaults, roadmap gates, diff hygiene')
    print('NOT TESTED: Apple build, iPad runtime, installer and application behavior')


if __name__ == '__main__':
    main()
