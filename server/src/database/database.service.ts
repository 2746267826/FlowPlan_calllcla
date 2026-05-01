import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Pool, QueryResult, QueryResultRow } from 'pg';

@Injectable()
export class DatabaseService implements OnModuleDestroy, OnModuleInit {
  private readonly pool: Pool;

  constructor() {
    const connectionString = process.env.DATABASE_URL;
    if (!connectionString) {
      throw new Error(
        [
          'DATABASE_URL is required for FlowPlan Server startup.',
          'Create flowplan.local.env in the workspace root or set $env:DATABASE_URL before starting the server.',
          'Expected format: postgres://USER:PASSWORD@HOST:5432/DATABASE',
          'Then run: cd server; npm run db:schema; npm run dev',
        ].join(' '),
      );
    }

    this.pool = new Pool({
      connectionString,
      max: Number(process.env.DATABASE_POOL_MAX ?? 10),
    });
  }

  async onModuleInit() {
    try {
      await this.pool.query('SELECT 1');
    } catch (error) {
      throw new Error(
        [
          'FlowPlan could not connect to PostgreSQL with DATABASE_URL.',
          this.errorMessage(error),
          'Check that PostgreSQL is running, the database exists, credentials are correct, and the schema has been applied with: cd server; npm run db:schema',
        ].join(' '),
      );
    }
  }

  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    values: unknown[] = [],
  ): Promise<QueryResult<T>> {
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

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}

export interface TransactionClient {
  query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    values?: unknown[],
  ): Promise<QueryResult<T>>;
}
