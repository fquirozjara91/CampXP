#!/usr/bin/env python3
"""Pasa lo descubierto en el juego (/cxp dev on) al registro del addon.

Uso:
    python3 tools/import_discoveries.py <ruta a WTF/.../SavedVariables/CampXP.lua> [--write]

Sin --write solo muestra el informe. Con --write:
  - comidas nuevas (XP o Well Fed)      > bloque DISCOVERED de Foods.lua
  - consumibles nuevos (sin grupo)       > un grupo propio en el bloque DISCOVERED de Consumables.lua
Lo que necesita revisión (ítems de grupos sin confirmar, piedras/aceites y buffs que
no se acumulan) solo se informa: se edita a mano en Consumables.lua.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------- lector de SavedVariables
class LuaReader:
    TOKEN = re.compile(r'\s*(?:--[^\n]*\n\s*)*(\[\[|\{|\}|\[|\]|=|,|;|"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?|[A-Za-z_][A-Za-z0-9_]*)')

    def __init__(self, text):
        self.toks = [m.group(1) for m in self.TOKEN.finditer(text)]
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def next(self):
        t = self.peek()
        self.i += 1
        return t

    def value(self):
        t = self.next()
        if t == "{":
            return self.table()
        if t.startswith('"'):
            return bytes(t[1:-1], "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
        if t in ("true", "false"):
            return t == "true"
        if t == "nil":
            return None
        try:
            return int(t)
        except ValueError:
            return float(t)

    def table(self):
        out, n = {}, 1
        while self.peek() != "}":
            if self.peek() == "[":
                self.next()
                k = self.value()
                self.next()  # ]
                self.next()  # =
                out[k] = self.value()
            elif self.i + 1 < len(self.toks) and self.toks[self.i + 1] == "=" and re.match(r"[A-Za-z_]", self.peek()):
                k = self.next()
                self.next()
                out[k] = self.value()
            else:
                out[n] = self.value()
                n += 1
            if self.peek() in (",", ";"):
                self.next()
        self.next()
        return out

    def globals(self):
        g = {}
        while self.peek():
            name = self.next()
            if self.next() != "=":
                break
            g[name] = self.value()
        return g


# ---------------------------------------------------------------- registro actual
def registry_items(text):
    """IDs de ítems ya presentes en ns.CONS_DB."""
    ids = set()
    for m in re.finditer(r"items\s*=\s*\{([^}]*)\}", text):
        ids.update(int(x) for x in re.findall(r"\d+", re.sub(r"--[^\n]*", "", m.group(1))))
    return ids


def block(text, name):
    m = re.search(r"(-- BEGIN DISCOVERED\n)(.*?)(\s*-- END DISCOVERED)", text, re.S)
    if not m:
        sys.exit(f"{name}: no encuentro el bloque BEGIN/END DISCOVERED")
    return m


def replace_block(text, m, lines, indent="    "):
    body = "".join(indent + l + "\n" for l in lines)
    return text[: m.start(2)] + body + indent + "-- END DISCOVERED" + text[m.end(3):]


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    if not args:
        sys.exit(__doc__)
    sv = LuaReader(Path(args[0]).read_text(encoding="utf-8")).globals()
    disc = (sv.get("CampXPDB") or {}).get("discovered") or {}
    cons, foods, pairs = disc.get("cons") or {}, disc.get("food") or {}, disc.get("pairs") or {}

    cons_path, food_path = ROOT / "Consumables.lua", ROOT / "Foods.lua"
    ctext, ftext = cons_path.read_text(encoding="utf-8"), food_path.read_text(encoding="utf-8")
    in_registry = registry_items(ctext)
    known_food = {int(x) for x in re.findall(r"^\s*\[(\d+)\]\s*=", ftext, re.M)}

    # ------------------------------------------------------------ comidas
    new_food = []
    for fid, f in sorted(foods.items()):
        if fid in known_food or not (f.get("xp") or f.get("wf")):
            continue
        parts = []
        if f.get("xp"):
            parts.append(f"xp = {f['xp']}")
        if f.get("wf"):
            parts.append("wf = true")
        if f.get("keys"):
            keys = [f["keys"][i] for i in sorted(f["keys"])]
            parts.append("keys = { " + ", ".join(lua_str(k) for k in keys) + " }")
        new_food.append((fid, f"[{fid}] = {{ {', '.join(parts)} }}, -- {f.get('name') or '?'}"))

    # ------------------------------------------------------------ consumibles
    new_cons, review, confirm = [], [], set()
    for iid, e in sorted(cons.items()):
        name = e.get("name") or "?"
        if e.get("weapon"):
            review.append(f"piedra/aceite: {name} ({iid}) > {e.get('wtext')}  (se detecta solo; no va al registro)")
            continue
        if iid in in_registry and not e.get("group"):
            continue  # ya está en el bloque de descubiertos
        if iid in in_registry and e.get("group") and (not e.get("aura") or e.get("aura") == e.get("use")):
            confirm.add(e["group"])
            continue
        if iid in in_registry:
            review.append(f"confirmar: {name} ({iid}) del grupo '{e.get('group')}' deja {e.get('auraName')} ({e.get('aura')})"
                          + ("" if e.get("aura") == e.get("use") else f"  [aura distinta del Usar {e.get('use')}: añadir auras = {{ {e.get('aura')} }}]"))
            continue
        auras = "" if not e.get("aura") or e.get("aura") == e.get("use") else f", auras = {{ {e['aura']} }}"
        dur = f", {round(e['dur'] / 60)} min" if e.get("dur") else ""
        new_cons.append((iid, f'{{ key = "d{iid}", confirmed = true, items = {{ {iid} }}{auras} }}, -- {name} > {e.get("auraName")} ({e.get("aura")}{dur})'))

    # grupos que ya están confirmados en el registro
    already = set(re.findall(r'key\s*=\s*"(\w+)"\s*,[^}\n]*confirmed\s*=\s*true', ctext))
    confirm -= already

    # ------------------------------------------------------------ informe
    print(f"Grupos a confirmar (buff visto en el juego): {len(confirm)}")
    for g in sorted(confirm):
        print("  " + g)
    print(f"Comidas nuevas: {len(new_food)}")
    for _, l in new_food:
        print("  " + l)
    print(f"Consumibles nuevos: {len(new_cons)}")
    for _, l in new_cons:
        print("  " + l)
    print(f"Para revisar: {len(review)}")
    for l in review:
        print("  " + l)
    print(f"No se acumulan (agrupar a mano): {len(pairs)}")
    for p in pairs.values():
        who = "buff de otro jugador" if p.get("other") else f"ítem {p.get('lostItem') or '?'}"
        print(f"  {p.get('itemName')} ({p.get('item')}) reemplazó {p.get('lostName')} ({p.get('lost')}, {who}) x{p.get('n')}")

    if not write:
        print("\n(solo informe: usa --write para escribir Foods.lua y Consumables.lua)")
        return
    if new_food:
        m = block(ftext, "Foods.lua")
        old = [l.strip() for l in m.group(2).splitlines() if l.strip()]
        food_path.write_text(replace_block(ftext, m, old + [l for _, l in new_food]), encoding="utf-8")
    for g in confirm:
        ctext = re.sub(r'(\{\s*key\s*=\s*"' + g + r'"\s*,)', r'\1 confirmed = true,', ctext, count=1)
        ctext = re.sub(r'(key\s*=\s*"' + g + r'"\s*, confirmed = true,)\s*(label\s*=\s*[^,]+,)\s*confirmed\s*=\s*true,', r'\1 \2', ctext)
    if confirm and not new_cons:
        cons_path.write_text(ctext, encoding="utf-8")
    if new_cons:
        m = block(ctext, "Consumables.lua")
        old = [l.strip() for l in m.group(2).splitlines() if l.strip()]
        cons_path.write_text(replace_block(ctext, m, old + [l for _, l in new_cons]), encoding="utf-8")
    print("\nEscrito.")


if __name__ == "__main__":
    main()
