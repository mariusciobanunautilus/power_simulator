/*
 * Power Simulator
 * Permit quantity-only placeholder contracts without inventing pricing metadata.
 */

alter table core.contract
    drop constraint if exists contract_price_method_check;

alter table core.contract
    add constraint contract_price_method_check
    check (
        price_method = any (
            array[
                'fixed'::text,
                'pzu_plus_fee'::text,
                'indexed_other'::text,
                'negotiated'::text,
                'unclassified'::text
            ]
        )
    );

alter table core.contract
    alter column currency_code drop not null;

comment on column core.contract.price_method is
    'Commercial price method. Use unclassified for source-backed placeholder contracts where the workbook does not supply an authoritative price method.';

comment on column core.contract.currency_code is
    'Contract pricing currency when known. May be null for quantity-only source placeholders until authoritative commercial metadata is supplied.';
