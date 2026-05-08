-- ============================================================================
-- Migration 003: pgvector extension (optional)
--
-- Provides vector similarity search for task-activity matching.
-- If pgvector is not installed on the PostgreSQL server, this migration
-- is safely skipped (CREATE EXTENSION IF NOT EXISTS).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS vector;

-- Embedding storage for task descriptions and activity segments.
-- 384 dimensions matches all-MiniLM-L6-v2 (lightweight local model)
-- or text-embedding-3-small (OpenAI).
CREATE TABLE IF NOT EXISTS task_embeddings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_id text NOT NULL,
  embedding vector(384),
  model text NOT NULL DEFAULT 'none',
  source_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, task_id)
);

CREATE INDEX IF NOT EXISTS task_embeddings_user_idx
  ON task_embeddings(user_id, task_id);

-- Index for approximate nearest neighbor search (IVFFlat)
-- Only created if the vector extension is available and the table has data.
-- Requires: SET ivfflat.probes = <value>; before querying.
-- CREATE INDEX IF NOT EXISTS task_embeddings_ivfflat_idx
--   ON task_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Simple cosine similarity search function.
-- Returns the top N matching tasks for a given query embedding.
CREATE OR REPLACE FUNCTION match_tasks(
  query_embedding vector(384),
  match_user_id uuid,
  match_threshold float DEFAULT 0.5,
  match_count integer DEFAULT 10
)
RETURNS TABLE(
  task_id text,
  similarity float
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.task_id,
    (1 - (e.embedding <=> query_embedding))::float AS similarity
  FROM task_embeddings e
  WHERE e.user_id = match_user_id
    AND (1 - (e.embedding <=> query_embedding)) > match_threshold
  ORDER BY e.embedding <=> query_embedding
  LIMIT match_count;
EXCEPTION
  WHEN undefined_function THEN
    -- pgvector not installed — return empty
    RETURN;
END;
$$ LANGUAGE plpgsql;
