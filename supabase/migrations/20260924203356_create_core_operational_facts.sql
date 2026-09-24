-- Power Simulator
-- Core operational facts
-- Time-series and transactional inputs used by portfolio calculations


-- ============================================================
-- CORE: HOURLY VOLUME
-- ============================================================

create table core.hourly_volume (
    hourly_volume_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    interval_id bigint not null
        references core.settlement_interval(interval_id),

    measure_code text not null
        check (
            measure_code in (
                'total_load',
                'indexed_load',
                'fixed_load',
                'renewable_output',
                'other_supply'
            )
        ),

    book_id bigint
        references core.book(book_id),

    source_component_code text not null default 'portfolio',

    quantity_mwh numeric(20,8) not null
        check (quantity_mwh >= 0),

    source_sign smallint not null
        check (source_sign in (-1, 1)),

    record_status text not null
        check (
            record_status in (
                'actual',
                'forecast',
                'manual_override'
            )
        ),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    unique (
        run_id,
        interval_id,
        measure_code,
        source_component_code
    )
);

comment on table core.hourly_volume is
'Normalized hourly portfolio volumes. Quantities are stored positive; source_sign preserves the sign convention of the original source.';


-- ============================================================
-- CORE: MARKET PRICE
-- ============================================================

create table core.market_price (
    run_id bigint not null
        references core.model_run(run_id),

    interval_id bigint not null
        references core.settlement_interval(interval_id),

    market_code text not null
        check (
            market_code in (
                'PZU',
                'ID',
                'BALANCING_DEFICIT',
                'BALANCING_EXCESS'
            )
        ),

    currency_code char(3) not null default 'RON',

    price_per_mwh numeric(20,8) not null,

    record_status text not null
        check (
            record_status in (
                'actual',
                'forecast',
                'manual_override'
            )
        ),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    primary key (
        run_id,
        interval_id,
        market_code
    )
);

comment on table core.market_price is
'Hourly market prices. Negative prices are permitted and market direction must therefore be determined from physical volume, not cashflow sign.';


-- ============================================================
-- CORE: PROCUREMENT SCHEDULE
-- ============================================================

create table core.procurement_schedule (
    run_id bigint not null
        references core.model_run(run_id),

    interval_id bigint not null
        references core.settlement_interval(interval_id),

    contract_id bigint not null
        references core.contract(contract_id),

    quantity_mwh numeric(20,8) not null
        check (quantity_mwh >= 0),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    primary key (
        run_id,
        interval_id,
        contract_id
    )
);

comment on table core.procurement_schedule is
'Hourly scheduled purchase volume by supply contract. This is the authoritative contracted-purchase fact rather than duplicating purchases in hourly_volume.';


-- ============================================================
-- CORE: MONTHLY BALANCING
-- ============================================================

create table core.balancing_month (
    run_id bigint not null
        references core.model_run(run_id),

    month_start date not null,

    deficit_mwh numeric(20,8) not null default 0
        check (deficit_mwh >= 0),

    deficit_ron_per_mwh numeric(20,8) not null default 0,

    excess_mwh numeric(20,8) not null default 0
        check (excess_mwh >= 0),

    excess_ron_per_mwh numeric(20,8) not null default 0,

    redistribution_income_ron numeric(20,4) not null default 0,

    record_status text not null
        check (
            record_status in (
                'actual',
                'forecast',
                'manual_override'
            )
        ),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    primary key (
        run_id,
        month_start
    )
);

comment on table core.balancing_month is
'Monthly balancing deficit, excess, settlement prices and redistribution values until authoritative hourly settlement data is available.';


-- ============================================================
-- CORE: TRADE
-- ============================================================

create table core.trade (
    trade_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    trade_reference text not null,

    book_id bigint not null
        references core.book(book_id),

    product_id bigint
        references core.product(product_id),

    counterparty_id bigint
        references core.counterparty(counterparty_id),

    delivery_from timestamptz not null,
    delivery_to timestamptz not null,

    quantity_mwh numeric(20,8) not null
        check (quantity_mwh >= 0),

    buy_price_per_mwh numeric(20,8),

    sell_price_per_mwh numeric(20,8),

    currency_code char(3) not null default 'RON',

    recognition_month date not null,

    attribution_share numeric(9,6) not null default 1
        check (
            attribution_share between 0 and 1
        ),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    check (delivery_to > delivery_from),

    unique (
        run_id,
        trade_reference
    )
);

comment on table core.trade is
'Optimization and origination trades with explicit delivery period, pricing, recognition period and portfolio attribution.';


-- ============================================================
-- CORE: SERVICE INCOME
-- ============================================================

create table core.service_income (
    service_income_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    month_start date not null,

    service_code text not null,

    counterparty_id bigint
        references core.counterparty(counterparty_id),

    amount numeric(20,4) not null,

    currency_code char(3) not null default 'RON',

    source_cell_id bigint
        references raw.source_cell(source_cell_id)
);

comment on table core.service_income is
'Monthly commercial service income retained separately from physical electricity sourcing.';


-- ============================================================
-- CORE: FEE RULE
-- ============================================================

create table core.fee_rule (
    fee_rule_id bigint generated always as identity primary key,

    venue text not null,

    direction text not null
        check (
            direction in (
                'buy',
                'sell',
                'both'
            )
        ),

    product_id bigint
        references core.product(product_id),

    valid_from date not null,
    valid_to date not null,

    rate_per_mwh numeric(20,8),

    fixed_amount numeric(20,4),

    currency_code char(3) not null default 'RON',

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    check (valid_to >= valid_from),

    check (
        rate_per_mwh is not null
        or fixed_amount is not null
    )
);

comment on table core.fee_rule is
'Effective-dated transaction fee rules by venue, direction and optional product.';


-- ============================================================
-- CORE: GUARANTEE EXPOSURE
-- ============================================================

create table core.guarantee_exposure (
    guarantee_exposure_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    exposure_code text not null,

    beneficiary text,

    guarantee_type text,

    amount numeric(20,4) not null
        check (amount >= 0),

    currency_code char(3) not null default 'EUR',

    annual_cost_ron numeric(20,4),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    unique (
        run_id,
        exposure_code
    )
);

comment on table core.guarantee_exposure is
'Guarantees and collateral exposures together with their estimated annual financing cost.';


-- ============================================================
-- CORE: FX RATE
-- ============================================================

create table core.fx_rate (
    run_id bigint not null
        references core.model_run(run_id),

    rate_date date not null,

    rate_purpose text not null
        check (
            rate_purpose in (
                'forecast',
                'trade_realised',
                'guarantee',
                'historical',
                'reporting'
            )
        ),

    ron_per_eur numeric(20,8) not null
        check (ron_per_eur > 0),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    primary key (
        run_id,
        rate_date,
        rate_purpose
    )
);

comment on table core.fx_rate is
'Purpose-specific RON/EUR exchange rates used by the portfolio model.';


-- ============================================================
-- INDEXES
-- ============================================================

create index ix_hourly_volume_run_measure
    on core.hourly_volume(
        run_id,
        measure_code,
        interval_id
    );

create index ix_hourly_volume_interval
    on core.hourly_volume(interval_id);

create index ix_market_price_interval
    on core.market_price(
        run_id,
        interval_id
    );

create index ix_procurement_contract
    on core.procurement_schedule(
        run_id,
        contract_id,
        interval_id
    );

create index ix_balancing_month
    on core.balancing_month(
        run_id,
        month_start
    );

create index ix_trade_book_month
    on core.trade(
        run_id,
        book_id,
        recognition_month
    );

create index ix_trade_delivery
    on core.trade(
        delivery_from,
        delivery_to
    );

create index ix_service_income_month
    on core.service_income(
        run_id,
        month_start
    );

create index ix_fee_rule_validity
    on core.fee_rule(
        valid_from,
        valid_to
    );

create index ix_guarantee_run
    on core.guarantee_exposure(run_id);

create index ix_fx_rate_date
    on core.fx_rate(
        run_id,
        rate_date
    );