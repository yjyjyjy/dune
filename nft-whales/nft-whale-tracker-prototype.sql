

/*
I want to get a list of whales and track what they are buying now. I want to catch the trend early on.
*/


-- how is their delta over time?
-- who are the whales 
-- , replace("to"::text, '\', '0') AS current_owner_address

with nft_last_ownership as ( -- NFT's current owner
    select 
        token_id
        , contract_address
        , owner_address_raw
        , REPLACE (owner_address_raw::text, '\x', '0x') as owner_address
    from (
        select 
            "tokenId" as token_id
            , contract_address
            , "to" as owner_address_raw
            , evt_block_number
            , row_number() over (partition by contract_address, "tokenId" order by evt_block_number desc) as rnk 
        from erc721."ERC721_evt_Transfer"
        where 1=1 -- contract_address = '\xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d' -- BAYC
            and evt_block_time <= NOW() 
            and "to" not in (
                '\x0000000000000000000000000000000000000000'
                , '\xe052113bd7d7700d623414a0a4585bcae754e9d5'-- nifty-gateway-omnibus
                , '\x959e104e1a4db6317fa58f8295f586e1a978c297'-- decentraland
                , '\x000000000000000000000000000000000000dead'--burned
                )
            and contract_address not in (
                '\x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85' --Ethereum Name Service (ENS)
                )
            -- and "to" = '\x020ca66c30bec2c4fe3861a94e4db4a498a35872'
    ) a 
    where rnk = 1
)
, ownership_scrubbed as (
    select o.* 
    from nft_last_ownership o 
    join (
          select 
              owner_address
          from nft_last_ownership
          group by 1
          having count(distinct token_id) < 99999 -- otherwise likely marketplace account
        ) m 
        on o.owner_address = m.owner_address
    join (
          select 
              owner_address
              , contract_address
          from nft_last_ownership
          group by 1,2
          having count(distinct token_id) < 500 -- otherwise likely the owner contract of a project with left over items
        ) l 
        on o.owner_address = l.owner_address
        and o.contract_address = l.contract_address
)
, labels as (
    select 
        address
        , labels.get(address, 'ens name') as name
    from labels."labels"
    where type = 'ens name'
        and address is not null 
        and name is not null 
    group by 1,2
)
, floor_price as (
    select 
        "nft_contract_address" as contract_address
        , nft_project_name
        , percentile_cont(.100) within group (order by usd_amount) as floor_price_usd
        , sum(number_of_items) trade_volume
    FROM nft.trades
    where 1=1-- "nft_contract_address"= ('\xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d')
        and original_amount > 0.0 
        and "trade_type" = 'Single Item Trade'
        and "tx_from" != '0x0000000000000000000000000000000000000000'
        and block_time > now() - interval '30 days'
        AND original_amount_raw > 0
        and usd_amount > 0 
    group by 1,2
    having sum(number_of_items) >= 5
)
, owner_collection as (
  select 
    owner_address
    , owner_address_raw
    , o.contract_address
    , count(distinct token_id) as num_token
    , sum(floor_price_usd) as collection_worth
  from ownership_scrubbed o
  join floor_price p
      on p.contract_address = o.contract_address
  group by 1,2,3
)
, multi_collection_holders as (
select 
    owner_address
  from (
    select 
      owner_address
      , contract_address
      , num_token
      , collection_worth
      , row_number() over (partition by owner_address order by collection_worth desc) as rnk
    from owner_collection
  ) tmp
  group by 1
  having sum(case when rnk = 1 then collection_worth end)/sum(collection_worth) < 0.9 -- avoid one trick pony
)
select 
    o.owner_address
    , case 
      when l.name IS NOT NULL THEN 
        CONCAT('<a href="https://opensea.io/'
          , o.owner_address
          , '" target="_blank" >'
          , left(l.name::text,42)
          , '</a>'
          )
      else 
        CONCAT('<a href="https://opensea.io/'
          , o.owner_address
          , '" target="_blank" >'
          , o.owner_address
          , '</a>'
          ) END as name
    , sum(num_token) as num_token
    , sum(collection_worth) as total_wallet_worth
from owner_collection o
join multi_collection_holders m 
  on o.owner_address = m.owner_address
left join labels l 
    on o.owner_address_raw = l.address
group by 1,2
order by total_wallet_worth desc 
limit 100;






/*
check individual wallets
*/

with nft_last_ownership as ( -- NFT's current owner
    select 
        token_id
        , contract_address
        , owner_address_raw
        , REPLACE (owner_address_raw::text, '\x', '0x') as owner_address
    from (
        select 
            "tokenId" as token_id
            , contract_address
            , "to" as owner_address_raw
            , evt_block_number
            , row_number() over (partition by "tokenId" order by evt_block_number desc) as rnk 
        from erc721."ERC721_evt_Transfer"
        where 1=1 -- contract_address = '\xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d' -- BAYC
            and evt_block_time <= NOW() 
            and "to" = '\x020ca66c30bec2c4fe3861a94e4db4a498a35872'
    ) a 
    where rnk = 1
)
, floor_price as (
    select 
        "nft_contract_address" as contract_address
        , nft_project_name
        , percentile_cont(.100) within group (order by usd_amount) as floor_price_usd
        , sum(number_of_items) trade_volume
    FROM nft.trades
    where 1=1-- "nft_contract_address"= ('\xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d')
        and original_amount > 0.0 
        and "trade_type" = 'Single Item Trade'
        and "tx_from" != '0x0000000000000000000000000000000000000000'
        and block_time > now() - interval '30 days'
        AND original_amount_raw > 0
        and usd_amount > 0 
    group by 1,2
    having sum(number_of_items) >= 5
    order by 3 desc
)
select 
    owner_address
    , nft_project_name
    , p.contract_address
    , count(distinct token_id) as num_token
    , sum(floor_price_usd) as total_wallet_worth
from nft_last_ownership o
join floor_price p
    on p.contract_address = o.contract_address
group by 1,2,3
order by total_wallet_worth desc 
limit 100;



-- I want to know the newest collection purchased by whales



























/*
I want to get a list of whales and track what they are buying now. I want to catch the trend early on.
*/


-- how is their delta over time?
-- who are the whales 
-- , replace("to"::text, '\', '0') AS current_owner_address

with nft_last_ownership as ( -- NFT's current owner
    select 
        token_id
        , contract_address
        , owner_address_raw
        , REPLACE (owner_address_raw::text, '\x', '0x') as owner_address
    from (
        select 
            "tokenId" as token_id
            , contract_address
            , "to" as owner_address_raw
            , evt_block_number
            , row_number() over (partition by "tokenId" order by evt_block_number desc) as rnk 
        from erc721."ERC721_evt_Transfer"
        where 1=1 -- contract_address = '\xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d' -- BAYC
            and evt_block_time <= NOW() 
            and "to" not in (
                '\x0000000000000000000000000000000000000000'
                , '\xe052113bd7d7700d623414a0a4585bcae754e9d5'-- nifty-gateway-omnibus
                , '\x959e104e1a4db6317fa58f8295f586e1a978c297'-- decentraland
                , '\x000000000000000000000000000000000000dead'--burned
                )
            and contract_address not in (
                '\x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85' --Ethereum Name Service (ENS)
                )
            and "to" = '\x020ca66c30bec2c4fe3861a94e4db4a498a35872'
    ) a 
    where rnk = 1
)
, ownership_scrubbed as (
    select o.* 
    from nft_last_ownership o 
    join (
          select 
              owner_address
          from nft_last_ownership
          group by 1
          having count(distinct token_id) < 99999 -- otherwise likely marketplace account
        ) m 
        on o.owner_address = m.owner_address
    join (
          select 
              owner_address
              , contract_address
          from nft_last_ownership
          group by 1,2
          having count(distinct token_id) < 500 -- otherwise likely the owner contract of a project with left over items
        ) l 
        on o.owner_address = l.owner_address
        and o.contract_address = l.contract_address
)
, labels as (
    select 
        address
        , labels.get(address, 'ens name') as name
    from labels."labels"
    where type = 'ens name'
        and address is not null 
        and name is not null 
    group by 1,2
)
, floor_price as (
    select 
        "nft_contract_address" as contract_address
        , nft_project_name
        , percentile_cont(.100) within group (order by usd_amount) as floor_price_usd
        , sum(number_of_items) trade_volume
    FROM nft.trades
    where 1=1-- "nft_contract_address"= ('\xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d')
        and original_amount > 0.0 
        and "trade_type" = 'Single Item Trade'
        and "tx_from" != '0x0000000000000000000000000000000000000000'
        and block_time > now() - interval '30 days'
        AND original_amount_raw > 0
        and usd_amount > 0 
    group by 1,2
    having sum(number_of_items) >= 5
)
, owner_collection as (
  select 
    owner_address
    , o.contract_address
    , count(distinct token_id) as num_token
    , sum(floor_price_usd) as collection_worth
  from ownership_scrubbed o
  join floor_price p
      on p.contract_address = o.contract_address
  group by 1,2
)
, multi_collection_holders as (
  with tmp as (
    select 
      owner_address
      , contract_address
      , num_token
      , collection_worth
      , row_number() over (partition by owner_address order by collection_worth desc) as rnk
    from owner_collection
  ) 
  select 
    owner_address
  from tmp
  group by 1
  having sum(case when rnk = 1 then collection_worth end)/sum(collection_worth) < 0.9 -- avoid one trick pony
)
select 
    o.owner_address
    , case 
      when l.name IS NOT NULL THEN 
        CONCAT('<a href="https://opensea.io/'
          , o.owner_address
          , '" target="_blank" >'
          , left(l.name::text,42)
          , '</a>'
          )
      else 
        CONCAT('<a href="https://opensea.io/'
          , o.owner_address
          , '" target="_blank" >'
          , o.owner_address
          , '</a>'
          ) END as name
    , o.contract_address
    , count(distinct token_id) as num_token
    , sum(floor_price_usd) as total_wallet_worth
from ownership_scrubbed o
join multi_collection_holders m 
  on o.owner_address = m.owner_address
left join labels l 
    on o.owner_address_raw = l.address
join floor_price p
    on p.contract_address = o.contract_address
group by 1,2,3
order by total_wallet_worth desc 
limit 100;
