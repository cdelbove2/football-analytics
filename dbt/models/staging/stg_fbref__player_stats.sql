with source as (

    select * from {{ source('raw', 'fbref_player_stats') }}

),

renamed as (

    select
        fbref_id,
        trim(player_name)                          as player_name,
        season,
        competition,
        squad,
        position                                    as position_raw,

        -- FBref sometimes formats age as "25-180" (years-days); take the
        -- year part only.
        nullif(split_part(age, '-', 1), '')::int    as age_years,

        minutes_played,

        -- Commonly-used stats pulled out of the JSON blob.
        -- Extend this list as the analytics layer needs more fields -
        -- everything else remains available in `stats_extra`.
        (stats ->> 'gls')::numeric                  as goals,
        (stats ->> 'ast')::numeric                  as assists,
        (stats ->> 'xg')::numeric                   as expected_goals,
        (stats ->> 'xag')::numeric                  as expected_assisted_goals,
        (stats ->> 'sh')::numeric                   as shots,
        (stats ->> 'sot')::numeric                  as shots_on_target,
        (stats ->> 'prgc')::numeric                 as progressive_carries,
        (stats ->> 'prgp')::numeric                 as progressive_passes,
        (stats ->> 'prgr')::numeric                 as progressive_passes_received,

        stats                                        as stats_extra,

        _source,
        _loaded_at

    from source

)

select * from renamed
