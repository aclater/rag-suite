"""Tests for rag-suite Postgres schema migrations.

Run against a live Postgres 16 instance with pg_partman and pg_cron installed.
Set DATABASE_URL (or DOCSTORE_URL) to the connection string.

    pytest test_migrations.py -v
"""

import os
import subprocess
import uuid

import pytest

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    pytest.skip("psycopg2 not available", allow_module_level=True)


DB_URL = os.environ.get("DATABASE_URL") or os.environ.get("DOCSTORE_URL", "")
MIGRATIONS_DIR = os.path.dirname(os.path.abspath(__file__))

pytestmark = pytest.mark.skipif(
    not DB_URL,
    reason="DATABASE_URL or DOCSTORE_URL not set",
)


@pytest.fixture(scope="session")
def migrated_db():
    """Run all migrations once per session and yield the connection."""
    subprocess.run(
        ["bash", os.path.join(MIGRATIONS_DIR, "run_migrations.sh")],
        env={**os.environ, "DATABASE_URL": DB_URL},
        check=True,
        capture_output=True,
        text=True,
    )
    conn = psycopg2.connect(DB_URL)
    conn.autocommit = True
    yield conn
    conn.close()


def _run_migrations():
    """Run migrations and return a fresh connection."""
    subprocess.run(
        ["bash", os.path.join(MIGRATIONS_DIR, "run_migrations.sh")],
        env={**os.environ, "DATABASE_URL": DB_URL},
        check=True,
        capture_output=True,
        text=True,
    )
    conn = psycopg2.connect(DB_URL)
    conn.autocommit = True
    return conn


# -- Idempotency --

def test_migrations_are_idempotent():
    """Running migrations twice must succeed without errors."""
    conn1 = _run_migrations()
    conn1.close()
    conn2 = _run_migrations()
    conn2.close()


# -- collections table --

def test_collections_table_exists(migrated_db):
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_name = 'collections')"
    )
    assert cur.fetchone()[0] is True


def test_collections_columns(migrated_db):
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_name = 'collections' ORDER BY ordinal_position"
    )
    cols = {row[0]: row[1] for row in cur.fetchall()}
    assert cols["id"] == "uuid"
    assert cols["name"] == "text"
    assert cols["description"] == "text"
    assert cols["created_at"] == "timestamp with time zone"
    assert cols["updated_at"] == "timestamp with time zone"


def test_collections_unique_name(migrated_db):
    cur = migrated_db.cursor()
    name = f"test-collection-{uuid.uuid4()}"
    cur.execute("INSERT INTO collections (name) VALUES (%s)", (name,))
    with pytest.raises(Exception, match="unique"):
        cur.execute("INSERT INTO collections (name) VALUES (%s)", (name,))


def test_collections_insert_and_read(migrated_db):
    cur = migrated_db.cursor()
    name = f"test-read-{uuid.uuid4()}"
    desc = "test collection for read verification"
    cur.execute(
        "INSERT INTO collections (name, description) VALUES (%s, %s) RETURNING id",
        (name, desc),
    )
    cid = cur.fetchone()[0]
    cur.execute("SELECT name, description FROM collections WHERE id = %s", (cid,))
    row = cur.fetchone()
    assert row[0] == name
    assert row[1] == desc


# -- query_log table --

def test_query_log_table_exists(migrated_db):
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_name = 'query_log')"
    )
    assert cur.fetchone()[0] is True


def test_query_log_columns(migrated_db):
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_name = 'query_log' ORDER BY ordinal_position"
    )
    cols = {row[0]: row[1] for row in cur.fetchall()}
    assert cols["id"] == "bigint"
    assert cols["collection_id"] == "uuid"
    assert cols["query_text"] == "text"
    assert cols["query_hash"] == "text"
    assert cols["grounding"] == "text"
    assert cols["cited_chunks"] == "ARRAY"
    assert cols["cited_count"] == "integer"
    assert cols["total_chunks"] == "integer"
    assert cols["latency_ms"] == "integer"
    assert cols["model"] == "text"
    assert cols["route"] == "text"
    assert cols["created_at"] == "timestamp with time zone"


def test_query_log_grounding_check(migrated_db):
    cur = migrated_db.cursor()
    with pytest.raises(Exception, match="violates check constraint"):
        cur.execute(
            "INSERT INTO query_log (query_text, query_hash, grounding, total_chunks) "
            "VALUES (%s, %s, %s, %s)",
            ("test", "hash", "invalid_grounding", 0),
        )


def test_query_log_grounding_valid_values(migrated_db):
    """All three grounding values must be accepted."""
    cur = migrated_db.cursor()
    for val in ("corpus", "general", "mixed"):
        cur.execute(
            "INSERT INTO query_log (query_text, query_hash, grounding, total_chunks) "
            "VALUES (%s, %s, %s, %s) RETURNING id",
            (f"test-{val}", f"hash-{val}", val, 5),
        )
        row_id = cur.fetchone()[0]
        cur.execute("SELECT grounding FROM query_log WHERE id = %s", (row_id,))
        assert cur.fetchone()[0] == val


def test_query_log_cited_chunks_array(migrated_db):
    cur = migrated_db.cursor()
    chunks = ["doc-1:0", "doc-2:3", "doc-1:1"]
    cur.execute(
        "INSERT INTO query_log (query_text, query_hash, grounding, cited_chunks, total_chunks) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING id",
        ("test array", "hash-array", "corpus", chunks, 10),
    )
    row_id = cur.fetchone()[0]
    cur.execute("SELECT cited_chunks FROM query_log WHERE id = %s", (row_id,))
    assert cur.fetchone()[0] == chunks


def test_query_log_cited_count_generated(migrated_db):
    """cited_count should be auto-derived from cardinality of cited_chunks."""
    cur = migrated_db.cursor()
    chunks = ["doc-a:0", "doc-b:1"]
    cur.execute(
        "INSERT INTO query_log (query_text, query_hash, grounding, cited_chunks, total_chunks) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING id",
        ("test generated", "hash-gen", "corpus", chunks, 20),
    )
    row_id = cur.fetchone()[0]
    cur.execute("SELECT cited_count FROM query_log WHERE id = %s", (row_id,))
    assert cur.fetchone()[0] == 2


def test_query_log_cited_count_null_when_no_chunks(migrated_db):
    cur = migrated_db.cursor()
    cur.execute(
        "INSERT INTO query_log (query_text, query_hash, grounding, total_chunks) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        ("test null", "hash-null", "general", 0),
    )
    row_id = cur.fetchone()[0]
    cur.execute("SELECT cited_count FROM query_log WHERE id = %s", (row_id,))
    assert cur.fetchone()[0] == 0


# -- Partitioning --

def test_query_log_partitioning_exists(migrated_db):
    """query_log should have child partitions in pg_inherits."""
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT EXISTS ("
        "  SELECT 1 FROM pg_inherits i "
        "  JOIN pg_class c ON c.oid = i.inhrelid "
        "  JOIN pg_class p ON p.oid = i.inhparent "
        "  WHERE p.relname = 'query_log'"
        ")"
    )
    assert cur.fetchone()[0] is True


def test_query_log_insert_routes_to_partition(migrated_db):
    """Inserting a row should land it in a child partition, not the parent."""
    cur = migrated_db.cursor()
    cur.execute(
        "INSERT INTO query_log (query_text, query_hash, grounding, total_chunks) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        ("partition test", "hash-part", "corpus", 5),
    )
    row_id = cur.fetchone()[0]
    cur.execute(
        "SELECT c.relname FROM pg_inherits i "
        "JOIN pg_class c ON c.oid = i.inhrelid "
        "JOIN pg_class p ON p.oid = i.inhparent "
        "WHERE p.relname = 'query_log' AND EXISTS ("
        "  SELECT 1 FROM query_log WHERE id = %s AND tableoid = c.oid"
        ")",
        (row_id,),
    )
    assert cur.fetchone() is not None


# -- pg_partman config --

def test_partman_config(migrated_db):
    """partman.part_config should have correct settings for query_log."""
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT partition_interval, premake, retention, retention_keep_table "
        "FROM partman.part_config WHERE parent_table = 'public.query_log'"
    )
    row = cur.fetchone()
    assert row is not None
    assert row[0] == "1 day"
    assert row[1] == 7
    assert row[2] == "30 days"
    assert row[3] is False


# -- pg_cron --

def test_pg_cron_scheduled(migrated_db):
    """cron.job should have the retention job registered."""
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'query_log_retention')"
    )
    assert cur.fetchone()[0] is True


# -- FK behavior --

def test_collection_fk_set_null_on_delete(migrated_db):
    """Deleting a collection should SET NULL on referencing query_log rows."""
    cur = migrated_db.cursor()
    name = f"test-fk-{uuid.uuid4()}"
    cur.execute("INSERT INTO collections (name) VALUES (%s) RETURNING id", (name,))
    cid = cur.fetchone()[0]
    cur.execute(
        "INSERT INTO query_log (query_text, query_hash, grounding, collection_id, total_chunks) "
        "VALUES (%s, %s, %s, %s, %s) RETURNING id",
        ("fk test", "hash-fk", "corpus", cid, 1),
    )
    log_id = cur.fetchone()[0]
    cur.execute("DELETE FROM collections WHERE id = %s", (cid,))
    cur.execute("SELECT collection_id FROM query_log WHERE id = %s", (log_id,))
    assert cur.fetchone()[0] is None


# -- GIN index on cited_chunks --

def test_gin_index_exists(migrated_db):
    cur = migrated_db.cursor()
    cur.execute(
        "SELECT EXISTS ("
        "  SELECT 1 FROM pg_indexes "
        "  WHERE tablename = 'query_log' AND indexname = 'idx_query_log_cited_chunks' "
        "  AND indexdef LIKE '%gin%'"
        ")"
    )
    assert cur.fetchone()[0] is True


# -- Migration ordering --

def test_migration_order():
    """Migration files must exist in numeric order 001, 002, 003."""
    files = sorted(
        f for f in os.listdir(MIGRATIONS_DIR)
        if f.endswith(".sql") and f[0].isdigit()
    )
    assert files == ["001_collections.sql", "002_query_log.sql", "003_partman_config.sql"]
