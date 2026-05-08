import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../database/database.service';

/**
 * Optional pgvector-backed similarity search for task matching.
 *
 * When pgvector is installed and task embeddings exist, `matchTasks()`
 * returns cosine-similarity-ranked task IDs.  Falls back gracefully when
 * the extension is not available.
 */
@Injectable()
export class VectorService {
  constructor(private readonly db: DatabaseService) {}

  /**
   * Search for tasks similar to a query embedding vector.
   * Returns empty array if pgvector is not installed or no embeddings exist.
   */
  async matchTasks(
    userId: string,
    embedding: number[],
    threshold = 0.5,
    limit = 10,
  ): Promise<Array<{ taskId: string; similarity: number }>> {
    try {
      const result = await this.db.query<{
        task_id: string;
        similarity: number;
      }>(
        `SELECT * FROM match_tasks($1::vector, $2::uuid, $3, $4)`,
        [JSON.stringify(embedding), userId, threshold, limit],
      );
      return result.rows.map((row) => ({
        taskId: row.task_id,
        similarity: Number(row.similarity),
      }));
    } catch {
      // pgvector not available — graceful fallback
      return [];
    }
  }

  /**
   * Store (or update) an embedding for a task.
   */
  async upsertEmbedding(
    userId: string,
    taskId: string,
    embedding: number[],
    model: string,
    sourceText: string,
  ): Promise<void> {
    try {
      await this.db.query(
        `
        INSERT INTO task_embeddings (user_id, task_id, embedding, model, source_text)
        VALUES ($1, $2, $3::vector, $4, $5)
        ON CONFLICT (user_id, task_id) DO UPDATE SET
          embedding = EXCLUDED.embedding,
          model = EXCLUDED.model,
          source_text = EXCLUDED.source_text,
          updated_at = now()
        `,
        [userId, taskId, JSON.stringify(embedding), model, sourceText],
      );
    } catch {
      // pgvector not available — ignore
    }
  }

  /**
   * Generate a simple text embedding using character n-gram hashing.
   * This is a fallback when no external embedding model is available.
   * Not as accurate as real embeddings, but works without any API calls.
   */
  static simpleEmbedding(text: string, dimensions = 384): number[] {
    const vec = new Array<number>(dimensions).fill(0);
    // Character n-grams (2-4 chars) mapped to vector dimensions via hash
    for (let i = 0; i < text.length - 1; i++) {
      for (let n = 2; n <= 4 && i + n <= text.length; n++) {
        const ngram = text.slice(i, i + n);
        let hash = 0;
        for (let j = 0; j < ngram.length; j++) {
          hash = ((hash << 5) - hash + ngram.charCodeAt(j)) | 0;
        }
        const idx = Math.abs(hash) % dimensions;
        vec[idx] += 1;
      }
    }
    // L2 normalize
    const norm = Math.sqrt(vec.reduce((sum, v) => sum + v * v, 0)) || 1;
    for (let i = 0; i < dimensions; i++) {
      vec[i] /= norm;
    }
    return vec;
  }
}
