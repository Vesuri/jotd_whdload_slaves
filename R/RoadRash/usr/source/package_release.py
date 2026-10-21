#!/usr/bin/env python3
"""Build and verify a fresh installer archive; no original game data is included."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parent
USR = SOURCE.parent
ORIGINAL_SHA256 = 'c84bb5732a14c76dbe28a22366c476bb4f2f199e7833bbdedffc485d5cb49d23'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def manifest(root):
    return {p.relative_to(root).as_posix(): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}

def validate_install(text):
    depth = 0
    quoted = comment = escape = False
    code = []
    for c in text:
        if comment:
            if c == '\n': comment = False
        elif quoted:
            if escape: escape = False
            elif c == '\\': escape = True
            elif c == '"': quoted = False
        elif c == ';': comment = True
        elif c == '"': quoted = True
        else:
            code.append(c)
            if c == '(': depth += 1
            elif c == ')': depth -= 1
            if depth < 0: raise ValueError('unbalanced Installer expression')
    if depth or quoted: raise ValueError('unterminated Installer expression/string')
    text = ''.join(code)
    definitions = set(re.findall(r'\(procedure\s+(\w+)', text))
    calls = set(re.findall(r'\((P_\w+|PDI_\w+)\b', text))
    if calls - definitions: raise ValueError('undefined procedures: ' + str(calls - definitions))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--original', type=Path, required=True, help='Original version 2.0 installer archive')
    parser.add_argument('--output', type=Path, required=True, help='Fresh output directory')
    args = parser.parse_args()
    original, out = args.original.resolve(), args.output.resolve()
    if sha(original) != ORIGINAL_SHA256: raise ValueError('unexpected original installer archive')
    if out.exists(): raise ValueError('output already exists; choose a fresh directory')
    out.mkdir(parents=True)
    share = Path(os.environ.get('AMIGA_SHARE', Path.home() / '.local/share/amiga'))
    vasm = os.environ.get('VASM', str(Path.home() / '.local/vasmm68k_mot'))
    lha = os.environ.get('LHA', str(share / 'lha-compressor/src/lha'))
    slave = out / 'RoadRash.slave'
    subprocess.run([vasm, '-quiet', '-devpac', '-nosym', '-Fhunkexe', '-pic',
                    '-I' + str(share / 'WHDLoad/Include'), '-I' + str(share / 'WHDLoad/Src'),
                    '-I' + str(share / 'ndk/Include_I'), '-I.', '-o', str(slave), 'RoadRashHD.s'],
                   cwd=SOURCE, check=True)
    data = slave.read_bytes()
    match = re.search(rb'\$VER: RoadRash ([0-9.]+[a-z]?) \((\d{2}\.\d{2}\.\d{4})\)\0', data)
    if not match: raise ValueError('missing release version/date')
    version, date = (s.decode('ascii') for s in match.groups())
    if f'Version {version} ({date})'.encode() not in (USR / 'Readme').read_bytes():
        raise ValueError('Readme and slave version/date disagree')
    if b'C2:B:Enhanced framerate;' not in data: raise ValueError('missing boolean option')
    if b'RRA1STAT' in data: raise ValueError('diagnostic build is not releasable')
    validate_install((USR / 'Install').read_text(encoding='latin1'))
    stage = out / 'stage'
    stage.mkdir()
    # Input is pinned, so archive names and lack of links are already known.
    subprocess.run([lha, 'xq2', str(original)], cwd=stage, check=True)
    before = manifest(stage)
    drawer = stage / 'RoadRashHD'
    for name in ['Install', 'Readme']: shutil.copyfile(USR / name, drawer / name)
    shutil.copyfile(slave, drawer / 'RoadRash.slave')
    # Replace stale bundled sources with the complete source for this release.
    shutil.rmtree(drawer / 'source')
    (drawer / 'source').mkdir()
    for p in sorted(SOURCE.iterdir()):
        if p.suffix in ('.s', '.md') or p.name in ('Makefile', 'package_release.py'):
            shutil.copyfile(p, drawer / 'source' / p.name)
    expected = manifest(stage)
    # Only these three runtime members and the source directory intentionally change.
    allowed = {'RoadRashHD/Install', 'RoadRashHD/Readme', 'RoadRashHD/RoadRash.slave'}
    changed = {n for n in before.keys() | expected.keys() if before.get(n) != expected.get(n)}
    if any(n not in allowed and not n.startswith('RoadRashHD/source/') for n in changed):
        raise ValueError('unexpected original member change')
    # Shared writer owns portable generic headers; UNIX LHa supplies LH5 payloads.
    # This avoids host ownership, locale, timestamps and directory separators.
    sys.path.insert(0, str(share / 'pylib'))
    from amigaxdev.release import member, dos_stamp, check_names
    check_names(expected)
    day, month, year = map(int, date.split('.'))
    archive = out / f'RoadRash_v{version}.lha'
    os.environ['LHA'] = lha
    archive.write_bytes(b''.join(member(name, (stage / name).read_bytes(),
                                       dos_stamp(year, month, day))
                                 for name in expected) + b'\0')
    subprocess.run([lha, 'tq2', str(archive)], check=True, stdout=subprocess.DEVNULL)
    extracted = out / 'extracted'
    extracted.mkdir()
    # Independent decoder, not the compressor used above.
    subprocess.run(['lha', 'xq', str(archive)], cwd=extracted, check=True)
    if manifest(extracted) != expected: raise ValueError('extracted archive differs from staging')
    report = dict(version=version, date=date, archive=archive.name, sha256=sha(archive),
                  slave_sha256=sha(slave), original_sha256=sha(original),
                  changed_members=sorted(changed), files=expected)
    (out / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    print(archive)

if __name__ == '__main__': main()
