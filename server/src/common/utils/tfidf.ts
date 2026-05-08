/**
 * Minimal TF-IDF implementation for task-activity matching.
 *
 * Zero dependencies — operates on plain strings.
 *
 * Usage:
 *   const matcher = new TfidfMatcher();
 *   tasks.forEach(t => matcher.addDocument(t.id, t.title + ' ' + t.description));
 *   const best = matcher.bestMatch('VS Code: flowplan - editing server.ts');
 *   // → { id: 'task-1', score: 0.82 }
 */

export interface TfidfDoc {
  id: string;
  terms: Map<string, number>;
}

export class TfidfMatcher {
  private docs: TfidfDoc[] = [];
  private df = new Map<string, number>();  // document frequency
  private totalDocs = 0;

  /** Index a document (task) by its text content. */
  addDocument(id: string, text: string): void {
    const terms = this.tokenize(text);
    if (terms.size === 0) return;
    this.docs.push({ id, terms });
    this.totalDocs += 1;
    for (const term of terms.keys()) {
      this.df.set(term, (this.df.get(term) ?? 0) + 1);
    }
  }

  /**
   * Find the best-matching document for a query string.
   * Returns { id, score } or null if no documents are indexed.
   */
  bestMatch(query: string): { id: string; score: number } | null {
    if (this.docs.length === 0) return null;
    const queryTerms = this.tokenize(query);
    if (queryTerms.size === 0) return null;

    const queryVec = this.tfidfVector(queryTerms);

    let best: { id: string; score: number } | null = null;
    for (const doc of this.docs) {
      const docVec = this.tfidfVector(doc.terms);
      const score = this.cosineSimilarity(queryVec, docVec);
      if (best === null || score > best.score) {
        best = { id: doc.id, score };
      }
    }
    return best;
  }

  /**
   * Return all matches above a threshold.
   */
  matches(query: string, threshold = 0.01): Array<{ id: string; score: number }> {
    if (this.docs.length === 0) return [];
    const queryTerms = this.tokenize(query);
    if (queryTerms.size === 0) return [];

    const queryVec = this.tfidfVector(queryTerms);
    const results: Array<{ id: string; score: number }> = [];
    for (const doc of this.docs) {
      const score = this.cosineSimilarity(queryVec, this.tfidfVector(doc.terms));
      if (score >= threshold) {
        results.push({ id: doc.id, score });
      }
    }
    return results.sort((a, b) => b.score - a.score);
  }

  /** Clear all indexed documents. */
  reset(): void {
    this.docs = [];
    this.df.clear();
    this.totalDocs = 0;
  }

  /** Number of indexed documents. */
  get size(): number {
    return this.totalDocs;
  }

  // ---- internal ----

  private tokenize(text: string): Map<string, number> {
    const map = new Map<string, number>();
    // Split on non-word boundaries; keep Chinese chars (CJK) as single tokens
    const words = text
      .toLowerCase()
      .split(/[\s_/\\\-:，。,.!?;:()\[\]{}"']+/)
      .filter((w) => w.length >= 2);

    // Also extract CJK bigrams for Chinese text
    const cjkOnly = text.replace(/[^一-鿿]/g, '');
    for (let i = 0; i < cjkOnly.length - 1; i += 1) {
      words.push(cjkOnly.slice(i, i + 2));
    }

    for (const word of words) {
      map.set(word, (map.get(word) ?? 0) + 1);
    }
    return map;
  }

  private tfidfVector(terms: Map<string, number>): Map<string, number> {
    const vec = new Map<string, number>();
    let norm = 0;
    for (const [term, tf] of terms) {
      const df = this.df.get(term) ?? 0;
      if (df === 0) continue;
      const idf = Math.log((this.totalDocs + 1) / (df + 1)) + 1;
      const tfidf = tf * idf;
      vec.set(term, tfidf);
      norm += tfidf * tfidf;
    }
    // L2 normalize
    const invNorm = norm > 0 ? 1 / Math.sqrt(norm) : 1;
    for (const [term, val] of vec) {
      vec.set(term, val * invNorm);
    }
    return vec;
  }

  private cosineSimilarity(a: Map<string, number>, b: Map<string, number>): number {
    // Both vectors are already L2-normalized, so dot product = cosine similarity
    let dot = 0;
    for (const [term, aVal] of a) {
      const bVal = b.get(term);
      if (bVal !== undefined) dot += aVal * bVal;
    }
    return dot;
  }
}
