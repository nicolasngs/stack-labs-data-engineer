{{
    config(
        materialized='table',
        partition_by={
            "field": "sales_datetime",
            "data_type": "timestamp",
            "granularity": "month"
        }
    )
}}

select
    s.id as ID,
    s.datetime as sales_datetime,
    item.amount as item_amount,
    item.product_sku,
    item.quantity as item_quantity,
    p.description as product_description,
    round(((p.unit_amount - (item.amount / item.quantity)) / p.unit_amount) * 100, 2) as discount_perc
from {{ source('stg_retail', 'sales') }} s
cross join unnest(s.items) as item
left join {{ source('stg_retail', 'products') }} p
    on item.product_sku = p.product_sku
where s.datetime is not null
--order by s.datetime desc, s.id
