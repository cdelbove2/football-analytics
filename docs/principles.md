# Project principles

These are the working principles for this project. They matter as much as
the architecture decisions, because this project is a learning vehicle as
much as a product.

## 1. Comment for learning, not just for documentation

Every component (ingestion script, SQL file, dbt model, analytics
notebook, etc.) should have comments that explain:

- **What** the code is doing at each meaningful step.
- **Why** it's done this way (especially where there's a non-obvious
  choice, a workaround, or a trade-off).
- **Where to look** if you want to change or extend it (e.g. "add new
  stat columns here", "this threshold can be tuned").

The goal is that Christian (or anyone else) can open any file, read top to
bottom, and understand both the mechanics and the reasoning - without
needing to ask "why was this written this way?" separately.

This is *more* commenting than typical production code would have. That's
intentional - as the codebase matures and patterns become familiar,
comments can be trimmed, but err on the side of over-explaining early on.

### Examples of the level of detail expected

- A dbt model should have a header comment explaining what grain the table
  is at, what it joins, and any assumptions (e.g. minutes-played
  thresholds, bracket boundaries).
- A SQL DDL file should explain *why* a table is structured the way it is
  (e.g. why `core.player` uses nullable per-source ID columns instead of a
  separate join table).
- A Python ingestion script should comment each major step (fetch, parse,
  transform, load) and flag any known limitations or TODOs inline.

## 2. Prefer explicit over clever

Favour code that's easy to read and modify over code that's compact or
"smart". This is a portfolio + learning project - readability has direct
value.

## 3. Document known gaps and TODOs inline

If something is a placeholder, simplification, or known limitation, say so
in a comment near the code (not just in a separate doc), so it's visible
exactly where it matters.

## 4. Architecture decisions go in `docs/adr_*.md`

Bigger design decisions (like the player identity mapping table, or the
choice to defer Airflow/Neo4j) get a short ADR file. Inline comments handle
the "how this specific code works" level; ADRs handle the "why did we
choose this approach at all" level.
