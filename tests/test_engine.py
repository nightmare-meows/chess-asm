import pytest
from driver import play, START

# 1.d4 e6 2.Nd2 Bb4 — black bishop pins the d2 knight to the white king on e1
PIN = ["d2d4", "e7e6", "b1d2", "f8b4"]
PIN_BOARD = ["rnbqk.nr","pppp.ppp","....p...","........",".b.P....","........","PPPNPPPP","R.BQKBNR"]
BB5 = ["e2e4", "d7d5", "f1b5"]
BB5_BOARD = ["rnbqkbnr","ppp.pppp","........",".B.p....","....P...","........","PPPP.PPP","RNBQK.NR"]


@pytest.mark.parametrize("moves, expect", [
    # geometry + turn order
    (["e2e5"], START),                              # pawn cannot jump 3
    (["e7e5"], START),                              # black cannot move first
    (["f1c4"], START),                              # bishop blocked by own pawn
    (["g1f3"], ["rnbqkbnr","pppppppp","........","........","........",".....N..","PPPPPPPP","RNBQKB.R"]),
    # captures
    (["e2e4","d7d5","e4d5"], ["rnbqkbnr","ppp.pppp","........","...P....","........","........","PPPP.PPP","RNBQKBNR"]),
    (["e2e4","a7a6","e4d5"], ["rnbqkbnr",".ppppppp","p.......","........","....P...","........","PPPP.PPP","RNBQKBNR"]),
    # pin / self-check
    (PIN, PIN_BOARD),
    (PIN + ["d2f3"], PIN_BOARD),                    # pinned knight may not move
    (PIN + ["c2c3"], ["rnbqk.nr","pppp.ppp","....p...","........",".b.P....","..P.....","PP.NPPPP","R.BQKBNR"]),
    # check + responses
    (BB5, BB5_BOARD),
    (BB5 + ["a7a6"], BB5_BOARD),                    # illegal reply leaves king in check
    (BB5 + ["c7c6"], ["rnbqkbnr","pp..pppp","..p.....",".B.p....","....P...","........","PPPP.PPP","RNBQK.NR"]),
])
def test_position(moves, expect):
    assert play(moves) == expect
