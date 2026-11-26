# Reservation-detail schema migration

Airbnb CSV headers `予約ステータス` and `連絡先` map to nullable STRING columns
`reservation_status` and `contact`. Contact values remain strings, retaining
leading zeros, plus signs, and formatting. Blank cells become NULL.

Earlier deployments preserve these headers under their raw Japanese names.
Staging autodetection can accept them, but MERGE fails when the existing target
table does not contain the columns. Both the explicit importer schema and the
existing BigQuery tables must be upgraded.

## Upgrade and deploy

Run the following GoogleSQL against the configured audit table before deploying:

```sql
ALTER TABLE `YOUR_PROJECT.YOUR_DATASET.YOUR_TABLE`
  ADD COLUMN IF NOT EXISTS reservation_status STRING,
  ADD COLUMN IF NOT EXISTS contact STRING;

-- Run only if the current-state table already exists.
ALTER TABLE `YOUR_PROJECT.YOUR_DATASET.YOUR_TABLE_current`
  ADD COLUMN IF NOT EXISTS reservation_status STRING,
  ADD COLUMN IF NOT EXISTS contact STRING;
```

These additive changes preserve existing rows. Verify that both columns are
nullable STRINGs in every existing audit/current table. The snapshot-state
metadata table needs no change. The migration is required even for CSVs without
the new headers because the transformer fills missing schema columns with NULL.

Deploy the updated importer while retaining the configured service account,
environment variables, secrets, and current-state mode. Allow pending Eventarc
deliveries to retry, or replay the original bucket/name payload against the
authenticated service. Reusing the original object retains its generation and
creation time for cumulative-snapshot ordering.

## Verify

1. Confirm the original CSV loads and MERGE completes without unmapped warnings
   for these two headers.
2. Redeliver the same object and confirm the audit MERGE inserts zero rows.
3. If current-state reconciliation is enabled, confirm it completes or skips
   the previously applied snapshot.

Absent or blank reservation details preserve legacy row IDs. Populated details
participate in the content hash with their field names; enriched historical
rows can therefore receive new IDs under the insert-only audit policy. This
does not rewrite historical rows. Do not log contact values during verification.

## Rollback

Roll back the Cloud Run revision if needed and retain the nullable columns.
Older revisions will again fail for CSVs containing the two unmapped headers.
Do not delete audit history or change stored row IDs.
