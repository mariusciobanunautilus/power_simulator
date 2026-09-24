-- Power Simulator
-- Seed canonical products into core.product.
--
-- Workbook evidence supports the following product concepts:
--
--   Base
--     Used in 2026 sourcing assumptions.
--
--   Peak
--     Used in 2026 sourcing assumptions.
--
--   PZU
--     Day-ahead market price / position references across monthly sheets.
--
--   Fixed price retail
--     Explicitly labelled in Asumptions.
--
--   Indexed price retail
--     Explicitly labelled in Asumptions.
--
--   Small renewable / Regenerabili mici
--     Explicit renewable supply concept in 2026 and monthly sheets.
--
--   Balancing
--     Explicit balancing concept in 2026 / Asumptions.
--
--   Services
--     Explicit service-income / BRP-service concept.
--
-- No certificate product is seeded because the workbook evidence inspected so far
-- does not support a distinct certificate product.


begin;


-- ============================================================
-- SAFETY GUARD
-- ============================================================

do $$
begin

    if exists (
        select 1
        from core.product
        where product_code in (
            'BASE',
            'PEAK',
            'PZU',
            'FIXED_RETAIL',
            'INDEXED_RETAIL',
            'SMALL_RENEWABLE',
            'BALANCING',
            'SERVICES'
        )
    ) then
        raise exception
            'One or more canonical Power Simulator products already exist. Seed aborted.';
    end if;

end
$$;


-- ============================================================
-- LOAD CANONICAL PRODUCTS
-- ============================================================

insert into core.product (
    product_code,
    product_name,
    product_type,
    delivery_zone,
    active
)
values

    (
        'BASE',
        'Base',
        'base',
        'RO',
        true
    ),

    (
        'PEAK',
        'Peak',
        'peak',
        'RO',
        true
    ),

    (
        'PZU',
        'PZU Day-Ahead Market',
        'hourly',
        'RO',
        true
    ),

    (
        'FIXED_RETAIL',
        'Fixed Price Retail',
        'retail',
        'RO',
        true
    ),

    (
        'INDEXED_RETAIL',
        'Indexed Price Retail',
        'retail',
        'RO',
        true
    ),

    (
        'SMALL_RENEWABLE',
        'Small Renewable',
        'renewable',
        'RO',
        true
    ),

    (
        'BALANCING',
        'Balancing',
        'balancing',
        'RO',
        true
    ),

    (
        'SERVICES',
        'Services',
        'service',
        'RO',
        true
    );


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    canonical_product_count integer;
begin

    select count(*)
    into canonical_product_count
    from core.product
    where product_code in (
        'BASE',
        'PEAK',
        'PZU',
        'FIXED_RETAIL',
        'INDEXED_RETAIL',
        'SMALL_RENEWABLE',
        'BALANCING',
        'SERVICES'
    );

    if canonical_product_count <> 8 then
        raise exception
            'Expected 8 canonical products, found %',
            canonical_product_count;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

select
    product_id,
    product_code,
    product_name,
    product_type,
    delivery_zone,
    active
from core.product
where product_code in (
    'BASE',
    'PEAK',
    'PZU',
    'FIXED_RETAIL',
    'INDEXED_RETAIL',
    'SMALL_RENEWABLE',
    'BALANCING',
    'SERVICES'
)
order by product_id;