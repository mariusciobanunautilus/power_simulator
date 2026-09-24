-- Power Simulator
-- Core domain entities
-- Foundational business dimensions used by portfolio calculations


-- ============================================================
-- CORE: SETTLEMENT INTERVAL
-- ============================================================

create table core.settlement_interval (
    interval_id bigint generated always as identity primary key,

    market_code text not null default 'RO',

    interval_start_utc timestamptz not null,
    interval_end_utc timestamptz not null,

    local_date date not null,

    local_hour_label smallint not null
        check (local_hour_label between 1 and 25),

    local_occurrence smallint not null default 1
        check (local_occurrence in (1, 2)),

    duration_hours numeric(10,5) not null
        check (duration_hours > 0),

    check (interval_end_utc > interval_start_utc),

    unique (
        market_code,
        interval_start_utc
    ),

    unique (
        market_code,
        local_date,
        local_hour_label,
        local_occurrence
    )
);

comment on table core.settlement_interval is
'Canonical Romanian electricity settlement intervals, stored in UTC with Romanian local market labels for DST-safe reporting.';


-- ============================================================
-- CORE: BOOK
-- ============================================================

create table core.book (
    book_id bigint generated always as identity primary key,

    book_code text not null unique,

    book_name text not null,

    book_type text not null
        check (
            book_type in (
                'portfolio',
                'fixed_retail',
                'indexed_retail',
                'sourcing',
                'optimisation',
                'origination',
                'balancing',
                'services'
            )
        ),

    active boolean not null default true
);

comment on table core.book is
'Commercial and reporting books used to separate retail, sourcing, optimisation, origination and related activities.';


-- ============================================================
-- CORE: COUNTERPARTY
-- ============================================================

create table core.counterparty (
    counterparty_id bigint generated always as identity primary key,

    counterparty_code text not null unique,

    external_reference text,

    legal_name text,

    counterparty_type text not null
        check (
            counterparty_type in (
                'customer',
                'supplier',
                'generator',
                'market',
                'service',
                'other'
            )
        ),

    active boolean not null default true
);

comment on table core.counterparty is
'Customers, suppliers, generators, market operators and other commercial counterparties.';


-- ============================================================
-- CORE: PRODUCT
-- ============================================================

create table core.product (
    product_id bigint generated always as identity primary key,

    product_code text not null unique,

    product_name text,

    product_type text not null
        check (
            product_type in (
                'base',
                'peak',
                'hourly',
                'renewable',
                'retail',
                'balancing',
                'service',
                'certificate',
                'other'
            )
        ),

    delivery_zone text not null default 'RO',

    active boolean not null default true
);

comment on table core.product is
'Energy and service products used by contracts, procurement schedules and trading records.';


-- ============================================================
-- CORE: CONTRACT
-- ============================================================

create table core.contract (
    contract_id bigint generated always as identity primary key,

    contract_reference text not null unique,

    external_reference text,

    counterparty_id bigint
        references core.counterparty(counterparty_id),

    book_id bigint not null
        references core.book(book_id),

    product_id bigint
        references core.product(product_id),

    side text not null
        check (
            side in (
                'buy',
                'sell'
            )
        ),

    price_method text not null
        check (
            price_method in (
                'fixed',
                'pzu_plus_fee',
                'indexed_other',
                'negotiated'
            )
        ),

    valid_from date not null,
    valid_to date not null,

    currency_code char(3) not null,

    active boolean not null default true,

    check (valid_to >= valid_from)
);

comment on table core.contract is
'Commercial purchase or sale agreement linked to counterparty, book and delivery product.';


-- ============================================================
-- CORE: CONTRACT PRICE
-- ============================================================

create table core.contract_price (
    contract_price_id bigint generated always as identity primary key,

    contract_id bigint not null
        references core.contract(contract_id)
        on delete cascade,

    valid_from date not null,
    valid_to date not null,

    fixed_price numeric(20,8),

    fee_per_mwh numeric(20,8),

    currency_code char(3) not null,

    amendment_reference text,

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    check (valid_to >= valid_from),

    check (
        fixed_price is not null
        or fee_per_mwh is not null
    ),

    unique (
        contract_id,
        valid_from,
        valid_to
    )
);

comment on table core.contract_price is
'Effective-dated contract pricing, retaining workbook/source lineage where available.';


-- ============================================================
-- INDEXES
-- ============================================================

create index ix_settlement_interval_local_date
    on core.settlement_interval(local_date);

create index ix_contract_counterparty
    on core.contract(counterparty_id);

create index ix_contract_book
    on core.contract(book_id);

create index ix_contract_product
    on core.contract(product_id);

create index ix_contract_validity
    on core.contract(valid_from, valid_to);

create index ix_contract_price_contract
    on core.contract_price(contract_id);

create index ix_contract_price_validity
    on core.contract_price(valid_from, valid_to);