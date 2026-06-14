-- =====================================================================
-- 003_player_nationality_cap_status.sql
--
-- Replaces the boolean `is_primary` column on core.player_nationality
-- with a richer `cap_status` text column.
--
-- Why: A boolean can't distinguish between:
--   * Senior-capped  → FIFA rules lock in the commitment permanently.
--                      This nationality is their primary, full stop.
--   * Youth-capped   → Player has represented a country at youth level
--                      but has NOT yet made a senior appearance in an
--                      official competition. Commitment is NOT final —
--                      they can still switch. Treat as provisional primary.
--   * No caps        → Uncapped or the nationality is purely a second
--                      citizenship with no international football intent.
--
-- How to read the table after this change:
--   cap_status = 'senior' → primary nationality, locked in
--   cap_status = 'youth'  → provisional primary, can still change
--   cap_status = null     → additional citizenship only, or uncapped with
--                           no declared intent
--
-- Only one row per player should ever carry a non-null cap_status
-- (enforced by application logic / ingestion; a partial unique index is
-- added below as a guardrail).
-- =====================================================================

alter table core.player_nationality
    drop column is_primary;

alter table core.player_nationality
    add column cap_status text
        check (cap_status in ('senior', 'youth'));

-- Guardrail: at most one cap_status row per player.
-- A player cannot be senior-capped (or youth-capped) for two countries
-- at the same time. The partial index enforces uniqueness only where
-- cap_status IS NOT NULL, leaving additional citizenship rows (null) free.
create unique index player_nationality_one_cap_status
    on core.player_nationality (player_id)
    where cap_status is not null;

comment on column core.player_nationality.cap_status is
    'International commitment level for this nationality: '
    '''senior'' = senior cap in an official FIFA competition — commitment is permanent. '
    '''youth''  = youth caps only — commitment is provisional, player can still switch. '
    'null       = additional citizenship with no cap / no declared intent. '
    'At most one non-null cap_status row is allowed per player (enforced by partial unique index).';
