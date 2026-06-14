# ADR 002: Player nationality modelling

## Status
Accepted

## Context
Players frequently hold more than one citizenship (dual/triple nationality is
common in football). A single `nationality text` column on `core.player` forces
an arbitrary choice and loses data needed for:

- Work permit / squad registration eligibility (e.g. Premier League non-UK quota,
  Serie A non-EU limits) — requires knowing *all* citizenships, not just one.
- Knowing which international team a player has committed to.
- Filtering scouting candidates by passport country.

Additionally, international commitment is not binary. FIFA regulations distinguish
between:

- **Senior caps** in an official competition → commitment is **permanent**. A
  player cannot switch national team after a senior appearance.
- **Youth caps only** → commitment is **provisional**. The player has represented
  a country at youth level but can still switch to another eligible nation before
  making a senior appearance.
- **No caps** → no commitment has been made; the player may hold the citizenship
  but has expressed no international intent.

## Decision

### Table structure
Replace the single `nationality` column with a junction table,
`core.player_nationality`:

```
player_id   uuid  FK → core.player (cascade delete)
nationality text  ISO 3166-1 alpha-3 country code (e.g. 'ENG', 'FRA', 'BRA')
cap_status  text  'senior' | 'youth' | null
```

Primary key: `(player_id, nationality)` — one row per player per citizenship.

### `cap_status` values and what they mean

| Value | Meaning | Primary nationality? |
|---|---|---|
| `'senior'` | Senior cap in an official FIFA competition. Commitment is permanent by FIFA rules. | Yes — locked in. |
| `'youth'` | Youth international caps only (U17, U19, U21, etc.). No senior appearance yet. | Provisional — can still switch. |
| `null` | Additional citizenship with no cap at any level, or uncapped player with no declared intent. | No (or unknown). |

The "primary" nationality for a player is the row where `cap_status IS NOT NULL`.
At most one such row is allowed per player, enforced by a partial unique index.

### Country code format
All nationality values must be stored as **ISO 3166-1 alpha-3** codes
(three letters: `ENG`, `FRA`, `BRA`, `NGA`, etc.). Sources use different formats:

| Source | Format | Example | Action |
|---|---|---|---|
| FBref | Two-letter IOC/FBref code | `EN`, `FR` | Map to alpha-3 in ingestion |
| Transfermarkt | Full country name | `England`, `France` | Map to alpha-3 in ingestion |
| Understat | Varies | — | Map to alpha-3 in ingestion |

Each ingestion script is responsible for normalising to alpha-3 before inserting.
A lookup mapping will be maintained in the ingestion layer (e.g. a dict or small
CSV) as this comes up.

## Populating cap_status in ingestion scripts

When loading nationality data from a source, apply this logic:

```
if player has senior caps for this country:
    cap_status = 'senior'
elif player has youth caps for this country (but no senior):
    cap_status = 'youth'
else:
    cap_status = null
```

**Transfermarkt** is the best source for this — it explicitly lists:
- "National team" (senior squad appearance)
- "Youth national teams" (U-level appearances)

**FBref** shows nationality flags but does not distinguish senior vs youth caps
within the player stats tables. Use Transfermarkt as the authority for cap_status;
FBref nationality flags can confirm citizenship but should not set cap_status.

### Edge cases to handle in ingestion

- **Switched nationality**: A player who represented Country A at youth level and
  later switched to Country B at senior level. Store both rows:
  - `(player_id, 'A', null)` — original youth commitment, no longer primary
  - `(player_id, 'B', 'senior')` — current senior commitment
  When detected, update the old row's cap_status to null.

- **Naturalised players**: Some players are naturalised citizens who never played
  youth football for that country. Their row will have `cap_status = 'senior'`
  if they've been capped, or `null` if not yet capped.

- **Eligible but uncapped**: A player may be eligible for multiple countries but
  uncapped. Store all citizenship rows with `cap_status = null` until they declare
  or receive a cap.

## Consequences
- Querying for "all French players" requires joining `core.player_nationality`
  and filtering `nationality = 'FRA'` — one extra join compared to a column on
  `core.player`. This is acceptable.
- Work permit checks can query `WHERE nationality IN ('ENG','SCO','WAL','NIR','IRL', ...)`
  across all rows for a player, correctly handling dual nationals.
- `cap_status = 'youth'` rows should be treated as provisional in any feature that
  shows a player's national team — flag them as "eligible, not committed" rather
  than "representing X".
- The partial unique index on `(player_id) WHERE cap_status IS NOT NULL` prevents
  accidental double-entry of a cap_status but is not a substitute for clean
  ingestion logic.
