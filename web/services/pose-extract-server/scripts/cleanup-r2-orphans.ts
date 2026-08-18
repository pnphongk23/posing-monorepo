/**
 * DEPRECATED — SQLite has been removed from this service.
 *
 * This script previously listed Cloudflare R2 objects under `community/` and
 * reported keys not referenced by any `community_poses.image_path` row read from
 * a local SQLite file (`better-sqlite3` + `DATABASE_PATH`). That database
 * backend is gone; the service now uses Postgres (`DATABASE_URL`).
 *
 * To find R2 orphans manually with Postgres:
 *
 *   1. List all `image_path` values currently referenced in Postgres:
 *        psql "$DATABASE_URL" -c \
 *          "SELECT image_path FROM community_poses WHERE image_path LIKE 'community/%';"
 *
 *   2. List all objects in the R2 bucket:
 *        aws s3 ls "s3://$R2_BUCKET/community/" \
 *          --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com" \
 *          --recursive
 *
 *   3. Any R2 key absent from step 1's output is an orphan candidate. Delete it
 *      only after review (this script never implemented deletion, and still does not).
 */

function main(): void {
  console.error(
    "[cleanup-r2-orphans] DEPRECATED: SQLite removed. " +
      "This service now uses Postgres (DATABASE_URL). " +
      "See the header of this file for the manual orphan-detection steps."
  );
  process.exitCode = 2;
}

main();
