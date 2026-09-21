#!/usr/bin/env python3
"""Producer-only build: cross-compile Refine and retain source/license provenance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

def copy(src, dst):
    if dst.exists(): dst.chmod(0o644)
    shutil.copyfile(src, dst)
    dst.chmod(0o644)

root = Path(__file__).resolve().parents[2]
target = root / 'maven/refine-engine/target'
wasm = target / 'engine/refine.wasm'
wasm.parent.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, GOOS='wasip1', GOARCH='wasm', CGO_ENABLED='0')
subprocess.run(['go', 'build', '-trimpath', '-buildvcs=false', '-ldflags=-w -buildid=', '-o', str(wasm), './cmd/refine'], cwd=root, env=env, check=True)
raw = subprocess.check_output(['go', 'list', '-deps', '-json', './cmd/refine'], cwd=root, env=env, text=True)
decoder = json.JSONDecoder()
packages = []
while raw.strip():
    package, end = decoder.raw_decode(raw.lstrip())
    packages.append(package)
    raw = raw.lstrip()[end:]
source_dir = target / 'generated-sources/engine-inputs'
notice_dir = target / 'generated-resources/engine-notices/META-INF/refine-engine'
source_dir.mkdir(parents=True, exist_ok=True)
# Keep retained third-party/stdlib sources out of the root Go package traversal.
(source_dir / 'go.mod').write_text('module refine.engine.provenance\n\ngo 1.26.0\n')
notice_dir.mkdir(parents=True, exist_ok=True)
modules = {}
for package in packages:
    directory = Path(package['Dir'])
    destination = source_dir / package['ImportPath']
    destination.mkdir(parents=True, exist_ok=True)
    for name in package.get('GoFiles', []) + package.get('SFiles', []) + package.get('EmbedFiles', []):
        src = directory / name
        dst = destination / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        copy(src, dst)
        if name.endswith('_gp.go'):
            gp = directory / name.replace('_gp.go', '.gp')
            if gp.exists(): copy(gp, destination / gp.name)
    module = package.get('Module')
    if module and module.get('Dir'): modules[module['Path']] = module
modules['Go-standard-library'] = {'Dir': subprocess.check_output(['go', 'env', 'GOROOT'], text=True).strip(), 'Version': subprocess.check_output(['go', 'version'], text=True).strip()}
for name, module in modules.items():
    directory = Path(module['Dir'])
    destination = notice_dir / 'licenses' / name
    destination.mkdir(parents=True, exist_ok=True)
    found = False
    for pattern in ('LICENSE*', 'LICENCE*', 'COPYING*', 'NOTICE*', 'license*', 'licence*', 'notice*'):
        for src in directory.glob(pattern):
            if src.is_file(): copy(src, destination / src.name); found = True
    if not found: raise SystemExit('Missing license provenance: ' + name)
# Refine embeds the QuickJS regex guest, including its distribution notices.
for src in (root / 'internal/ecmaregex/guest').rglob('*'):
    if src.is_file() and ('LICENSE' in src.name or 'NOTICE' in src.name):
        dst = notice_dir / 'licenses/ecmaregex' / src.relative_to(root / 'internal/ecmaregex/guest')
        dst.parent.mkdir(parents=True, exist_ok=True); copy(src, dst)
manifest = {'format': 'refine-jvm-engine/v1', 'wasmSha256': hashlib.sha256(wasm.read_bytes()).hexdigest(), 'goVersion': modules['Go-standard-library']['Version'], 'modules': {k: v.get('Version', 'source-tree') for k, v in sorted(modules.items())}}
(notice_dir / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Prepared JVM engine input: ' + manifest['wasmSha256'])
