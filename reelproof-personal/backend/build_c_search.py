"""Compile the C search on the deployment target; runtime compilation is unused."""
import ctypes
import os
from pathlib import Path
import platform
import shlex
import subprocess

ROOT = Path(__file__).resolve().parent

def build():
    system = platform.system()
    suffix = '.dll' if system == 'Windows' else '.dylib' if system == 'Darwin' else '.so'
    target = ROOT / ('_reelproof_scan' + suffix)
    compiler = shlex.split(os.environ.get('CC', 'cc'))
    flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror']
    if system != 'Windows': flags += ['-fPIC']
    flags += ['-dynamiclib' if system == 'Darwin' else '-shared']
    subprocess.run(compiler + flags + [str(ROOT/'sequential_search.c'), '-lm', '-o', str(target)], check=True)
    library = ctypes.CDLL(str(target))
    library.rp_scan_implementation.restype = ctypes.c_char_p
    assert library.rp_scan_implementation() == b'c-sequential-cosine-v1'
    print('Built and loaded C sequential search:', target.name)

if __name__ == '__main__': build()
