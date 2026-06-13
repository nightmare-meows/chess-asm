"""Ground-truth board states via python-chess, in the engine's row format.

board_fen() already emits rank-8-first, white-uppercase placement; we only
expand digit run-lengths to '.' so it matches what the engine renders.
"""
import chess


def rows(sans):
    b = chess.Board()
    for s in sans:
        b.push_san(s)
    out = []
    for part in b.board_fen().split("/"):
        row = ""
        for c in part:
            row += "." * int(c) if c.isdigit() else c
        out.append(row)
    return out
