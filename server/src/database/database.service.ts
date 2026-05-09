import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Pool, QueryResult, QueryResultRow } from 'pg';
import { errorMessage } from '../common/utils';

@Injectable()
export class DatabaseService implements OnModuleDestroy, OnModuleInit {
  private readonly pool: Pool;

  constructor() {
    const connectionString =
      process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error(
        [
          'FLOWPLANV2_DATABASE_URL or DATABASE_URL is required for FlowPlanV2 Server startup.',
          'Create .env in the server directory or set FLOWPLANV2_DATABASE_URL before starting the server.',
          'Expected format: postgres://USER:PASSWORD@HOST:5432/DATABASE',
          'Then run: cd server; npm run db:schema; npm run dev',
        ].join(' '),
      );
    }

    const poolMax = Number(process.env.DATABASE_POOL_MAX ?? 10);
    const idleTimeout = Number(process.env.DATABASE_POOL_IDLE_TIMEOUT ?? 30000);

    this.pool = new Pool({
      connectionString,
      max: poolMax,
      idleTimeoutMillis: idleTimeout,
      connectionTimeoutMillis: Number(process.env.DATABASE_POOL_CONNECTION_TIMEOUT ?? 10000),
    });

    // Pool event monitoring (D7)
    this.pool.on('connect', () => {
      // client connected — high-frequency, debug only
    });
    this.pool.on('error', (err: Error) => {
      console.error('[DatabaseService] Pool error:', err.message);
    });
  }

  /** Get current pool statistics (D7). */
  poolStats(): { totalCount: number; idleCount: number; waitingCount: number; max: number } {
    return {
      totalCount: this.pool.totalCount,
      idleCount: this.pool.idleCount,
      waitingCount: this.pool.waitingCount,
      max: Number(process.env.DATABASE_POOL_MAX ?? 10),
    };
  }

  async onModuleInit() {
    try {
      await this.pool.query('SELECT 1');
    } catch (error) {
      throw new Error(
        [
          'FlowPlanV2 could not connect to PostgreSQL with FLOWPLANV2_DATABASE_URL/DATABASE_URL.',
          errorMessage(error),
          'Check that PostgreSQL is running, the database exists, credentials are correct, and the schema has been applied with: cd server; npm run db:schema',
        ].join(' '),
      );
    }
  }

  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    values: unknown[] = [],
  ): Promise<QueryResult<T>> {
    const threshold = Number(process.env.SLOW_QUERY_THRESHOLD_MS ?? 1000);
    if (threshold > 0) {
      const start = Date.now();
      return this.pool.query<T>(text, values).then((result) => {
        const ms = Date.now() - start;
        if (ms >= threshold) {
          console.warn(`[SlowQuery] ${ms}ms: ${text.slice(0, 200).replace(/\s+/g, ' ')}`);
        }
        return result;
      });
    }
    return this.pool.query<T>(text, values);
  }

  async transaction<T>(
    callback: (client: TransactionClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}

export interface TransactionClient {
  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: unknown[],
  ): Promise<QueryResult<T>>;
}
