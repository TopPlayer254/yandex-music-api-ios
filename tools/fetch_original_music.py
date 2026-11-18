"""Extract a pinned official Apple Music bundle with HTTP ranges, on macOS CI."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess

ROOT=Path(__file__).resolve().parents[1]
IPSW_COMMIT='d53e699459d2c45799efc17ddf5b63b65b41ac7e'
URL='https://updates.cdn-apple.com/2026SpringFCS/fullrestores/122-88894/CF6FDC3F-3E68-4ADE-85AA-390E18FCE138/iPhone18,1_26.5.1_23F81_Restore.ipsw'
EXPECTED='1111db60f9e19436b30f732dde0f9d0cbaf0b1127bee1d3ca3bee33ba3dedd2a'

def run(*command,cwd=None):
    subprocess.run(command,cwd=cwd,check=True)

def main(destination):
    destination=destination.resolve()
    app=destination/'23F81__iPhone18,1/private/var/staged_system_apps/Music.app'
    if not (app/'Music').exists():
        tools=destination/'tools'
        tools.mkdir(parents=True,exist_ok=True)
        source=tools/'ipsw'
        if not source.exists():
            run('git','init',str(source))
            run('git','-C',str(source),'remote','add','origin','https://github.com/blacktop/ipsw.git')
            run('git','-C',str(source),'fetch','--depth','1','origin',IPSW_COMMIT)
            run('git','-C',str(source),'checkout','--detach','FETCH_HEAD')
        run('go','mod','download','github.com/blacktop/go-apfs@v1.0.32',cwd=source)
        modules=Path(subprocess.check_output(['go','env','GOMODCACHE'],text=True).strip())
        apfs=tools/'go-apfs'
        if not apfs.exists():
            shutil.copytree(modules/'github.com/blacktop/go-apfs@v1.0.32',apfs)
            apfs.chmod(apfs.stat().st_mode|stat.S_IWUSR)
            for path in apfs.rglob('*'):
                path.chmod(path.stat().st_mode|stat.S_IWUSR)
            run('patch','-p1','-i',str(ROOT/'MusicBridge/Extract/resource-zlib.patch'),cwd=apfs)
        run('go','mod','edit','-replace','github.com/blacktop/go-apfs='+str(apfs),cwd=source)
        command=source/'cmd/kreshka-extract'
        command.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/'MusicBridge/Extract/main.go',command/'main.go')
        binary=tools/'kreshka-extract'
        run('go','build','-o',str(binary),'./cmd/kreshka-extract',cwd=source)
        run(str(binary),URL,str(destination))
    if hashlib.sha256((app/'Music').read_bytes()).hexdigest()!=EXPECTED:
        raise RuntimeError('Original Music binary checksum mismatch')
    if not (app/'Assets.car').exists(): raise RuntimeError('Incomplete original Music bundle')
    print(app)
    if os.environ.get('GITHUB_ENV'):
        with open(os.environ['GITHUB_ENV'],'a') as output: output.write('ORIGINAL_MUSIC_APP='+str(app)+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination',type=Path)
    main(parser.parse_args().destination)
