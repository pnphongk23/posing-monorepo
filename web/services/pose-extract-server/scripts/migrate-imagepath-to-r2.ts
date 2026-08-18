/**
 * DEPRECATED — SQLite has been removed from this service.
 *
 * This script previously rewrote `community_poses.image_path` values from local
 * filesystem paths (SQLite era) to Cloudflare R2 public URLs. The service now
 * stores all state in Postgres (`DATABASE_URL`) and community images are uploaded
 * to R2 *before* the pose row is created, so there is no local path left to
 * migrate.
 *
 * For a one-off legacy migration (only if you still hold a pre-Postgres SQLite
 * file), perform the steps manually:
 *
 *   1. Upload each local image to R2 via the admin upload flow:
 *        POST /api/admin/community/poses/upload-url   (get presigned PUT URL)
 *        PUT  <uploadUrl>                              (upload the image bytes)
 *        POST /api/admin/community/poses              (save metadata)
 *
 *   2. Or update the Postgres row directly once the file is in R2:
 *        psql "$DATABASE_URL" -c \
 *          "UPDATE community_poses SET image_path = '<r2 public url>' WHERE id = '<id>';"
 */

function main(): void {
  console.error(
    "[migrate-imagepath-to-r2] DEPRECATED: SQLite removed. " +
      "This service now uses Postgres (DATABASE_URL) and R2. " +
      "See the header of this file for the manual migration steps."
  );
  process.exitCode = 2;
}

main();
