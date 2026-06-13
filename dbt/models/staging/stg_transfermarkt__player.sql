with source as (

    select * from {{ source('raw', 'transfermarkt_player') }}

),

renamed as (

    select
        transfermarkt_id,
        trim(player_name)       as player_name,
        date_of_birth,
        nationality,
        current_club,
        position                as position_raw,
        market_value_eur,
        contract_expires,
        agent,
        _source,
        _loaded_at

    from source

)

select * from renamed
