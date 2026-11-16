#!/usr/bin/env python3
"""Genera Changelog.lua (pestaña Changelog del juego) desde CHANGELOG.md."""
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
md = (root / "CHANGELOG.md").read_text(encoding="utf-8")
body = md.split("\n", 1)[1].strip() if md.startswith("# ") else md.strip()
assert "]]" not in body
(root / "Changelog.lua").write_text(
    "-- Generado desde CHANGELOG.md por tools/gen_changelog.py (no editar a mano)\n"
    "local ADDON, ns = ...\n"
    "ns.CHANGELOG = [[\n" + body + "\n]]\n", encoding="utf-8")
print("Changelog.lua actualizado")
