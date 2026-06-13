import os, pty, select, time, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHESS = os.path.join(ROOT, "chess")

START = ["rnbqkbnr","pppppppp","........","........","........","........","PPPPPPPP","RNBQKBNR"]

PROMPT = "move "


def play(moves, timeout=2.0):
    """Drive ./chess over a pty.

    The engine renders one prompt per main-loop iteration, then blocks on
    read(). We send the next move only after the prompt count has advanced,
    so each move lands in its own read() (the engine parses one move per read).
    Returns the last rendered 8-row board.
    """
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(ROOT)
        os.execv(CHESS, [CHESS])
    buf = bytearray()

    def pump():
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                buf.extend(os.read(fd, 65536))
            except OSError:
                return False
        return True

    def wait_prompts(n):
        end = time.time() + timeout
        while time.time() < end:
            if buf.count(PROMPT.encode()) >= n:
                return
            if not pump():
                return

    wait_prompts(1)
    for i, m in enumerate(moves, 1):
        os.write(fd, (m + "\n").encode())
        wait_prompts(i + 1)
    os.write(fd, b"q\n")
    end = time.time() + 0.3
    while time.time() < end:
        pump()
    for closer in (lambda: os.close(fd), lambda: os.waitpid(pid, 0)):
        try:
            closer()
        except OSError:
            pass

    txt = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", buf.decode("latin1"))
    rows = re.findall(r"^[1-8] \| (.{15}) \|", txt, re.M)
    return [r.replace(" ", "") for r in rows[-8:]]
