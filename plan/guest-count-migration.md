# Guest-count schema migration

Airbnb exports can include `大人`, `子ども`, and `乳幼児`. The importer maps these
to nullable `INT64` columns `number_of_adults`, `number_of_children`, and
`number_of_infants`. Zero is retained; blank cells become NULL.

Older deployments preserve these unknown headers verbatim. Staging loads can
succeed through schema autodetection, but MERGE fails because the destination
table has no `大人` column. Mapping the headers alone does not upgrade existing
tables: the English columns must be added before deploying this release.

## Upgrade existing tables

Replace `YOUR_PROJECT.YOUR_DATASET.YOUR_TABLE` with the configured audit table
(`GCP_PROJECT_ID.BQ_DATASET_ID.BQ_TABLE_ID`). Run this SQL with GoogleSQL before
deploying the updated importer. The optional current table must also be upgraded
if it exists, including when current-state reconciliation is currently disabled.
The snapshot-state table contains metadata only and needs no change.

```sql
ALTER TABLE `YOUR_PROJECT.YOUR_DATASET.YOUR_TABLE`
  ADD COLUMN IF NOT EXISTS number_of_adults INT64,
  ADD COLUMN IF NOT EXISTS number_of_children INT64,
  ADD COLUMN IF NOT EXISTS number_of_infants INT64;

-- Run this statement only if the current table already exists.
ALTER TABLE `YOUR_PROJECT.YOUR_DATASET.YOUR_TABLE_current`
  ADD COLUMN IF NOT EXISTS number_of_adults INT64,
  ADD COLUMN IF NOT EXISTS number_of_children INT64,
  ADD COLUMN IF NOT EXISTS number_of_infants INT64;
```

The statements can be repeated and do not remove or rewrite existing data. Check
the table identifiers carefully. Existing
columns must already have the expected nullable INT64 type; inspect the schema
after running the migration. New installations get these columns from the
explicit staging schema without this migration.

## Deploy and verify

1. Deploy the updated importer after the schema migration.
2. Allow the pending Eventarc delivery to retry, or upload the original CSV to
   GCS under a new object name if retries have ended. The Drive sync intentionally
   skips an unchanged file, so running it again alone may not emit a new event.
3. Confirm that all input rows load, MERGE succeeds, and these three headers no
   longer appear in unmapped-column warnings. For the November 2026 incident,
   the input contains 540 rows; inserted rows can be fewer because of deduplication.
4. Re-deliver the identical CSV and confirm the audit MERGE inserts zero rows.
5. If `CURRENT_STATE_MODE=apply`, also confirm current-state reconciliation succeeds.

Missing or blank guest counts retain the pre-upgrade `row_id`, so reimporting
legacy CSVs does not create duplicates merely because nullable columns were
added. Populated guest counts participate in the content hash. A row enriched
with counts can therefore have a different ID from its historical version;
the audit table retains both versions under the existing insert-only policy.
Use the current-state table for cumulative-snapshot analysis as described in
[Current-state reconciliation](current-state-reconciliation.md).

## Rollback

Leave the additive nullable columns in place if the application is rolled back.
The previous application can still import legacy files, but exports containing
the three Japanese guest-count headers will fail again. Do not delete audit
history or alter stored row IDs as part of rollback.
