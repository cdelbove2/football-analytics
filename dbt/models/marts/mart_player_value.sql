-- Player performance per 90 minutes, joined with latest market value and
-- bucketed into price brackets. This is the table the "Price Explorer"
-- and "Scout Assist" product surfaces would query.
--
-- NOTE: per-90 metrics are only meaningful above a minutes-played floor -
-- a player with 90 minutes who scored once will show a 1.0 goals/90,
-- which is noise, not signal. `sample_size_ok` flags this.

with performance as (

    select * from {{ ref('int_player_performance') }}

),

valuation as (

    select
        player_id,
        market_value_eur
    from {{ ref('stg_transfermarkt__player') }} tm
    inner join {{ source('core', 'player') }} p
        on tm.transfermarkt_id = p.transfermarkt_id

),

minutes_floor as (
    -- 600 minutes (~6-7 full matches) as a baseline sample-size threshold;
    -- revisit once real data volumes are in.
    select 600 as min_minutes
),

per_90 as (

    select
        performance.player_id,
        performance.name_canonical,
        performance.season,
        performance.competition,
        performance.squad,
        performance.position_raw,
        performance.minutes_played,

        case when performance.minutes_played >= minutes_floor.min_minutes then true else false end
            as sample_size_ok,

        round(performance.goals / nullif(performance.minutes_played, 0) * 90, 3)
            as goals_per_90,
        round(performance.expected_goals / nullif(performance.minutes_played, 0) * 90, 3)
            as xg_per_90,
        round(performance.assists / nullif(performance.minutes_played, 0) * 90, 3)
            as assists_per_90,
        round(performance.expected_assisted_goals / nullif(performance.minutes_played, 0) * 90, 3)
            as xag_per_90,
        round(performance.progressive_carries / nullif(performance.minutes_played, 0) * 90, 3)
            as progressive_carries_per_90,
        round(performance.progressive_passes / nullif(performance.minutes_played, 0) * 90, 3)
            as progressive_passes_per_90,

        valuation.market_value_eur

    from performance
    cross join minutes_floor
    left join valuation
        on performance.player_id = valuation.player_id

),

bracketed as (

    select
        *,
        case
            when market_value_eur is null            then 'unknown'
            when market_value_eur <  5000000          then '<5m'
            when market_value_eur <  15000000         then '5m-15m'
            when market_value_eur <  30000000         then '15m-30m'
            when market_value_eur <  60000000         then '30m-60m'
            else                                           '60m+'
        end as price_bracket

    from per_90

)

select * from bracketed
