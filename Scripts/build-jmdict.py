#!/usr/bin/env python3
"""Convert JMdict_e (EDRDG) into the compact SQLite the app bundles.

Usage:
  curl -L -o /tmp/JMdict_e.gz http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz
  gunzip -f /tmp/JMdict_e.gz
  python3 Scripts/build-jmdict.py /tmp/JMdict_e Resources/dict/jmdict.sqlite

Schema (optimised for one indexed lookup per tap):
  forms(form TEXT, entry_id INT)          -- every kanji + kana writing
  entries(id INT PK, kanji TEXT, kana TEXT, common INT, senses TEXT)
    senses: one line per sense, "pos<TAB>gloss; gloss; ..."

JMdict is property of the Electronic Dictionary Research and Development
Group, used under the Group's licence (CC BY-SA 4.0). Keep the attribution
in the app's Settings screen.
"""

import sqlite3
import sys
import xml.etree.ElementTree as ET

COMMON_PRI = {"news1", "ichi1", "spec1", "spec2", "gai1"}


def main(src: str, dst: str) -> None:
    db = sqlite3.connect(dst)
    db.executescript(
        """
        DROP TABLE IF EXISTS forms;
        DROP TABLE IF EXISTS entries;
        CREATE TABLE entries (id INTEGER PRIMARY KEY, kanji TEXT, kana TEXT,
                              common INTEGER, senses TEXT);
        CREATE TABLE forms (form TEXT NOT NULL, entry_id INTEGER NOT NULL);
        """
    )

    n = 0
    for _, entry in ET.iterparse(src, events=("end",)):
        if entry.tag != "entry":
            continue
        eid = int(entry.findtext("ent_seq"))

        kanji = [k.findtext("keb") for k in entry.findall("k_ele")]
        kana = [r.findtext("reb") for r in entry.findall("r_ele")]
        pris = [p.text for el in ("k_ele", "r_ele")
                for e in entry.findall(el) for p in e.findall(f"{el[0]}e_pri")]
        common = 1 if any(p in COMMON_PRI for p in pris) else 0

        sense_lines = []
        for sense in entry.findall("sense"):
            pos = "; ".join(p.text or "" for p in sense.findall("pos"))
            glosses = "; ".join(g.text or "" for g in sense.findall("gloss"))
            if glosses:
                sense_lines.append(f"{pos}\t{glosses}")
        if not sense_lines:
            entry.clear()
            continue

        db.execute(
            "INSERT INTO entries VALUES (?, ?, ?, ?, ?)",
            (eid, "; ".join(kanji), "; ".join(kana), common, "\n".join(sense_lines)),
        )
        db.executemany(
            "INSERT INTO forms VALUES (?, ?)",
            [(f, eid) for f in dict.fromkeys(kanji + kana)],
        )

        entry.clear()
        n += 1
        if n % 20000 == 0:
            print(f"  {n} entries…", flush=True)

    db.execute("CREATE INDEX ix_forms ON forms(form)")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"done: {n} entries -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
