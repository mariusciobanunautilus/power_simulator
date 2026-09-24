-- Power Simulator
-- Seed canonical portfolio books into core.book.
--
-- Workbook evidence:
--
--   Books result!B2
--     2026 Sourcing Book
--
--   Books result!B21
--     2026 Sourcing Book - optimisation
--
--   Books result!B40
--     2026 Origination Book
--
--   2026 / Asumptions
--     BALANCING
--     Services income
--     Fixed price retail volumes
--     Indexed price retail volumes
--
-- PORTFOLIO_TOTAL is a canonical reporting book required by the
-- target model for aggregate portfolio metrics. It is a model
-- dimension rather than a literal workbook-labelled book.


begin;


-- ============================================================
-- SAFETY GUARD
-- ============================================================

do $$
begin

    if exists (
        select 1
        from core.book
        where book_code in (
            'PORTFOLIO_TOTAL',
            'FIXED_RETAIL',
            'INDEXED_RETAIL',
            'SOURCING',
            'OPTIMISATION',
            'ORIGINATION',
            'BALANCING',
            'SERVICES'
        )
    ) then
        raise exception
            'One or more canonical Power Simulator books already exist. Seed aborted.';
    end if;

end
$$;


-- ============================================================
-- LOAD CANONICAL BOOKS
-- ============================================================

insert into core.book (
    book_code,
    book_name,
    book_type,
    active
)
values

    (
        'PORTFOLIO_TOTAL',
        'Portfolio Total',
        'portfolio',
        true
    ),

    (
        'FIXED_RETAIL',
        'Fixed Price Retail',
        'fixed_retail',
        true
    ),

    (
        'INDEXED_RETAIL',
        'Indexed Price Retail',
        'indexed_retail',
        true
    ),

    (
        'SOURCING',
        'Sourcing Book',
        'sourcing',
        true
    ),

    (
        'OPTIMISATION',
        'Sourcing Book - Optimisation',
        'optimisation',
        true
    ),

    (
        'ORIGINATION',
        'Origination Book',
        'origination',
        true
    ),

    (
        'BALANCING',
        'Balancing',
        'balancing',
        true
    ),

    (
        'SERVICES',
        'Services',
        'services',
        true
    );


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    canonical_book_count integer;
begin

    select count(*)
    into canonical_book_count
    from core.book
    where book_code in (
        'PORTFOLIO_TOTAL',
        'FIXED_RETAIL',
        'INDEXED_RETAIL',
        'SOURCING',
        'OPTIMISATION',
        'ORIGINATION',
        'BALANCING',
        'SERVICES'
    );

    if canonical_book_count <> 8 then
        raise exception
            'Expected 8 canonical books, found %',
            canonical_book_count;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

select
    book_id,
    book_code,
    book_name,
    book_type,
    active
from core.book
where book_code in (
    'PORTFOLIO_TOTAL',
    'FIXED_RETAIL',
    'INDEXED_RETAIL',
    'SOURCING',
    'OPTIMISATION',
    'ORIGINATION',
    'BALANCING',
    'SERVICES'
)
order by book_id;