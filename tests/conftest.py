import os, subprocess
import pytest
from driver import ROOT, CHESS


@pytest.fixture(scope="session", autouse=True)
def build():
    src = os.path.join(ROOT, "chess.asm")
    obj = os.path.join(ROOT, "chess.o")
    stale = (not os.path.exists(CHESS)
             or os.path.getmtime(CHESS) < os.path.getmtime(src))
    if stale:
        subprocess.run(["nasm", "-w-implicit-abs", "-f", "elf64", src, "-o", obj],
                       check=True, cwd=ROOT)
        subprocess.run(["ld", obj, "-o", CHESS], check=True, cwd=ROOT)
