-- =====================================================================
-- 001_init_raw_schema.sql
--
-- Initial raw schema for the football analytics platform.
--
-- Design principles:
--   * `raw` schema holds landing tables, close to source shape, with
--     minimal transformation (just enough to load reliably). dbt's
--     staging layer is responsible for cleaning/typing/renaming.
--   * `core` schema holds cross-source infrastructure: the player
--     identity mapping table ("identity graph" / mapping table) and
--     shared reference data (positions, clubs, competitions).
--   * Every raw table carries a `_loaded_at` timestamp and `_source`
--     marker for traceability.
-- =====================================================================

create schema if not exists raw;
create schema if not exists core;

-- Why two schemas?
--   `raw`  = "as close to the source as possible" landing zone. If a
--            scrape format changes, only raw tables and the matching
--            ingestion script need to change.
--   `core` = stable, source-agnostic infrastructure (the mapping table,
--            shared lookups) that the rest of the pipeline depends on.
-- dbt will add its own schemas on top of these (staging/intermediate/marts)
-- as defined in dbt/dbt_project.yml.


-- ---------------------------------------------------------------------
-- core.player
--
-- One row per real-world player, identified by our own UUID. This is
-- the "mapping table" that links the same player across data sources.
-- New sources just need a new nullable *_id column.
-- ---------------------------------------------------------------------
create table if not exists core.player (
    player_id           uuid primary key default gen_random_uuid(),
    name_canonical      text not null,
    date_of_birth       date,
    nationality         text,

    -- per-source identifiers (nullable - not every player exists in every source)
    fbref_id            text unique,
    transfermarkt_id    text unique,
    understat_id        text unique,
    sofascore_id        text unique,
    opta_id             text unique,

    -- matching metadata
    match_status        text not null default 'unmatched'
                         check (match_status in ('unmatched', 'auto_matched', 'confirmed', 'needs_review')),
    match_confidence    numeric(4,3),  -- 0.000 - 1.000, null if exact match

    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now()
);

comment on table core.player is
    'Cross-source player identity mapping table. Joins on *_id columns to '
    'unify records from FBref, Transfermarkt, Understat, etc. under one '
    'internal player_id.';

-- ---------------------------------------------------------------------
-- core.position
--
-- Canonical position taxonomy. Sources use different position labels
-- (e.g. "CB" vs "Centre-Back" vs "DC") - this is the normalised set
-- used downstream for position-specific metric sets.
-- ---------------------------------------------------------------------
create table if not exists core.position (
    position_code   text primary key,        -- e.g. 'CB', 'RB', 'CM', 'ST'
    position_name   text not null,           -- e.g. 'Centre-Back'
    position_group  text not null            -- e.g. 'Defender', 'Midfielder', 'Forward', 'Goalkeeper'
);

-- ---------------------------------------------------------------------
-- core.position_alias
--
-- Maps each source's raw position strings to a core.position_code.
-- ---------------------------------------------------------------------
create table if not exists core.position_alias (
    source          text not null,           -- 'fbref', 'transfermarkt', etc.
    source_value    text not null,           -- raw string as it appears in that source
    position_code   text not null references core.position(position_code),
    primary key (source, source_value)
);

-- =====================================================================
-- RAW LANDING TABLES
-- =====================================================================

-- ---------------------------------------------------------------------
-- raw.fbref_player_stats
--
-- One row per player per season per competition, as scraped from FBref
-- standard/advanced stats tables. Kept wide and loosely typed; dbt
-- staging models will cast and reshape.
-- ---------------------------------------------------------------------
create table if not exists raw.fbref_player_stats (
    fbref_id        text not null,
    player_name     text not null,
    season          text not null,           -- e.g. '2024-2025'
    competition     text,
    squad           text,
    position        text,
    age             text,
    minutes_played  numeric,
    stats           jsonb not null,          -- all numeric/text stat columns as scraped
    _source         text not null default 'fbref',
    _loaded_at      timestamptz not null default now(),
    primary key (fbref_id, season, competition, squad)
);

comment on column raw.fbref_player_stats.stats is
    'Wide stat block as scraped (goals, xg, passes, tackles, etc.) stored as '
    'JSON to avoid migrations every time we add a stat; dbt staging flattens '
    'the fields we care about.';

-- Why JSONB here instead of one column per stat?
--   FBref's stat tables have 30-40+ columns and the set varies slightly
--   by table/season. Storing them as JSONB means a new stat appearing in
--   a scrape doesn't break the load (no ALTER TABLE needed). The dbt
--   staging model (stg_fbref__player_stats.sql) is the single place where
--   we decide which JSON keys become "first-class" typed columns - that's
--   the file to edit when you want to use a new stat downstream.

-- ---------------------------------------------------------------------
-- raw.transfermarkt_player
--
-- One row per player, latest scrape snapshot. Market value history is
-- kept separately (raw.transfermarkt_market_value_history) since it
-- changes over time.
-- ---------------------------------------------------------------------
create table if not exists raw.transfermarkt_player (
    transfermarkt_id    text primary key,
    player_name         text not null,
    date_of_birth       date,
    nationality         text,
    current_club        text,
    position            text,
    market_value_eur    numeric,
    contract_expires     date,
    agent               text,
    raw_payload         jsonb,               -- full scraped payload for anything not modelled yet
    _source             text not null default 'transfermarkt',
    _loaded_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- raw.transfermarkt_market_value_history
--
-- Time series of market value snapshots per player, for tracking value
-- trends (used by watchlist/alerts later).
-- ---------------------------------------------------------------------
create table if not exists raw.transfermarkt_market_value_history (
    transfermarkt_id    text not null,
    value_date          date not null,
    market_value_eur    numeric not null,
    _source             text not null default 'transfermarkt',
    _loaded_at          timestamptz not null default now(),
    primary key (transfermarkt_id, value_date)
);

-- ---------------------------------------------------------------------
-- raw.understat_player_stats
--
-- One row per player per season, xG-focused metrics from Understat.
-- ---------------------------------------------------------------------
create table if not exists raw.understat_player_stats (
    understat_id    text not null,
    player_name     text not null,
    season          text not null,
    team            text,
    position        text,
    minutes_played  numeric,
    goals           numeric,
    xg              numeric,
    assists         numeric,
    xa              numeric,
    shots           numeric,
    key_passes      numeric,
    raw_payload     jsonb,
    _source         text not null default 'understat',
    _loaded_at      timestamptz not null default now(),
    primary key (understat_id, season)
);

-- ---------------------------------------------------------------------
-- raw.ingestion_log
--
-- Simple run log for each ingestion script execution. Useful early on
-- for debugging and later as the seed for monitoring / GitHub Actions
-- status reporting.
-- ---------------------------------------------------------------------
create table if not exists raw.ingestion_log (
    run_id          uuid primary key default gen_random_uuid(),
    source          text not null,
    started_at      timestamptz not null default now(),
    finished_at     timestamptz,
    status          text not null default 'running'
                    check (status in ('running', 'success', 'failed')),
    rows_loaded     integer,
    notes           text
);

-- =====================================================================
-- SEED DATA: core.position
-- =====================================================================
insert into core.position (position_code, position_name, position_group) values
    ('GK', 'Goalkeeper',        'Goalkeeper'),
    ('CB', 'Centre-Back',       'Defender'),
    ('LB', 'Left-Back',         'Defender'),
    ('RB', 'Right-Back',        'Defender'),
    ('DM', 'Defensive Midfield','Midfielder'),
    ('CM', 'Central Midfield',  'Midfielder'),
    ('AM', 'Attacking Midfield','Midfielder'),
    ('LW', 'Left Winger',       'Forward'),
    ('RW', 'Right Winger',      'Forward'),
    ('ST', 'Striker',           'Forward')
on conflict (position_code) do nothing;
