-- Joins FBref stats to the cross-source player identity mapping table
-- (core.player) to attach our internal player_id. This is the join
-- point where "which source ID maps to which real player" gets resolved -
-- everything downstream of this model should use player_id, not fbref_id.

with fbref as (

    select * from {{ ref('stg_fbref__player_stats') }}

),

player_map as (

    select
        player_id,
        name_canonical,
        fbref_id,
        transfermarkt_id
    from {{ source('core', 'player') }}

),

joined as (

    select
        player_map.player_id,
        player_map.name_canonical,

        fbref.season,
        fbref.competition,
        fbref.squad,
        fbref.position_raw,
        fbref.age_years,
        fbref.minutes_played,
        fbref.goals,
        fbref.assists,
        fbref.expected_goals,
        fbref.expected_assisted_goals,
        fbref.shots,
        fbref.shots_on_target,
        fbref.progressive_carries,
        fbref.progressive_passes,
        fbref.progressive_passes_received,

        player_map.transfermarkt_id is not null as has_transfermarkt_link

    from fbref
    left join player_map
        on fbref.fbref_id = player_map.fbref_id

)

select * from joined
