import os, mmap, struct, time, subprocess, signal
import pytest
from driver import ROOT, START

CHESS = os.path.join(ROOT, "chess")
CHESSMOVE = os.path.join(ROOT, "chessmove")
SHM = "/dev/shm/chess.state"
MQ = "/dev/mqueue/chess.moves"


def _build(name):
    src = os.path.join(ROOT, name + ".asm")
    obj = os.path.join(ROOT, name + ".o")
    out = os.path.join(ROOT, name)
    stale = (not os.path.exists(out)
             or os.path.getmtime(out) < os.path.getmtime(src))
    if stale:
        subprocess.run(["nasm", "-w-implicit-abs", "-f", "elf64", src, "-o", obj],
                       check=True, cwd=ROOT)
        subprocess.run(["ld", obj, "-o", out], check=True, cwd=ROOT)


def read_state(buf):
    while True:
        s1 = struct.unpack_from("<Q", buf, 8)[0]
        if s1 & 1:
            continue
        snap = bytes(buf[:256])
        s2 = struct.unpack_from("<Q", buf, 8)[0]
        if s1 == s2:
            return s1, snap


def decode(snap):
    board = snap[40:104]
    rows = ["".join(chr(board[r * 8 + c]) for c in range(8)) for r in range(8)]
    return {
        "stm": snap[16],
        "result": snap[17],
        "reject_color": snap[18],
        "ply": struct.unpack_from("<I", snap, 20)[0],
        "reject_seq": struct.unpack_from("<Q", snap, 24)[0],
        "last_move": snap[32:40].rstrip(b"\x00").decode(),
        "rows": rows,
    }


def wait_seq(buf, prev, timeout=2.0):
    end = time.time() + timeout
    while time.time() < end:
        s, snap = read_state(buf)
        if s != prev:
            return s, snap
        time.sleep(0.01)
    raise AssertionError("seq did not advance")


def send(color, move):
    subprocess.run([CHESSMOVE, color, move], check=True, cwd=ROOT)


@pytest.fixture
def arbiter():
    _build("chessmove")
    for p in (SHM,):
        try:
            os.unlink(p)
        except OSError:
            pass
    proc = subprocess.Popen([CHESS, "--serve"], cwd=ROOT)
    # wait for shm + initial publish
    end = time.time() + 3.0
    fd = None
    while time.time() < end:
        if os.path.exists(SHM):
            fd = os.open(SHM, os.O_RDONLY)
            buf = mmap.mmap(fd, 256, mmap.MAP_SHARED, mmap.PROT_READ)
            if buf[:4] == b"CHS1" and struct.unpack_from("<Q", buf, 8)[0] >= 2:
                yield buf
                buf.close()
                os.close(fd)
                break
            buf.close()
            os.close(fd)
        time.sleep(0.02)
    else:
        proc.kill()
        proc.wait()
        raise AssertionError("arbiter did not initialize shm")
    proc.send_signal(signal.SIGKILL)
    proc.wait()
    try:
        os.unlink(SHM)
    except OSError:
        pass


def test_initial(arbiter):
    _, snap = read_state(arbiter)
    st = decode(snap)
    assert snap[:4] == b"CHS1"
    assert st["rows"] == START
    assert st["stm"] == 0
    assert st["result"] == 0
    assert st["ply"] == 0


def test_full_game(arbiter):
    buf = arbiter
    s, snap = read_state(buf)

    send("W", "e2e4")
    s, snap = wait_seq(buf, s)
    st = decode(snap)
    assert st["stm"] == 1
    assert st["ply"] == 1
    assert st["last_move"] == "e2e4"
    assert st["rows"][4] == "....P..."
    assert st["reject_color"] == 0

    send("B", "c7c5")
    s, snap = wait_seq(buf, s)
    st = decode(snap)
    assert st["stm"] == 0
    assert st["ply"] == 2
    assert st["rows"][3] == "..p....."

    send("W", "g1f3")
    s, snap = wait_seq(buf, s)
    st = decode(snap)
    assert st["stm"] == 1
    assert st["ply"] == 3
    assert st["last_move"] == "g1f3"


def test_out_of_turn(arbiter):
    buf = arbiter
    s, snap = read_state(buf)
    rej0 = decode(snap)["reject_seq"]
    # black to move? no, white. Submit black -> wrong color
    send("B", "e7e5")
    s, snap = wait_seq(buf, s)
    st = decode(snap)
    assert st["reject_seq"] == rej0 + 1
    assert st["reject_color"] == 2
    assert st["stm"] == 0
    assert st["ply"] == 0
    assert st["rows"] == START


def test_illegal(arbiter):
    buf = arbiter
    s, snap = read_state(buf)
    rej0 = decode(snap)["reject_seq"]
    # white's turn, illegal pawn jump
    send("W", "e2e5")
    s, snap = wait_seq(buf, s)
    st = decode(snap)
    assert st["reject_seq"] == rej0 + 1
    assert st["reject_color"] == 1
    assert st["stm"] == 0
    assert st["ply"] == 0
    assert st["rows"] == START
    # reject cleared on next accepted move
    send("W", "e2e4")
    s, snap = wait_seq(buf, s)
    st = decode(snap)
    assert st["reject_color"] == 0
    assert st["ply"] == 1
