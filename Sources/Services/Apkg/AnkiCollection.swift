import Foundation

/// The Anki collection SQLite schema and the `col` JSON blobs (conf / models /
/// decks / dconf). Ported verbatim from server/src/lib/apkg.ts so decks import
/// identically to the desktop export.
enum AnkiCollection {
    static let schema = """
    CREATE TABLE col (
      id INTEGER PRIMARY KEY, crt INTEGER NOT NULL, mod INTEGER NOT NULL,
      scm INTEGER NOT NULL, ver INTEGER NOT NULL, dty INTEGER NOT NULL,
      usn INTEGER NOT NULL, ls INTEGER NOT NULL, conf TEXT NOT NULL,
      models TEXT NOT NULL, decks TEXT NOT NULL, dconf TEXT NOT NULL, tags TEXT NOT NULL
    );
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY, guid TEXT NOT NULL, mid INTEGER NOT NULL,
      mod INTEGER NOT NULL, usn INTEGER NOT NULL, tags TEXT NOT NULL,
      flds TEXT NOT NULL, sfld TEXT NOT NULL, csum INTEGER NOT NULL,
      flags INTEGER NOT NULL, data TEXT NOT NULL
    );
    CREATE TABLE cards (
      id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL,
      ord INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL,
      type INTEGER NOT NULL, queue INTEGER NOT NULL, due INTEGER NOT NULL,
      ivl INTEGER NOT NULL, factor INTEGER NOT NULL, reps INTEGER NOT NULL,
      lapses INTEGER NOT NULL, left INTEGER NOT NULL, odue INTEGER NOT NULL,
      odid INTEGER NOT NULL, flags INTEGER NOT NULL, data TEXT NOT NULL
    );
    CREATE TABLE revlog (
      id INTEGER PRIMARY KEY, cid INTEGER NOT NULL, usn INTEGER NOT NULL,
      ease INTEGER NOT NULL, ivl INTEGER NOT NULL, lastIvl INTEGER NOT NULL,
      factor INTEGER NOT NULL, time INTEGER NOT NULL, type INTEGER NOT NULL
    );
    CREATE TABLE graves (usn INTEGER NOT NULL, oid INTEGER NOT NULL, type INTEGER NOT NULL);
    CREATE INDEX ix_notes_usn on notes (usn);
    CREATE INDEX ix_cards_usn on cards (usn);
    CREATE INDEX ix_revlog_usn on revlog (usn);
    CREATE INDEX ix_cards_nid on cards (nid);
    CREATE INDEX ix_cards_sched on cards (did, queue, due);
    CREATE INDEX ix_revlog_cid on revlog (cid);
    CREATE INDEX ix_notes_csum on notes (csum);
    """

    static func model(
        id: Int64, deckId: Int64, name: String,
        fields: [String], front: String, back: String, css: String, mod: Int64
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "type": 0,
            "mod": mod,
            "usn": -1,
            "sortf": 0,
            "did": deckId,
            "tmpls": [[
                "name": "Vocab", "ord": 0,
                "qfmt": front, "afmt": back,
                "bqfmt": "", "bafmt": "", "did": NSNull(),
            ]],
            "flds": fields.enumerated().map { (ord, fieldName) in
                [
                    "name": fieldName, "ord": ord, "sticky": false,
                    "rtl": false, "font": "Arial", "size": 20, "media": [],
                ] as [String: Any]
            },
            "css": css,
            "latexPre": "\\documentclass[12pt]{article}\n",
            "latexPost": "\\end{document}",
            "latexsvg": false,
            "req": [[0, "any", [0]]],
            "vers": [],
            "tags": [],
        ]
    }

    static func deck(id: Int64, name: String, mod: Int64) -> [String: Any] {
        [
            "id": id, "name": name, "mod": mod, "usn": -1, "desc": "",
            "collapsed": false, "browserCollapsed": false,
            "extendNew": 0, "extendRev": 50, "dyn": 0, "conf": 1,
            "newToday": [0, 0], "revToday": [0, 0],
            "lrnToday": [0, 0], "timeToday": [0, 0],
        ]
    }

    static let defaultConf: [String: Any] = [
        "curDeck": 1, "activeDecks": [1], "newSpread": 0, "collapseTime": 1200,
        "timeLim": 0, "estTimes": true, "dueCounts": true, "curModel": NSNull(),
        "nextPos": 1, "sortType": "noteFld", "sortBackwards": false,
        "addToCur": true, "dayLearnFirst": false,
    ]

    static let defaultDconf: [String: Any] = [
        "1": [
            "id": 1, "name": "Default", "replayq": false,
            "lapse": ["leechFails": 8, "minInt": 1, "delays": [10], "leechAction": 0, "mult": 0],
            "rev": ["perDay": 200, "fuzz": 0.05, "ivlFct": 1, "maxIvl": 36500,
                    "ease4": 1.3, "bury": false, "minSpace": 1],
            "timer": 0, "maxTaken": 60, "usn": -1,
            "new": ["perDay": 20, "delays": [1, 10], "separate": true, "ints": [1, 4, 7],
                    "initialFactor": 2500, "bury": false, "order": 1],
            "mod": 0, "autoplay": true,
        ],
    ]
}
