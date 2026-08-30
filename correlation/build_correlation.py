#!/usr/bin/env python3
"""Build a compact, deterministic correlation bundle from sealed TSV evidence.

This builder reads only the explicitly approved evidence paths.  It never reads
the preserved cache payloads, source bodies, Huge-Gists, or external volumes.
Canonical payloads are checked only by manifest-listed stat/hash/readability
operations, with no excerpts or materialization.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path("/private/tmp/paseo-recovery-filebasedindex-20260815")
CORRELATION = ROOT / "correlation"
JETBRAINS = Path("/private/tmp/paseo-jetbrains/final-recovery-20260815")
REFERENCE = Path("/Users/phamnhuphong/Desktop/JetBrains-Recovery-20260815/Reference")
BUILD = "233.11799.241"
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


INPUTS = [
    (ROOT / "preserved/evidence/file-manifest.tsv", "authoritative-preservation-manifest"),
    (ROOT / "preserved/REPORT.md", "preservation-report"),
    (ROOT / "replacement-control/peer1-preservation-report.md", "peer-preservation-report"),
    (ROOT / "replacement-control/peer1-preservation-seal.txt", "peer-preservation-seal"),
    (ROOT / "decode-continuation/REPORT.md", "decoder-report"),
    (ROOT / "decode-continuation/SEAL.txt", "decoder-seal"),
    (ROOT / "decode-continuation/records.tsv", "decoder-records"),
    (ROOT / "decode-continuation/names.tsv", "decoder-names"),
    (ROOT / "decode-continuation/paths.tsv", "decoder-paths"),
    (ROOT / "decode-continuation/content-records.tsv", "decoder-content-records"),
    (ROOT / "decode-continuation/content-hashes.tsv", "decoder-content-hashes"),
    (ROOT / "decode-continuation/vfs-content-joins.tsv", "decoder-vfs-content-joins"),
    (ROOT / "decode-continuation/project-summary.tsv", "decoder-project-summary"),
    (ROOT / "decode-continuation/parser-layout.tsv", "decoder-parser-layout"),
    (ROOT / "decode-continuation/negative-findings.tsv", "decoder-negative-findings"),
    (ROOT / "decode/artifact-manifest.tsv", "decoder-artifact-manifest"),
    (JETBRAINS / "all-revisions/manifest.tsv", "sealed-localhistory-all-revisions"),
    (JETBRAINS / "best-effort-latest/manifest.tsv", "sealed-localhistory-best-effort-latest"),
    (JETBRAINS / "canonical-payloads/canonical-payload-manifest.tsv", "sealed-canonical-payload-manifest"),
    (JETBRAINS / "reports/final-sha256-manifest.tsv", "sealed-localhistory-final-sha256"),
    (REFERENCE / "IntelliJ-2023.3-product-info.json", "reference-stat-hash-only"),
    (REFERENCE / "IntelliJ-2023.3-app.jar", "reference-stat-hash-only"),
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def stream_tsv(path: Path):
    handle = path.open("r", encoding="utf-8", newline="")
    return handle, csv.DictReader(handle, delimiter="\t")


def write_tsv(path: Path, columns: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in columns})


def safe_int(value: str | None, default: int = 0) -> int:
    try:
        return int(value or "")
    except ValueError:
        return default


def project_bucket(value: str) -> str:
    lowered = value.lower()
    for name in ("spotify", "topcoach", "ymner", "intellilove"):
        if re.search(rf"(^|[/\\ ._-]){re.escape(name)}([/\\ ._-]|$)", lowered):
            return name
    return "OTHER_ROOTS"


def manifest_hashes(path: Path, sha_column: str = "sha256") -> tuple[set[str], int]:
    hashes: set[str] = set()
    rows = 0
    handle, reader = stream_tsv(path)
    try:
        for row in reader:
            rows += 1
            value = (row.get(sha_column) or "").strip().lower()
            if SHA256_RE.fullmatch(value):
                hashes.add(value)
    finally:
        handle.close()
    return hashes, rows


def canonical_manifest_audit(path: Path) -> dict[str, object]:
    """Audit only manifest-listed canonical payload paths by stat/hash/readability."""
    rows = read_tsv(path)
    checked = missing = unreadable = size_mismatch = hash_mismatch = 0
    for row in rows:
        relative = (row.get("canonical_path") or "").strip()
        expected_size = safe_int(row.get("bytes"), -1)
        expected_hash = (row.get("sha256") or "").strip().lower()
        candidate = JETBRAINS / relative
        if not candidate.is_file():
            missing += 1
            continue
        try:
            stat_result = candidate.stat()
            if not os.access(candidate, os.R_OK):
                unreadable += 1
                continue
            checked += 1
            if expected_size >= 0 and stat_result.st_size != expected_size:
                size_mismatch += 1
            if SHA256_RE.fullmatch(expected_hash) and sha256_file(candidate) != expected_hash:
                hash_mismatch += 1
        except OSError:
            unreadable += 1
    return {
        "manifest_rows": len(rows),
        "checked": checked,
        "missing": missing,
        "unreadable": unreadable,
        "size_mismatch": size_mismatch,
        "hash_mismatch": hash_mismatch,
    }


def artifact_meta(path: Path) -> dict[str, object]:
    stat_result = path.stat()
    return {
        "path": path.name,
        "bytes": stat_result.st_size,
        "sha256": sha256_file(path),
        "readability": "PASS" if os.access(path, os.R_OK) else "FAIL",
    }


def build(output_dir: Path) -> None:
    output_dir = output_dir.resolve()
    correlation = CORRELATION.resolve()
    if correlation not in output_dir.parents and output_dir != correlation:
        raise SystemExit(f"refusing output outside correlation scope: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest_path = ROOT / "preserved/evidence/file-manifest.tsv"
    manifest_rows = read_tsv(manifest_path)
    join_rows = read_tsv(ROOT / "decode-continuation/vfs-content-joins.tsv")
    join_record_ids = {row.get("record_id", "") for row in join_rows}
    join_content_ids = {row.get("content_id", "") for row in join_rows}

    paths_by_record: dict[str, dict[str, str]] = {}
    path_handle, path_reader = stream_tsv(ROOT / "decode-continuation/paths.tsv")
    try:
        for row in path_reader:
            record_id = row.get("record_id", "")
            if record_id in join_record_ids:
                paths_by_record[record_id] = row
    finally:
        path_handle.close()

    content_by_id: dict[str, dict[str, str]] = {}
    unique_content_hashes: set[str] = set()
    content_rows = 0
    content_handle, content_reader = stream_tsv(ROOT / "decode-continuation/content-records.tsv")
    try:
        for row in content_reader:
            content_rows += 1
            content_id = row.get("content_id", "")
            if content_id in join_content_ids:
                content_by_id[content_id] = row
            value = (row.get("sha256") or "").strip().lower()
            if content_id != "0" and SHA256_RE.fullmatch(value):
                unique_content_hashes.add(value)
    finally:
        content_handle.close()

    records_data_rows = 0
    records_handle, records_reader = stream_tsv(ROOT / "decode-continuation/records.tsv")
    try:
        for _ in records_reader:
            records_data_rows += 1
    finally:
        records_handle.close()

    lh_sources = [
        (JETBRAINS / "all-revisions/manifest.tsv", "all-revisions/manifest.tsv"),
        (JETBRAINS / "best-effort-latest/manifest.tsv", "best-effort-latest/manifest.tsv"),
        (JETBRAINS / "canonical-payloads/canonical-payload-manifest.tsv", "canonical-payloads/canonical-payload-manifest.tsv"),
        (JETBRAINS / "reports/final-sha256-manifest.tsv", "reports/final-sha256-manifest.tsv"),
    ]
    lh_by_source: dict[str, set[str]] = {}
    lh_rows_by_source: dict[str, int] = {}
    for path, label in lh_sources:
        hashes, rows = manifest_hashes(path)
        lh_by_source[label] = hashes
        lh_rows_by_source[label] = rows
    lh_union = set().union(*lh_by_source.values()) if lh_by_source else set()

    join_columns = [
        "record_id", "inferred_path", "path_status", "parent_status", "name_status",
        "content_id", "content_storage_status", "content_hash", "join_status", "payload_status",
        "fbi_stub_file_id", "fbi_stub_file_id_status", "vfs_path_confidence", "content_confidence",
        "localhistory_hash_status", "project_bucket", "provenance",
    ]
    correlation_rows: list[dict[str, object]] = []
    project_join_counts: Counter[str] = Counter()
    project_valid_counts: Counter[str] = Counter()
    project_out_of_range: Counter[str] = Counter()
    project_hashes: defaultdict[str, set[str]] = defaultdict(set)
    project_existing: Counter[str] = Counter()
    project_unknown: Counter[str] = Counter()
    valid_refs = out_of_range_refs = 0
    for row in join_rows:
        record_id = row.get("record_id", "")
        path_row = paths_by_record.get(record_id, {})
        inferred_path = path_row.get("canonical_path", "")
        content_id = row.get("content_id", "")
        content_row = content_by_id.get(content_id)
        bucket = project_bucket(inferred_path)
        project_join_counts[bucket] += 1
        in_range = content_row is not None
        if in_range:
            valid_refs += 1
            project_valid_counts[bucket] += 1
        else:
            out_of_range_refs += 1
            project_out_of_range[bucket] += 1
        content_hash = (row.get("content_hash") or "").strip().lower()
        decoder_hash = (content_row or {}).get("sha256", "").strip().lower()
        content_valid = bool(content_row) and (content_row.get("read_status", "").startswith("VALID"))
        if content_valid and decoder_hash and content_hash and decoder_hash != content_hash:
            content_confidence = "UNKNOWN_HASH_FIELD_MISMATCH"
        elif content_valid:
            content_confidence = "VERIFIED"
        else:
            content_confidence = "UNKNOWN_OUT_OF_RANGE"
        if not in_range:
            lh_status = "NOT_CHECKED_OUT_OF_RANGE"
        elif content_hash in lh_union:
            lh_status = "HASH_EQUAL_BYTES_ONLY"
            project_existing[bucket] += 1
        else:
            lh_status = "NO_HASH_EQUALITY_OBSERVED"
            project_unknown[bucket] += 1
        if content_hash and content_hash in unique_content_hashes:
            project_hashes[bucket].add(content_hash)
        correlation_rows.append({
            "record_id": record_id,
            "inferred_path": inferred_path,
            "path_status": path_row.get("path_status", "UNKNOWN"),
            "parent_status": path_row.get("parent_status", "UNKNOWN"),
            "name_status": path_row.get("name_status", "UNKNOWN"),
            "content_id": content_id,
            "content_storage_status": row.get("storage_status", ""),
            "content_hash": content_hash,
            "join_status": row.get("join_status", ""),
            "payload_status": row.get("payload_status", ""),
            "fbi_stub_file_id": "",
            "fbi_stub_file_id_status": "UNKNOWN_EXACT_SERIALIZER_ABSENT",
            "vfs_path_confidence": "INFERRED_PATH",
            "content_confidence": content_confidence,
            "localhistory_hash_status": lh_status,
            "project_bucket": bucket,
            "provenance": "decode-continuation/vfs-content-joins.tsv + paths.tsv + content-records.tsv; exact serializer absent",
        })

    write_tsv(output_dir / "correlation-joins.tsv", join_columns, correlation_rows)

    def inventory_category(relative_path: str) -> str | None:
        lowered = relative_path.lower()
        if "indices.enum" in lowered:
            return "indices.enum"
        if "persistent-index" in lowered or ".persistent" in lowered:
            return "persistent-index"
        if "shared_index" in lowered or "shared-index" in lowered or "shared_indexes" in lowered:
            return "shared-index"
        if "filebasedindex" in lowered or "file-based-index" in lowered:
            return "filebasedindex"
        if "stub" in lowered:
            return "stub"
        if "stamp" in lowered:
            return "stamp"
        return None

    inventory_groups: defaultdict[str, list[dict[str, str]]] = defaultdict(list)
    for row in manifest_rows:
        category = inventory_category(row.get("relative_path", ""))
        if category:
            inventory_groups[category].append(row)
    inventory_columns = [
        "inventory_kind", "category", "count", "logical_bytes", "relative_path", "classification",
        "logical_size", "source_sha256", "cmp_status", "claim_status", "file_id_status",
        "serializer_status", "freshness_status", "provenance",
    ]
    inventory_output: list[dict[str, object]] = []
    categories = ["filebasedindex", "stub", "shared-index", "indices.enum", "persistent-index", "stamp"]
    for category in categories:
        rows = sorted(inventory_groups.get(category, []), key=lambda item: item.get("relative_path", ""))
        inventory_output.append({
            "inventory_kind": "category-summary",
            "category": category,
            "count": len(rows),
            "logical_bytes": sum(safe_int(item.get("logical_size")) for item in rows),
            "relative_path": "-",
            "classification": "manifest-only",
            "logical_size": "",
            "source_sha256": "",
            "cmp_status": "",
            "claim_status": "VERIFIED_MANIFEST_SCOPE" if rows else "UNKNOWN_NOT_OBSERVED_IN_MANIFEST",
            "file_id_status": "UNKNOWN_EXACT_SERIALIZER_ABSENT",
            "serializer_status": "UNKNOWN_EXACT_PLATFORM_SERIALIZER_ABSENT",
            "freshness_status": "METADATA_ONLY_FRESHNESS_VERSION",
            "provenance": "preserved/evidence/file-manifest.tsv only; no payload read",
        })
        for item in rows:
            inventory_output.append({
                "inventory_kind": "manifest-file",
                "category": category,
                "count": 1,
                "logical_bytes": safe_int(item.get("logical_size")),
                "relative_path": item.get("relative_path", ""),
                "classification": item.get("classification", ""),
                "logical_size": item.get("logical_size", ""),
                "source_sha256": item.get("source_sha256", ""),
                "cmp_status": item.get("cmp_or_safe_equivalent", ""),
                "claim_status": item.get("claim_status", ""),
                "file_id_status": "UNKNOWN_EXACT_SERIALIZER_ABSENT",
                "serializer_status": "UNKNOWN_EXACT_PLATFORM_SERIALIZER_ABSENT",
                "freshness_status": "METADATA_ONLY_FRESHNESS_VERSION",
                "provenance": "preserved/evidence/file-manifest.tsv; manifest row only",
            })
    write_tsv(output_dir / "filebasedindex-stub-inventory.tsv", inventory_columns, inventory_output)

    project_summary_rows = read_tsv(ROOT / "decode-continuation/project-summary.tsv")
    summary_by_bucket: defaultdict[str, list[dict[str, str]]] = defaultdict(list)
    for row in project_summary_rows:
        summary_by_bucket[project_bucket(row.get("project_root", ""))].append(row)
    project_columns = [
        "project_bucket", "metadata_path_count", "join_rows", "valid_content_refs", "out_of_range_refs",
        "unique_content_hashes", "localhistory_hash_equal_rows", "new_count", "existing_count", "unknown_count",
        "metadata_confidence", "hash_confidence", "lifecycle_confidence", "provenance",
    ]
    project_output: list[dict[str, object]] = []
    for bucket in ["spotify", "topcoach", "ymner", "intellilove", "OTHER_ROOTS"]:
        metadata_count = sum(safe_int(row.get("path_count")) for row in summary_by_bucket.get(bucket, []))
        join_count = project_join_counts[bucket]
        existing_count = project_existing[bucket]
        unknown_count = project_unknown[bucket] + project_out_of_range[bucket]
        project_output.append({
            "project_bucket": bucket,
            "metadata_path_count": metadata_count,
            "join_rows": join_count,
            "valid_content_refs": project_valid_counts[bucket],
            "out_of_range_refs": project_out_of_range[bucket],
            "unique_content_hashes": len(project_hashes[bucket]),
            "localhistory_hash_equal_rows": existing_count,
            "new_count": 0,
            "existing_count": existing_count,
            "unknown_count": unknown_count,
            "metadata_confidence": "INFERRED_CANDIDATE_GRAPH" if metadata_count else "UNKNOWN_ZERO_OR_NOT_OBSERVED",
            "hash_confidence": "BYTES_ONLY_HASH_EQUALITY; ABSENCE_NOT_NEW",
            "lifecycle_confidence": "UNKNOWN",
            "provenance": "decode-continuation/project-summary.tsv + correlation-joins.tsv; no source authorship claim",
        })
    write_tsv(output_dir / "project-correlation-summary.tsv", project_columns, project_output)

    lh_columns = [
        "row_kind", "manifest", "manifest_rows", "content_unique_hashes_checked", "intersection_unique_hashes",
        "content_sha256", "claim", "confidence", "provenance",
    ]
    lh_output: list[dict[str, object]] = []
    for label in sorted(lh_by_source):
        intersection = sorted(unique_content_hashes & lh_by_source[label])
        lh_output.append({
            "row_kind": "summary",
            "manifest": label,
            "manifest_rows": lh_rows_by_source[label],
            "content_unique_hashes_checked": len(unique_content_hashes),
            "intersection_unique_hashes": len(intersection),
            "content_sha256": "",
            "claim": "SHA-256 set intersection recomputed from sealed manifests",
            "confidence": "VERIFIED_BYTES_ONLY",
            "provenance": "decode-continuation/content-records.tsv vs exact sealed LocalHistory manifest path",
        })
        for value in intersection:
            lh_output.append({
                "row_kind": "intersection",
                "manifest": label,
                "manifest_rows": lh_rows_by_source[label],
                "content_unique_hashes_checked": len(unique_content_hashes),
                "intersection_unique_hashes": len(intersection),
                "content_sha256": value,
                "claim": "equal bytes only; no path/project/source authorship claim",
                "confidence": "VERIFIED_BYTES_ONLY",
                "provenance": "content-records.tsv sha256 + sealed manifest sha256",
            })
    write_tsv(output_dir / "localhistory-hash-intersections.tsv", lh_columns, lh_output)

    negative_columns = ["finding_id", "status", "claim", "confidence", "provenance"]
    negative_output = [
        {"finding_id": "fbi_stub_file_id", "status": "UNKNOWN", "claim": "FileBasedIndex/stub fileId extraction unsupported; exact serializer evidence absent", "confidence": "UNKNOWN", "provenance": "decode-continuation/SEAL.txt exact_platform_vfs_index_stub_classes=UNKNOWN_ABSENT; peer report compatibility section"},
        {"finding_id": "path_semantics", "status": "FORBIDDEN", "claim": "Decoder paths are INFERRED_PATH candidates only; canonical-path claim is forbidden", "confidence": "INFERRED_PATH_ONLY", "provenance": "decode-continuation/SEAL.txt canonical_path_claim=FORBIDDEN; paths.tsv"},
        {"finding_id": "content_hash_id_serializer", "status": "UNKNOWN", "claim": "Content hash-to-ID exact joins unsupported; 3,102 hashes remain unmapped by serializer", "confidence": "UNKNOWN", "provenance": "decode-continuation/SEAL.txt content_hash_unmapped=3102_UNKNOWN_NO_EXACT_HASH_TO_ID_SERIALIZER"},
        {"finding_id": "localhistory_integrity", "status": "VERIFIED_FAIL", "claim": "LocalHistory remains failed solely for +209 self-manifest accounting; payload/hardlink gates passed; no rewrite", "confidence": "VERIFIED_FAIL", "provenance": "replacement-control/peer1-preservation-report.md and peer1-preservation-seal.txt"},
        {"finding_id": "lifecycle", "status": "UNKNOWN", "claim": "Active/deleted/stale/reused lifecycle and new-vs-existing source semantics are not proven", "confidence": "UNKNOWN", "provenance": "decode-continuation/SEAL.txt records and attributes_projects sections"},
        {"finding_id": "source_bodies", "status": "NOT_CLAIMED", "claim": "No private source bodies or excerpts were read or materialized", "confidence": "VERIFIED_SCOPE", "provenance": "decode-continuation/SEAL.txt source_bodies=not_claimed; payload_materialization=none"},
        {"finding_id": "exact_platform_serializer", "status": "UNKNOWN_ABSENT", "claim": "Exact IDEA platform/VFS/index/stub implementation classes are absent from approved evidence", "confidence": "UNKNOWN", "provenance": "replacement-control/peer1-preservation-report.md compatibility checks"},
        {"finding_id": "persistent_index", "status": "UNKNOWN", "claim": "No regular-file persistent-index variant observed; .persistent was metadata-only placeholder state", "confidence": "UNKNOWN", "provenance": "replacement-control/peer1-preservation-report.md compatibility checks"},
        {"finding_id": "android_domain", "status": "REJECTED", "claim": "Android Studio evidence is a separate/rejected compatibility domain, not an IDEA VFS join", "confidence": "VERIFIED_SCOPE", "provenance": "decode-continuation/SEAL.txt android_studio_2025_3=REJECTED_DIFFERENT_COMPATIBILITY_DOMAIN; peer report"},
        {"finding_id": "huge_gists", "status": "EXCLUDED_OPTIONAL_UNKNOWN", "claim": "Huge-Gists is excluded from gates, totals, and project/source counts", "confidence": "VERIFIED_SCOPE", "provenance": "decode-continuation/SEAL.txt OPTIONAL_UNKNOWN_SIDE_LANE"},
    ]
    write_tsv(output_dir / "negative-findings.tsv", negative_columns, negative_output)

    snapshot_columns = ["path", "role", "bytes", "sha256", "readability", "hash_status", "confidence", "provenance"]
    snapshot_output: list[dict[str, object]] = []
    for path, role in INPUTS:
        stat_result = path.stat()
        snapshot_output.append({
            "path": str(path),
            "role": role,
            "bytes": stat_result.st_size,
            "sha256": sha256_file(path),
            "readability": "PASS" if os.access(path, os.R_OK) else "FAIL",
            "hash_status": "VERIFIED_DIRECT_SHA256",
            "confidence": "VERIFIED_INPUT_METADATA",
            "provenance": "exact approved read-only input path",
        })
    payload_audit = canonical_manifest_audit(JETBRAINS / "canonical-payloads/canonical-payload-manifest.tsv")
    snapshot_output.append({
        "path": str(JETBRAINS / "canonical-payloads/"),
        "role": "canonical-payload-stat-hash-readability-aggregate",
        "bytes": "",
        "sha256": "",
        "readability": "PASS" if payload_audit["missing"] == 0 and payload_audit["unreadable"] == 0 else "FAIL",
        "hash_status": f"manifest_rows={payload_audit['manifest_rows']}; checked={payload_audit['checked']}; missing={payload_audit['missing']}; size_mismatch={payload_audit['size_mismatch']}; hash_mismatch={payload_audit['hash_mismatch']}",
        "confidence": "VERIFIED_MANIFEST_LISTED_METADATA_ONLY",
        "provenance": "canonical-payload-manifest.tsv exact paths; stat/hash/readability only; no excerpts",
    })
    write_tsv(output_dir / "input-snapshot.tsv", snapshot_columns, snapshot_output)

    tsv_artifacts = [
        "correlation-joins.tsv", "filebasedindex-stub-inventory.tsv", "project-correlation-summary.tsv",
        "localhistory-hash-intersections.tsv", "negative-findings.tsv", "input-snapshot.tsv",
    ]
    artifact_lines = []
    for name in tsv_artifacts:
        meta = artifact_meta(output_dir / name)
        artifact_lines.append(f"| `{name}` | {meta['bytes']} | `{meta['sha256']}` | {meta['readability']} |")

    project_lines = []
    for row in project_output:
        project_lines.append(
            f"| {row['project_bucket']} | {row['metadata_path_count']} | {row['join_rows']} | "
            f"{row['valid_content_refs']} | {row['out_of_range_refs']} | {row['existing_count']} | {row['unknown_count']} |"
        )
    lh_total_intersection = len(unique_content_hashes & lh_union)
    report = f"""# FileBasedIndex/stub to VFS/LocalHistory correlation

## Decisions

[VERIFIED] Built a compact, deterministic correlation bundle from the sealed decoder and sealed LocalHistory manifests. Decoder paths remain `INFERRED_PATH`; content boundaries and SHA-256 values are promoted only where the decoder seal marks them verified. FBI/stub fileId extraction remains `UNKNOWN` because exact serializer evidence is absent.

## Reused evidence

The authoritative preservation manifest, preservation and decoder reports/seals, decoder tables, approved artifact manifest, and the four sealed final-recovery manifest views were reused read-only. No upstream table was copied into this bundle and no payload corpus was materialized.

## Peers/provenance

Prior peer `ec1cb1f2-3097-4d66-9ef2-e583deae785a` finished with no artifacts after bounded probes. That is preserved as failed/no-output provenance. Preservation peer evidence remains sealed; decoder continuation is `SEALED_FOR_CORRELATION`.

## Actual runtime settings

Standard-library Python only; local bounded files only; no network, install, IDE, PersistentFS, raw carving, secret decryption, external-volume access, Huge-Gists access, or recovered execution. Product evidence is IntelliJ IDEA 2023.3 build `{BUILD}`; Android Studio is separate/rejected compatibility evidence.

## Exact scopes

Read scope is exactly the approved paths recorded in `input-snapshot.tsv`. Write scope is the correlation directory. Canonical payloads were only stat/hash/readability checked against exact manifest rows; no private body or excerpt was emitted. Huge-Gists is excluded from gates and totals.

## Input/headroom/hash checks

The output is compact TSV/Markdown only. Input SHA-256, byte size, and readability are recorded in `input-snapshot.tsv`; its canonical-payload aggregate records manifest-row, stat, readability, size, and hash mismatch counts. The outer `SEAL.txt` records final root artifact hashes and headroom.

## FBI/stub inventory and compatibility

The inventory is manifest-only and includes FileBasedIndex/stub/shared-index/indices.enum/persistent-index/stamp categories, including zero/unknown summaries. Freshness/version is metadata-only. The exact IDEA platform/VFS/index/stub serializer is absent/unsupported; no fileId join is guessed. Shared-index byte preservation is reused as evidence. No regular-file persistent-index compatibility claim is made. Android Studio evidence remains separate/rejected.

## Correlation method/confidence

Each of the {len(join_rows)} actual rows from `vfs-content-joins.tsv` is retained once. Its record path is joined only by decoder `record_id` to `paths.tsv`; its content is joined only by decoder `content_id` to `content-records.tsv`. The result is {valid_refs} in-range and {out_of_range_refs} out-of-range. LocalHistory intersections are recomputed as SHA-256 set equality against each sealed manifest. Equality proves bytes only, never path, project, source authorship, canonicality, or lifecycle.

## record/path/content/LocalHistory stats

- records data rows observed: `{records_data_rows}` (decoder structural status remains as sealed)
- VFS-content references: `{len(join_rows)}` total; `{valid_refs}` valid/in-range; `{out_of_range_refs}` out-of-range
- content records observed: `{content_rows}`; unique nonzero SHA-256 values checked: `{len(unique_content_hashes)}`
- LocalHistory union unique SHA-256 values: `{len(lh_union)}`; content hash intersection unique values: `{lh_total_intersection}`
- LocalHistory status retained: `VERIFIED_FAIL` solely for `+209` self-manifest accounting; payload/hardlink gates passed; no rewrite

## per-project results

| project | metadata paths | join rows | valid refs | out-of-range | existing-byte matches | unknown |
|---|---:|---:|---:|---:|---:|---:|
{chr(10).join(project_lines)}

Priority rows are always present: spotify, topcoach, ymner, intellilove, and `OTHER_ROOTS`. Metadata candidate counts are not source-recovery counts.

## new vs existing

`existing_count` means only SHA-256 equality to a sealed LocalHistory manifest. `new_count` is `0` because non-equality cannot prove newness; the remainder is `unknown_count`. No project/source authorship or lifecycle claim is made.

## negative findings

See `negative-findings.tsv`. Exact serializers, fileId mappings, hash-to-ID mappings, lifecycle flags, attributes values, canonical paths, source bodies, and private excerpts remain unsupported or explicitly not claimed.

## Huge-Gists optional deviation

Huge-Gists was not accessed and is excluded from all gates, totals, and project/source counts. Its optional side-lane status is `UNKNOWN` only.

## corrections/deviations

The initial replacement peer produced no artifacts after bounded probes; this builder is the replacement producer. It does not repeat broad probes, duplicate decoder tables, rewrite LocalHistory, infer unsupported fileIds, or promote metadata to source evidence.

## blockers/pending permissions

`READY` is forbidden. Pending/blocked items are the absent exact IDEA platform/VFS/index/stub serializer/classes, unproven names/hash/attribute serializers, lifecycle semantics, and the sealed LocalHistory `+209` self-manifest failure. FishAudio remains untouched in the blocked safety state.

## exact artifact paths/sizes/SHA-256/readability

Primary generated artifacts:

| artifact | bytes | SHA-256 | readable |
|---|---:|---|---|
{chr(10).join(artifact_lines)}

`REPORT.md`, `commands.log`, and `SEAL.txt` are sealed at the required correlation root after primary/compare equality is proven; their exact final hashes are listed in the root `SEAL.txt`.

## lane disposition

`SEALED_FOR_VERIFICATION`; overall `READY` is forbidden.

## next verifier gates

Verify primary/compare byte identity and row counts, verify root artifact hashes/readability, verify no writes outside correlation, and independently confirm the 2,943 / 2,942 / 1 and 3,102 gates. Any future stronger join requires exact compatible serializer/class evidence and explicit permission; no source-body or Huge-Gists access is authorized.
"""
    (output_dir / "REPORT.md").write_text(report, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    build(args.output_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
