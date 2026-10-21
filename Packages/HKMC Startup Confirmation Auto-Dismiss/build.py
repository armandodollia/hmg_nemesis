"""Build installable NEMESIS v4.2 package + USB-ready ZIP from this directory."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED, ZipInfo

root = Path(__file__).resolve().parent
out = root.parent
stem = 'hkmc.factory82.bootready-v4.2'
files = ['NEMESIS.data','README.md','svc/watch.sh','scripts/preuninstall.sh','bin/diagnostics.sh']

def write_file(zipout, member, data, executable=False):
    info = ZipInfo(member, (2026,10,15,0,0,0))
    info.create_system = 3
    info.external_attr = ((0o100755 if executable else 0o100644) << 16)
    info.compress_type = ZIP_DEFLATED
    zipout.writestr(info, data)

pkg = out / (stem + '.nemesis.zip')
with ZipFile(pkg, 'w') as z:
    for path in files:
        write_file(z, path, (root/path).read_bytes(), path.endswith('.sh'))

usb = out / (stem + '.USB.zip')
with ZipFile(usb, 'w') as z:
    write_file(z, 'NEMESIS.data',
               ('[nemesis]\nversion=4.2\ntype=install\npath=packages/' + pkg.name + '\n').encode())
    write_file(z, 'packages/' + pkg.name, pkg.read_bytes())

source = out / (stem + '.source.zip')
with ZipFile(source, 'w') as z:
    for path in files + ['build.py','tests/test_watcher.py','tests/test_fast_path.py','tests/test_boot_readiness.py']:
        write_file(z, path, (root/path).read_bytes(), path.endswith(('.sh','.py')))
for p in (pkg,usb,source):
    print(p, p.stat().st_size)
