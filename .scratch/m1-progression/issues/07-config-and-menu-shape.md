# Decide the shape of `config.json` and the M1 mod-menu section

Type: grilling
Status: resolved
Blocked by: 05

## Question

M1 has one setting: the progression toggle, on by default, persisted in `reframework/data/Retinue/config.json`
separate from the roster (map Notes). What is the file's shape (keys, a version field, behaviour on a missing or
malformed file), when is it read and written, and what does the REFramework menu section show (toggle, status line,
anything about hired pawns in the party)? Keep M2's roster and later settings in mind without designing them.

## Answer

Grilled with the user 2026-11-03; every recommendation accepted.

- **Shape**: flat, versioned: `{ "version": 1, "progression": true }`. No nesting until a later milestone needs it.
- **Missing file**: defaults in memory (progression on); the file is created only when the user changes a setting.
- **Malformed file**: resolved per key. A valid key is used; a missing or wrongly typed key falls back to its default
  with a warning in the REFramework log. An unparseable file means all defaults. A newer `version` is read for the
  keys known. The file is not overwritten until the user changes a setting; unknown keys are preserved on rewrite.
- **Read/write timing**: read once at script load (game start or *Reset scripts*); written immediately on every
  change from the menu. `re.on_config_save` is not used.
- **Toggle effect**: immediate, also mid-fight. The hooks stay installed and check the flag; the next exp or job-point
  gain follows the new value. Turning it off reverts nothing (ADR 0001).
- **Menu** (`Retinue` tree node, English text):
  - checkbox `Hired pawns gain levels and vocation ranks`;
  - read-only status line listing the hired pawns in the party it applies to (name, level, vocation, rank), or
    `No hired pawns in party`;
  - if a hook fails to install: `Progression unavailable: <method> not found (game update?)`.
