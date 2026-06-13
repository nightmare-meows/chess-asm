import pytest

pytest.importorskip("chess")

from driver import play
from oracle import rows

# Legal SAN sequences (no en passant — the engine omits it). The engine output
# must match python-chess move for move.
LEGAL = [
    pytest.param(["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "O-O", "Be7"], id="ruy-lopez-OO"),
    pytest.param(["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "g6"], id="sicilian"),
    pytest.param(["d4", "Nf6", "c4", "e6", "Nc3", "Bb4", "e3", "O-O", "Bd3", "d5"], id="nimzo-OO-black"),
    pytest.param(["d4", "d5", "Nf3", "Nf6", "Nbd2"], id="disambig-knight-file"),
    pytest.param(["Nf3", "d5", "Ng1", "d4", "Nf3"], id="disambig-knight-back"),
    pytest.param(["e4", "d5", "exd5"], id="pawn-capture"),
    pytest.param(["e4", "d5", "c4", "a6", "cxd5"], id="pawn-capture-file-c"),
    pytest.param(["e4", "d5", "c4", "a6", "exd5"], id="pawn-capture-file-e"),
    pytest.param(["e4", "d5", "exd5", "c6", "dxc6", "Nf6", "cxb7", "e6", "bxa8=Q"], id="promote-Q"),
    pytest.param(["e4", "d5", "exd5", "c6", "dxc6", "Nf6", "cxb7", "e6", "bxa8=N"], id="promote-N"),
    pytest.param(["Nc3", "d5", "d4", "Nf6", "Bf4", "e6", "Qd2", "Be7", "O-O-O"], id="queenside-castle"),
]


@pytest.mark.parametrize("sans", LEGAL)
def test_matches_oracle(sans):
    assert play(sans) == rows(sans)


# Each: a legal prefix, then one move the engine must REJECT (illegal or
# ambiguous). The board must stay at the prefix.
REJECT = [
    pytest.param(["e4", "e5"], "Qd5", id="queen-through-pawn"),
    pytest.param(["d4", "d5", "Nf3", "Nf6"], "Nd2", id="ambiguous-knight"),
    pytest.param(["e4", "d5", "c4", "a6"], "dxd5", id="ambiguous-pawn-capture"),
    pytest.param([], "O-O", id="castle-blocked"),
    pytest.param(["e4", "d5", "Bb5"], "a6", id="ignore-illegal-under-check"),
]


@pytest.mark.parametrize("prefix, bad", REJECT)
def test_rejects(prefix, bad):
    assert play(prefix + [bad]) == rows(prefix)


def test_promotion_default_is_queen():
    # engine auto-queens when '=' is omitted; oracle needs it spelled out
    sans = ["e4", "d5", "exd5", "c6", "dxc6", "Nf6", "cxb7", "e6"]
    assert play(sans + ["bxa8"]) == rows(sans + ["bxa8=Q"])
