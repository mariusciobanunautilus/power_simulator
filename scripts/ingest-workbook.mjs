import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import ExcelJS from 'exceljs';
import pg from 'pg';

const { Client } = pg;

const RUN_ID = 1;
const SOURCE_FILE_ID = 1;

const EXPECTED_FILENAME = 'Simulare_2026_wk39.xlsx';
const EXPECTED_SHA256 =
  '5f931168f0ae465963f4c43ab9cc74f5714c2d664a03b56a17ab2e412a2c32a6';
const EXPECTED_SIZE = 1262697;

const CELL_BATCH_SIZE = 750;
const REF_BATCH_SIZE = 1000;


function usage() {
  console.error(
    'Usage: node scripts/ingest-workbook.mjs /absolute/path/Simulare_2026_wk39.xlsx'
  );
}


function chunks(items, size) {
  const out = [];

  for (let i = 0; i < items.length; i += size) {
    out.push(items.slice(i, i + size));
  }

  return out;
}


function hashFile(filePath) {
  const hash = crypto.createHash('sha256');

  hash.update(fs.readFileSync(filePath));

  return hash.digest('hex');
}


function valueToText(value) {
  if (value === null || value === undefined) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean'
  ) {
    return String(value);
  }

  if (typeof value === 'object') {
    if ('error' in value) {
      return String(value.error);
    }

    if ('text' in value && value.text !== undefined) {
      return String(value.text);
    }

    if (Array.isArray(value.richText)) {
      return value.richText
        .map((part) => part?.text ?? '')
        .join('');
    }

    try {
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  }

  return String(value);
}


function getFormula(cell) {
  try {
    return cell.formula ?? null;
  } catch {
    const value = cell.value;

    if (
      value &&
      typeof value === 'object' &&
      'formula' in value
    ) {
      return value.formula ?? null;
    }

    return null;
  }
}


function getCachedResult(cell) {
  try {
    return cell.result ?? null;
  } catch {
    const value = cell.value;

    if (
      value &&
      typeof value === 'object' &&
      'result' in value
    ) {
      return value.result ?? null;
    }

    return null;
  }
}


function classifyCell(cell, formula, cachedResult) {
  if (formula) {
    if (
      cachedResult &&
      typeof cachedResult === 'object' &&
      'error' in cachedResult
    ) {
      return 'error';
    }

    return 'formula';
  }

  if (
    cell.value === null ||
    cell.value === undefined
  ) {
    return 'blank';
  }

  if (
    cell.value &&
    typeof cell.value === 'object' &&
    'error' in cell.value
  ) {
    return 'error';
  }

  return 'manual';
}


/*
 * Captures standard Excel A1 references such as:
 *
 *   A1
 *   $A$1
 *   A1:B10
 *   'Books result'!C15
 *   2026!$D$20
 *
 * Defined names and structured table references are intentionally
 * left for the semantic transformation phase.
 */
const A1_REF_RE =
  /(?:(?:'((?:[^']|'')+)'|([A-Za-z0-9_][A-Za-z0-9_.]*))!)?(\$?[A-Z]{1,3}\$?\d+(?::\$?[A-Z]{1,3}\$?\d+)?)/g;


function extractFormulaReferences(
  formula,
  currentSheet,
  workbookSheets
) {
  if (!formula) {
    return [];
  }

  /*
   * Remove Excel string literals before reference parsing.
   * Otherwise text such as "A1" could incorrectly be treated
   * as a cell dependency.
   */
  const scanFormula =
    formula.replace(/"(?:[^"]|"")*"/g, '');

  const refs = [];

  let match;
  let ordinal = 0;

  A1_REF_RE.lastIndex = 0;

  while (
    (match = A1_REF_RE.exec(scanFormula)) !== null
  ) {
    ordinal += 1;

    const quotedSheet =
      match[1]?.replace(/''/g, "'") ?? null;

    const unquotedSheet =
      match[2] ?? null;

    const sheetName =
      quotedSheet ??
      unquotedSheet ??
      currentSheet;

    const range =
      match[3];

    const explicitlyQualified =
      Boolean(quotedSheet ?? unquotedSheet);

    const sheetExists =
      workbookSheets.has(sheetName);

    refs.push({
      tokenOrdinal: ordinal,

      referenceText:
        match[0],

      resolvedSheetName:
        sheetExists
          ? sheetName
          : null,

      resolvedRange:
        range,

      parseStatus:
        sheetExists
          ? 'resolved'
          : explicitlyQualified
            ? 'unresolved'
            : 'partial',
    });
  }

  return refs;
}


async function insertCells(
  client,
  sourceFileId,
  cells
) {
  const idMap = new Map();

  for (
    const batch of chunks(
      cells,
      CELL_BATCH_SIZE
    )
  ) {
    const values = [];
    const placeholders = [];

    for (const row of batch) {
      const base = values.length;

      values.push(
        sourceFileId,
        row.sheetName,
        row.cellAddress,
        row.rawText,
        row.formulaText,
        row.cachedText,
        row.numberFormat,
        row.valueStatus,
        row.parseError
      );

      placeholders.push(
        `(${
          Array.from(
            { length: 9 },
            (_, i) => `$${base + i + 1}`
          ).join(',')
        })`
      );
    }

    const sql = `
      insert into raw.source_cell (
        source_file_id,
        sheet_name,
        cell_address,
        raw_text,
        formula_text,
        cached_text,
        number_format,
        value_status,
        parse_error
      )
      values ${placeholders.join(',')}
      returning
        source_cell_id,
        sheet_name,
        cell_address
    `;

    const result =
      await client.query(
        sql,
        values
      );

    for (const row of result.rows) {
      idMap.set(
        `${row.sheet_name}!${row.cell_address}`,
        Number(row.source_cell_id)
      );
    }
  }

  return idMap;
}


async function insertFormulaRefs(
  client,
  refs
) {
  for (
    const batch of chunks(
      refs,
      REF_BATCH_SIZE
    )
  ) {
    const values = [];
    const placeholders = [];

    for (const ref of batch) {
      const base = values.length;

      values.push(
        ref.sourceCellId,
        ref.tokenOrdinal,
        ref.referenceText,
        ref.resolvedSheetName,
        ref.resolvedRange,
        ref.parseStatus
      );

      placeholders.push(
        `(${
          Array.from(
            { length: 6 },
            (_, i) => `$${base + i + 1}`
          ).join(',')
        })`
      );
    }

    await client.query(
      `
        insert into raw.formula_reference (
          source_cell_id,
          token_ordinal,
          reference_text,
          resolved_sheet_name,
          resolved_range,
          parse_status
        )
        values ${placeholders.join(',')}
      `,
      values
    );
  }
}


async function insertRejects(
  client,
  batchId,
  rejects
) {
  if (rejects.length === 0) {
    return;
  }

  for (
    const batch of chunks(
      rejects,
      500
    )
  ) {
    const values = [];
    const placeholders = [];

    for (const reject of batch) {
      const base = values.length;

      values.push(
        batchId,
        reject.sourceLocation,
        reject.errorCode,
        reject.offendingValue,
        reject.errorMessage,
        reject.remediation
      );

      placeholders.push(
        `(${
          Array.from(
            { length: 6 },
            (_, i) => `$${base + i + 1}`
          ).join(',')
        })`
      );
    }

    await client.query(
      `
        insert into raw.import_reject (
          batch_id,
          source_location,
          error_code,
          offending_value,
          error_message,
          remediation
        )
        values ${placeholders.join(',')}
      `,
      values
    );
  }
}


async function main() {
  const workbookArg =
    process.argv[2];

  if (!workbookArg) {
    usage();

    process.exitCode = 2;

    return;
  }

  const workbookPath =
    path.resolve(workbookArg);

  if (!fs.existsSync(workbookPath)) {
    throw new Error(
      `Workbook not found: ${workbookPath}`
    );
  }


  /*
   * ==========================================================
   * VERIFY SOURCE FILE
   * ==========================================================
   */

  const stat =
    fs.statSync(workbookPath);

  const actualHash =
    hashFile(workbookPath);


  if (
    path.basename(workbookPath) !==
    EXPECTED_FILENAME
  ) {
    throw new Error(
      `Unexpected filename. Expected ${EXPECTED_FILENAME}, ` +
      `got ${path.basename(workbookPath)}`
    );
  }


  if (
    stat.size !==
    EXPECTED_SIZE
  ) {
    throw new Error(
      `File size mismatch. Expected ${EXPECTED_SIZE}, ` +
      `got ${stat.size}`
    );
  }


  if (
    actualHash !==
    EXPECTED_SHA256
  ) {
    throw new Error(
      `SHA-256 mismatch. Expected ${EXPECTED_SHA256}, ` +
      `got ${actualHash}`
    );
  }


  /*
   * ==========================================================
   * VERIFY DATABASE ENVIRONMENT
   * ==========================================================
   */

  for (
    const name of [
      'PGHOST',
      'PGPORT',
      'PGDATABASE',
      'PGUSER',
      'PGPASSWORD',
    ]
  ) {
    if (!process.env[name]) {
      throw new Error(
        `Missing environment variable: ${name}`
      );
    }
  }


  console.log(
    `Workbook verified: ${workbookPath}`
  );

  console.log(
    `SHA-256: ${actualHash}`
  );


  /*
   * ==========================================================
   * DATABASE CONNECTION
   * ==========================================================
   */

  const client =
    new Client({
      ssl: true,
    });


  await client.connect();


  let batchId = null;


  try {

    /*
     * ========================================================
     * VERIFY SOURCE MANIFEST
     * ========================================================
     */

    const sourceResult =
      await client.query(
        `
          select
            source_file_id,
            run_id,
            filename,
            sha256,
            file_size_bytes
          from raw.source_file
          where
            source_file_id = $1
            and run_id = $2
        `,
        [
          SOURCE_FILE_ID,
          RUN_ID,
        ]
      );


    if (
      sourceResult.rowCount !== 1
    ) {
      throw new Error(
        `Expected raw.source_file ${SOURCE_FILE_ID} ` +
        `for run ${RUN_ID}`
      );
    }


    const source =
      sourceResult.rows[0];


    if (
      source.filename !==
        EXPECTED_FILENAME ||

      source.sha256.trim() !==
        EXPECTED_SHA256 ||

      Number(
        source.file_size_bytes
      ) !== EXPECTED_SIZE
    ) {
      throw new Error(
        'Database source_file metadata does not match ' +
        'the workbook being loaded'
      );
    }


    /*
     * ========================================================
     * IMMUTABILITY GUARD
     * ========================================================
     *
     * Raw workbook evidence is append-only.
     * Never silently overwrite previously ingested evidence.
     */

    const existing =
      await client.query(
        `
          select
            count(*)::bigint as n
          from raw.source_cell
          where source_file_id = $1
        `,
        [SOURCE_FILE_ID]
      );


    if (
      BigInt(
        existing.rows[0].n
      ) > 0n
    ) {
      throw new Error(
        `raw.source_cell already contains evidence for ` +
        `source_file_id=${SOURCE_FILE_ID}. ` +
        `Refusing to overwrite immutable evidence.`
      );
    }


    /*
     * ========================================================
     * CREATE IMPORT BATCH
     * ========================================================
     */

    const batchResult =
      await client.query(
        `
          insert into raw.import_batch (
            run_id,
            source_file_id,
            source_type,
            status,
            batch_checksum
          )
          values (
            $1,
            $2,
            'excel_workbook_cells',
            'started',
            $3
          )
          returning batch_id
        `,
        [
          RUN_ID,
          SOURCE_FILE_ID,
          actualHash,
        ]
      );


    batchId =
      Number(
        batchResult.rows[0].batch_id
      );


    console.log(
      `Import batch created: ${batchId}`
    );


    /*
     * ========================================================
     * READ WORKBOOK
     * ========================================================
     */

    const workbook =
      new ExcelJS.Workbook();


    await workbook.xlsx.readFile(
      workbookPath
    );


    const sheetNames =
      new Set(
        workbook.worksheets.map(
          (worksheet) =>
            worksheet.name
        )
      );


    const cells = [];

    const pendingRefs = [];

    const rejects = [];


    let rowsReceived = 0;

    let formulaCount = 0;

    let ignoredBlankCells = 0;


    /*
     * ========================================================
     * EXTRACT WORKBOOK EVIDENCE
     * ========================================================
     */

    for (
      const worksheet of
      workbook.worksheets
    ) {

      console.log(
        `Scanning: ${worksheet.name}`
      );


      worksheet.eachRow(
        {
          includeEmpty: false,
        },

        (row) => {

          row.eachCell(
            {
              includeEmpty: false,
            },

            (cell) => {

              /*
               * ExcelJS may expose blank placeholder cells that
               * exist only because they are part of a merged
               * range or carry formatting/style metadata.
               *
               * They contain no source value and therefore are
               * not workbook evidence.
               *
               * Ignoring them prevents false CELL_PARSE_ERROR
               * records such as:
               *
               *   2026!C2
               *   2026!C4
               *   2026!C5
               *   2026!A41
               */

              if (
                cell.value === null ||
                cell.value === undefined
              ) {
                ignoredBlankCells += 1;

                return;
              }


              rowsReceived += 1;


              try {

                const formula =
                  getFormula(cell);


                const cachedResult =
                  formula
                    ? getCachedResult(cell)
                    : null;


                const valueStatus =
                  classifyCell(
                    cell,
                    formula,
                    cachedResult
                  );


                /*
                 * Prefer cell.text for Excel's formatted textual
                 * representation, but fall back to the raw value
                 * if ExcelJS cannot render it.
                 */

                let rawText;

                try {
                  rawText =
                    valueToText(
                      cell.text
                    );
                } catch {
                  rawText =
                    valueToText(
                      cell.value
                    );
                }


                const cachedText =
                  formula
                    ? valueToText(
                        cachedResult
                      )
                    : null;


                const numberFormat =
                  cell.numFmt ||
                  null;


                cells.push({
                  sheetName:
                    worksheet.name,

                  cellAddress:
                    cell.address,

                  rawText,

                  formulaText:
                    formula,

                  cachedText,

                  numberFormat,

                  valueStatus,

                  parseError:
                    null,
                });


                /*
                 * Extract formula dependencies.
                 */

                if (formula) {

                  formulaCount += 1;


                  for (
                    const ref of
                    extractFormulaReferences(
                      formula,
                      worksheet.name,
                      sheetNames
                    )
                  ) {

                    pendingRefs.push({
                      sheetName:
                        worksheet.name,

                      cellAddress:
                        cell.address,

                      ...ref,
                    });
                  }
                }

              } catch (error) {

                /*
                 * Bad cells are quarantined rather than silently
                 * discarded.
                 */

                rejects.push({
                  sourceLocation:
                    `${worksheet.name}!${cell.address}`,

                  errorCode:
                    'CELL_PARSE_ERROR',

                  offendingValue:
                    valueToText(
                      cell.value
                    ),

                  errorMessage:
                    error instanceof Error
                      ? error.message
                      : String(error),

                  remediation:
                    'Inspect the workbook cell and extend ' +
                    'the loader if this Excel value type ' +
                    'requires special handling.',
                });
              }
            }
          );
        }
      );
    }


    console.log(
      `Source cells found: ${rowsReceived}`
    );

    console.log(
      `Ignored blank merge/style cells: ${ignoredBlankCells}`
    );

    console.log(
      `Formula cells found: ${formulaCount}`
    );

    console.log(
      `Formula references found: ${pendingRefs.length}`
    );

    console.log(
      `Cell parse rejects: ${rejects.length}`
    );


    /*
     * Workbook parsing finished successfully.
     */

    await client.query(
      `
        update raw.import_batch
        set
          status = 'parsed',
          rows_received = $2,
          rows_rejected = $3
        where batch_id = $1
      `,
      [
        batchId,
        rowsReceived,
        rejects.length,
      ]
    );


    /*
     * ========================================================
     * LOAD DATABASE TRANSACTION
     * ========================================================
     */

    await client.query(
      'begin'
    );


    const idMap =
      await insertCells(
        client,
        SOURCE_FILE_ID,
        cells
      );


    /*
     * Convert workbook dependency references into database
     * source_cell IDs.
     */

    const refs = [];


    for (
      const ref of
      pendingRefs
    ) {

      const sourceCellId =
        idMap.get(
          `${ref.sheetName}!${ref.cellAddress}`
        );


      if (!sourceCellId) {

        rejects.push({
          sourceLocation:
            `${ref.sheetName}!${ref.cellAddress}`,

          errorCode:
            'REFERENCE_PARENT_NOT_FOUND',

          offendingValue:
            ref.referenceText,

          errorMessage:
            'Formula reference parent cell was not ' +
            'returned after source_cell insert.',

          remediation:
            'Review source_cell insertion and ' +
            'workbook cell uniqueness.',
        });


        continue;
      }


      refs.push({
        sourceCellId,

        tokenOrdinal:
          ref.tokenOrdinal,

        referenceText:
          ref.referenceText,

        resolvedSheetName:
          ref.resolvedSheetName,

        resolvedRange:
          ref.resolvedRange,

        parseStatus:
          ref.parseStatus,
      });
    }


    await insertFormulaRefs(
      client,
      refs
    );


    await insertRejects(
      client,
      batchId,
      rejects
    );


    /*
     * ========================================================
     * CLOSE IMPORT BATCH
     * ========================================================
     */

    await client.query(
      `
        update raw.import_batch
        set
          completed_at = now(),
          rows_received = $2,
          rows_loaded = $3,
          rows_rejected = $4,
          status = 'loaded'
        where batch_id = $1
      `,
      [
        batchId,
        rowsReceived,
        cells.length,
        rejects.length,
      ]
    );


    await client.query(
      'commit'
    );


    /*
     * ========================================================
     * FINAL REPORT
     * ========================================================
     */

    console.log(
      'Workbook ingestion completed successfully.'
    );

    console.log(
      `Loaded source cells: ${cells.length}`
    );

    console.log(
      `Loaded formula references: ${refs.length}`
    );

    console.log(
      `Rejected records: ${rejects.length}`
    );

    console.log(
      `Ignored blank cells: ${ignoredBlankCells}`
    );

    console.log(
      `Import batch: ${batchId}`
    );

  } catch (error) {

    /*
     * Roll back any incomplete transactional load.
     */

    try {
      await client.query(
        'rollback'
      );
    } catch {
      // No active transaction.
    }


    /*
     * Preserve failed batch audit information where possible.
     */

    if (batchId !== null) {

      try {

        await client.query(
          `
            update raw.import_batch
            set
              completed_at = now(),
              status = 'failed'
            where batch_id = $1
          `,
          [batchId]
        );

      } catch (auditError) {

        console.error(
          'Could not mark import batch as failed:',
          auditError
        );
      }
    }


    throw error;

  } finally {

    await client.end();

  }
}


main().catch(
  (error) => {

    console.error(
      '\nINGESTION FAILED'
    );

    console.error(
      error instanceof Error
        ? error.stack
        : error
    );

    process.exitCode = 1;
  }
);