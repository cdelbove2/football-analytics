-- =====================================================================
-- 002_player_nationality.sql
--
-- Replaces the single `nationality` text column on core.player with a
-- proper junction table, core.player_nationality.
--
-- Why: Many players hold dual or triple citizenship. A single column
-- forces an arbitrary choice and loses data we may need for:
--   * Work permit / squad registration eligibility checks (EU vs non-EU)
--   * Knowing which international team a player has committed to
--   * Filtering candidates by passport country
--
-- is_primary = true  → the nationality they've represented internationally
-- is_primary = false → additional citizenship(s)
-- is_primary = null  → uncapped player; primary unknown / not yet declared
-- =====================================================================

-- Step 1: remove the old single-value column from core.player.
-- No data migration needed — the column was always nullable and no rows
-- have been loaded yet (schema is freshly initialised).
alter table core.player
    drop column if exists nationality;

-- Step 2: create the junction table.
create table if not exists core.player_nationality (
    player_id   uuid not null references core.player(player_id) on delete cascade,
    nationality text not null,   -- ISO 3166-1 alpha-3 country code, e.g. 'ENG', 'FRA'
    is_primary  boolean,         -- true = committed international; null = uncapped/unknown

    primary key (player_id, nationality)
);

comment on table core.player_nationality is
    'All nationalities/citizenships held by a player. is_primary = true marks '
    'the country they have committed to internationally (if capped). '
    'is_primary is null for uncapped players where primary is unknown.';

comment on column core.player_nationality.nationality is
    'ISO 3166-1 alpha-3 country code (ENG, FRA, BRA, etc.). '
    'Sources use different formats — the ingestion layer should normalise to alpha-3 '
    'before inserting here.';

comment on column core.player_nationality.is_primary is
    'true  = this is their chosen international team (capped or declared). '
    'false = additional citizenship only. '
    'null  = uncapped player, primary nationality unknown or not yet declared.';
