import { BadRequestException } from '@nestjs/common';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { FlowPlanV2RequestContext } from '../common/request-context';
import { encrypt, encryptionKey } from '../common/utils';
import { AiService } from './ai.service';

type QueryRows = Array<Record<string, unknown>>;
type QueryResult = { rows: QueryRows };
type QuerySource = 'db' | 'tx';
type QueryHandler = (
  sql: string,
  params: unknown[],
  source: QuerySource,
) => QueryResult | Promise<QueryResult> | undefined;

const context: FlowPlanV2RequestContext = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function result(rows: QueryRows = []): QueryResult {
  return { rows };
}

function compact(sql: string) {
  return sql.replace(/\s+/g, ' ').trim();
}

function hasSql(sql: string, fragment: string) {
  return compact(sql).includes(fragment);
}

function encryptedApiKey(value = 'sk-unit-test') {
  return encrypt(value, encryptionKey());
}

function createHarness(handler: QueryHandler = () => result()) {
  const databaseCalls: Array<{ sql: string; params: unknown[] }> = [];
  const transactionCalls: Array<{ sql: string; params: unknown[] }> = [];

  const query = vi.fn(async (sql: string, params: unknown[] = []) => {
    databaseCalls.push({ sql, params });
    return (await handler(sql, params, 'db')) ?? result();
  });
  const client = {
    query: vi.fn(async (sql: string, params: unknown[] = []) => {
      transactionCalls.push({ sql, params });
      return (await handler(sql, params, 'tx')) ?? result();
    }),
  };
  const database = {
    query,
    transaction: vi.fn(async <T>(callback: (txClient: typeof client) => Promise<T>) =>
      callback(client),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };

  return {
    service: new AiService(database as never, devices as never),
    database,
    client,
    devices,
    databaseCalls,
    transactionCalls,
  };
}

function emptyContextRows(sql: string) {
  if (hasSql(sql, 'COUNT(*)::int AS count')) return result();
  if (hasSql(sql, "object_type IN ('task_item')")) return result();
  if (hasSql(sql, "object_type IN ('calendar_event')")) return result();
  if (hasSql(sql, 'FROM report_documents')) return result();
  if (hasSql(sql, 'FROM file_nodes')) return result();
  if (hasSql(sql, 'FROM activity_daily_stats')) return result();
  return undefined;
}

function providerRow(overrides: Record<string, unknown> = {}) {
  return {
    provider_key: 'openai-main',
    provider_type: 'openai_compatible',
    display_name: 'OpenAI Main',
    base_url: 'https://api.example.test/v1',
    model: 'gpt-test',
    api_key_ciphertext: encryptedApiKey(),
    status: 'enabled',
    temperature: '0.3',
    max_output_tokens: '900',
    options: { response_format: { type: 'json_object' } },
    ...overrides,
  };
}

function mockFetchContent(content: string) {
  const fetchMock = vi.fn(async () => ({
    ok: true,
    status: 200,
    text: vi.fn(async () =>
      JSON.stringify({ choices: [{ message: { content } }] }),
    ),
  }));
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

function privateApi(service: AiService) {
  return service as unknown as {
    callModel(
      provider: Record<string, unknown>,
      apiKey: string,
      messages: Array<{ role: string; content: string }>,
      retries?: number,
    ): Promise<string>;
    callStructuredModel(
      provider: Record<string, unknown>,
      apiKey: string,
      recentMessages: Array<{ role: string; content: string }>,
      serverContext: Record<string, unknown>,
    ): Promise<{
      assistantContent: string;
      drafts: Array<Record<string, unknown>>;
      usage: Record<string, unknown>;
    }>;
    executeDraft(
      client: { query: ReturnType<typeof vi.fn> },
      userId: string,
      deviceId: string,
      action: string,
      payload: Record<string, unknown>,
    ): Promise<Record<string, unknown>>;
    fallbackTaskDraft(userMessage: string): Record<string, unknown>;
    extractTaskTitle(value: string): string;
    inferDueAt(value: string): string | null;
    parseModelJson(content: string): Record<string, unknown>;
    loadToolPolicy(
      userId: string,
      toolName: string,
    ): Promise<Record<string, unknown>>;
    summarize(value: string): string;
  };
}

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  delete process.env.AI_REQUEST_TIMEOUT_MS;
});

describe('AiService provider configuration', () => {
  it('lists providers and marks the first row as the default provider', async () => {
    const providers = [
      { id: 'provider-1', providerKey: 'openai-main', isDefault: true },
      { id: 'provider-2', providerKey: 'local', isDefault: false },
    ];
    const { service, database, devices } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result(providers);
      return result();
    });

    await expect(service.settings(context)).resolves.toEqual({
      providers,
      defaultProvider: providers[0],
    });
    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM ai_provider_configs'),
      [context.userId],
    );
  });

  it('returns a null default provider when no provider configs exist', async () => {
    const { service } = createHarness();

    await expect(service.settings(context)).resolves.toEqual({
      providers: [],
      defaultProvider: null,
    });
  });

  it('upserts a default provider with encrypted api key, normalized url, options, and audit log', async () => {
    const { service, client, transactionCalls } = createHarness((sql, params, source) => {
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_provider_configs')) {
        return result([
          {
            id: 'provider-id',
            providerKey: params[1],
            baseUrl: params[4],
            isDefault: params[11],
          },
        ]);
      }
      return result();
    });

    await expect(
      service.upsertProvider(
        'openai-main',
        {
          providerType: 'openai_compatible',
          displayName: 'Main Provider',
          baseUrl: 'https://api.example.test/v1/',
          model: 'gpt-test',
          apiKey: 'sk-secret-value',
          temperature: '0.45',
          maxOutputTokens: '2048',
          options: { top_p: 0.8 },
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      provider: {
        id: 'provider-id',
        providerKey: 'openai-main',
        baseUrl: 'https://api.example.test/v1',
        isDefault: true,
      },
    });

    expect(client.query).toHaveBeenCalledWith(
      'UPDATE ai_provider_configs SET is_default = false WHERE user_id = $1',
      [context.userId],
    );
    const insertCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_provider_configs'),
    );
    expect(insertCall?.params).toEqual(
      expect.arrayContaining([
        context.userId,
        'openai-main',
        'openai_compatible',
        'Main Provider',
        'https://api.example.test/v1',
        'gpt-test',
        expect.any(String),
        'alue',
        'enabled',
        0.45,
        2048,
        true,
        JSON.stringify({ top_p: 0.8 }),
      ]),
    );
    expect(insertCall?.params[6]).not.toBe('sk-secret-value');
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.provider.upsert']),
        }),
      ]),
    );
  });

  it('upserts a non-default provider without replacing the saved api key when apiKey is blank', async () => {
    const { service, client, transactionCalls } = createHarness((sql, params, source) => {
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_provider_configs')) {
        return result([{ id: 'provider-id', providerKey: params[1] }]);
      }
      return result();
    });

    await service.upsertProvider('local-provider', { isDefault: false, apiKey: '   ' }, context);

    expect(client.query).not.toHaveBeenCalledWith(
      'UPDATE ai_provider_configs SET is_default = false WHERE user_id = $1',
      expect.any(Array),
    );
    const insertCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_provider_configs'),
    );
    expect(insertCall?.params).toEqual(
      expect.arrayContaining([
        context.userId,
        'local-provider',
        'openai_compatible',
        'local-provider',
        'https://api.openai.com/v1',
        '',
        null,
        null,
        'enabled',
        0.2,
        1600,
        false,
        JSON.stringify({}),
      ]),
    );
  });

  it('rejects invalid provider base URLs before opening a transaction', async () => {
    const { service, database } = createHarness();

    await expect(
      service.upsertProvider('bad-provider', { baseUrl: 'not a url' }, context),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.upsertProvider('bad-provider', { baseUrl: 'ftp://example.test' }, context),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('tests a provider with the configured API key and records success', async () => {
    const fetchMock = mockFetchContent('连接正常');
    const provider = providerRow({
      base_url: 'https://api.example.test/v1/',
      temperature: '0.7',
      max_output_tokens: '1200',
      options: { seed: 7 },
    });
    const { service, databaseCalls } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([provider]);
      return result();
    });

    await expect(service.testProvider('openai-main', context)).resolves.toEqual({
      ok: true,
      message: '连接正常',
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://api.example.test/v1/chat/completions',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          authorization: 'Bearer sk-unit-test',
          'content-type': 'application/json',
        }),
      }),
    );
    const body = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(body).toMatchObject({
      model: 'gpt-test',
      temperature: 0.7,
      max_tokens: 1200,
      seed: 7,
    });
    expect(databaseCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('SET last_tested_at = now(), last_error = NULL'),
          params: [context.userId, 'openai-main'],
        }),
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.provider.test']),
        }),
      ]),
    );
  });

  it('rejects provider tests when the provider or api key is missing', async () => {
    const missingProvider = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result();
      return result();
    });
    await expect(
      missingProvider.service.testProvider('missing', context),
    ).rejects.toThrow('AI provider is not configured.');

    const missingKey = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) {
        return result([providerRow({ api_key_ciphertext: null })]);
      }
      return result();
    });
    await expect(missingKey.service.testProvider('openai-main', context)).rejects.toThrow(
      'AI provider apiKey is missing.',
    );
  });

  it('stores the last provider test error before rethrowing model failures', async () => {
    const { service, databaseCalls } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      return result();
    });
    vi.spyOn(service as never, 'callModel').mockRejectedValueOnce(new Error('quota exceeded'));

    await expect(service.testProvider('openai-main', context)).rejects.toThrow(
      'quota exceeded',
    );
    expect(databaseCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('SET last_tested_at = now(), last_error = $3'),
          params: [context.userId, 'openai-main', 'quota exceeded'],
        }),
      ]),
    );

    const stringFailure = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      return result();
    });
    vi.spyOn(stringFailure.service as never, 'callModel').mockRejectedValueOnce(
      'provider offline',
    );

    await expect(stringFailure.service.testProvider('openai-main', context)).rejects.toBe(
      'provider offline',
    );
    expect(stringFailure.databaseCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('SET last_tested_at = now(), last_error = $3'),
          params: [context.userId, 'openai-main', 'provider offline'],
        }),
      ]),
    );
  });
});

describe('AiService context and policy endpoints', () => {
  it('returns a sanitized server context summary', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T04:05:06.000Z'));
    const { service } = createHarness((sql) => {
      if (hasSql(sql, 'COUNT(*)::int AS count')) {
        return result([{ objectType: 'task_item', count: 2 }]);
      }
      if (hasSql(sql, "object_type IN ('task_item')")) {
        return result([
          {
            id: 'task-object-1',
            uid: 'task-uid-1',
            payload: {
              name: 'Task from payload',
              status: 'pending',
              startTime: '2026-06-08T08:00:00Z',
              dueDate: '2026-06-09',
              priority: 'high',
            },
            updatedAt: '2026-06-08T08:00:00Z',
          },
        ]);
      }
      if (hasSql(sql, "object_type IN ('calendar_event')")) {
        return result([
          {
            id: 'event-object-1',
            uid: 'event-uid-1',
            payload: {
              summary: 'Planning meeting',
              start: '2026-06-08T09:00:00Z',
              end: '2026-06-08T10:00:00Z',
              location: 'Room A',
            },
            updatedAt: '2026-06-08T09:00:00Z',
          },
        ]);
      }
      if (hasSql(sql, 'FROM report_documents')) {
        return result([{ reportType: 'daily', title: 'Daily', status: 'ready' }]);
      }
      if (hasSql(sql, 'FROM file_nodes')) {
        return result([{ nodeType: 'file', displayName: 'notes.md' }]);
      }
      if (hasSql(sql, 'FROM activity_daily_stats')) {
        return result([{ dayKey: '2026-06-08', category: 'coding', totalMinutes: 90 }]);
      }
      return result();
    });

    await expect(service.context(context)).resolves.toEqual({
      generatedAt: '2026-06-08T04:05:06.000Z',
      scope: 'sanitized_server_summary',
      context: {
        objectCounts: [{ objectType: 'task_item', count: 2 }],
        recentTasks: [
          {
            id: 'task-object-1',
            uid: 'task-uid-1',
            title: 'Task from payload',
            status: 'pending',
            startAt: '2026-06-08T08:00:00Z',
            endAt: undefined,
            dueAt: '2026-06-09',
            priority: 'high',
            location: undefined,
            updatedAt: '2026-06-08T08:00:00Z',
          },
        ],
        recentSchedules: [
          {
            id: 'event-object-1',
            uid: 'event-uid-1',
            title: 'Planning meeting',
            status: undefined,
            startAt: '2026-06-08T09:00:00Z',
            endAt: '2026-06-08T10:00:00Z',
            dueAt: undefined,
            priority: undefined,
            location: 'Room A',
            updatedAt: '2026-06-08T09:00:00Z',
          },
        ],
        recentReports: [{ reportType: 'daily', title: 'Daily', status: 'ready' }],
        recentFiles: [{ nodeType: 'file', displayName: 'notes.md' }],
        recentActivityStats: [
          { dayKey: '2026-06-08', category: 'coding', totalMinutes: 90 },
        ],
      },
    });
  });

  it('returns empty context collections when all summary queries have no rows', async () => {
    const { service } = createHarness((sql) => emptyContextRows(sql) ?? result());

    await expect(service.context(context)).resolves.toMatchObject({
      scope: 'sanitized_server_summary',
      context: {
        objectCounts: [],
        recentTasks: [],
        recentSchedules: [],
        recentReports: [],
        recentFiles: [],
        recentActivityStats: [],
      },
    });
  });

  it('creates a context snapshot with a sanitized payload and audit entry', async () => {
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      const contextRows = emptyContextRows(sql);
      if (contextRows) return contextRows;
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_context_snapshots')) {
        expect(JSON.parse(String(params[3]))).toMatchObject({
          objectCounts: [],
          recentTasks: [],
        });
        return result([
          {
            id: 'snapshot-1',
            contextType: params[2],
            createdAt: '2026-06-08T00:00:00Z',
          },
        ]);
      }
      return result();
    });

    await expect(
      service.createContextSnapshot(
        {
          conversationId: 'conversation-1',
          contextType: 'activity',
          sensitivePolicy: { redact: ['path'] },
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      snapshot: {
        id: 'snapshot-1',
        contextType: 'activity',
        createdAt: '2026-06-08T00:00:00Z',
      },
    });
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.context.snapshot']),
        }),
      ]),
    );
  });

  it('creates a context snapshot with default type, no conversation, and empty policy', async () => {
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      const contextRows = emptyContextRows(sql);
      if (contextRows) return contextRows;
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_context_snapshots')) {
        expect(params).toEqual([
          context.userId,
          null,
          'mixed',
          JSON.stringify({
            objectCounts: [],
            recentTasks: [],
            recentSchedules: [],
            recentReports: [],
            recentFiles: [],
            recentActivityStats: [],
          }),
          JSON.stringify({}),
        ]);
        return result([{ id: 'snapshot-default', contextType: params[2] }]);
      }
      return result();
    });

    await expect(service.createContextSnapshot({}, context)).resolves.toEqual({
      ok: true,
      snapshot: { id: 'snapshot-default', contextType: 'mixed' },
    });
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.context.snapshot']),
        }),
      ]),
    );
  });

  it('ensures default tool policies before listing configured policies', async () => {
    const policies = [
      {
        id: 'policy-1',
        toolName: 'create_task',
        permissionLevel: 'draft_then_confirm',
      },
    ];
    const { service, databaseCalls } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_tool_policies') && hasSql(sql, 'ORDER BY risk_level')) {
        return result(policies);
      }
      return result();
    });

    await expect(service.toolPolicies(context)).resolves.toEqual({ policies });
    expect(databaseCalls[0].sql).toContain('INSERT INTO ai_tool_policies');
    expect(databaseCalls[1].sql).toContain('UPDATE ai_tool_policies');
    expect(databaseCalls[2].sql).toContain('FROM ai_tool_policies');
  });

  it('upserts a tool policy with normalized defaults, scopes, confirmation flags, and audit', async () => {
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_tool_policies')) {
        return result([
          {
            id: 'policy-1',
            toolName: params[1],
            permissionLevel: params[2],
            riskLevel: params[3],
          },
        ]);
      }
      return result();
    });

    await expect(
      service.upsertToolPolicy(
        'create_task',
        {
          permissionLevel: 'confirm_required',
          riskLevel: 'normal',
          allowedScopes: ['task'],
          deniedScopes: ['calendar'],
          requiresConfirmation: false,
          requiresSecondConfirm: true,
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      policy: {
        id: 'policy-1',
        toolName: 'create_task',
        permissionLevel: 'confirm_required',
        riskLevel: 'normal',
      },
    });

    const upsertCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_tool_policies'),
    );
    expect(upsertCall?.params).toEqual([
      context.userId,
      'create_task',
      'confirm_required',
      'normal',
      JSON.stringify(['task']),
      JSON.stringify(['calendar']),
      false,
      true,
    ]);
  });

  it('upserts a tool policy with default permission values and empty non-array scopes', async () => {
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_tool_policies')) {
        return result([
          {
            id: 'policy-default',
            toolName: params[1],
            permissionLevel: params[2],
            riskLevel: params[3],
          },
        ]);
      }
      return result();
    });

    await expect(
      service.upsertToolPolicy(
        'activity_explanation_suggestion',
        { allowedScopes: 'activity', deniedScopes: null },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      policy: {
        id: 'policy-default',
        toolName: 'activity_explanation_suggestion',
        permissionLevel: 'draft_only',
        riskLevel: 'low',
      },
    });

    const upsertCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_tool_policies'),
    );
    expect(upsertCall?.params).toEqual([
      context.userId,
      'activity_explanation_suggestion',
      'draft_only',
      'low',
      JSON.stringify([]),
      JSON.stringify([]),
      true,
      false,
    ]);
  });

  it('loads restrictive defaults when the current policy row is empty', async () => {
    const { service } = createHarness((sql) => {
      if (hasSql(sql, 'INSERT INTO ai_tool_policies')) return result();
      if (hasSql(sql, 'UPDATE ai_tool_policies')) return result();
      if (hasSql(sql, 'FROM ai_tool_policies') && hasSql(sql, 'LIMIT 1')) {
        return result();
      }
      return result();
    });

    await expect(
      privateApi(service).loadToolPolicy(context.userId, 'create_task'),
    ).resolves.toEqual({
      permissionLevel: 'draft_only',
      riskLevel: 'high',
      allowedScopes: [],
      deniedScopes: [],
      requiresConfirmation: true,
      requiresSecondConfirm: false,
    });
  });
});

describe('AiService conversations and messages', () => {
  it('lists conversations with clamped pagination and status filters', async () => {
    const rows = Array.from({ length: 200 }, (_, index) => ({
      id: `conversation-${index}`,
    }));
    const { service, databaseCalls } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_conversations')) return result(rows);
      return result();
    });

    await expect(
      service.conversations({ status: ' open ', limit: '999', offset: '-5' }, context),
    ).resolves.toEqual({
      limit: 200,
      offset: 0,
      hasMore: true,
      conversations: rows,
    });
    expect(databaseCalls[0].params).toEqual([context.userId, 'open', 200, 0]);
  });

  it('creates a conversation with defaults and records an audit entry', async () => {
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_conversations')) {
        return result([{ id: 'conversation-1', title: params[2], status: 'open' }]);
      }
      return result();
    });

    await expect(service.createConversation({ title: '   ' }, context)).resolves.toEqual({
      ok: true,
      conversation: {
        id: 'conversation-1',
        title: 'AI 对话',
        status: 'open',
      },
    });
    const insertCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_conversations'),
    );
    expect(insertCall?.params).toEqual([
      context.userId,
      'flowplanv2',
      'AI 对话',
      null,
      null,
      JSON.stringify({}),
    ]);
  });

  it('lists messages for a conversation in chronological order', async () => {
    const messages = [
      { id: 'message-1', role: 'user', content: 'hello' },
      { id: 'message-2', role: 'assistant', content: 'hi' },
    ];
    const { service, database } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_messages') && hasSql(sql, 'ORDER BY created_at ASC')) {
        return result(messages);
      }
      return result();
    });

    await expect(service.messages('conversation-1', context)).resolves.toEqual({
      messages,
    });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM ai_messages'), [
      context.userId,
      'conversation-1',
    ]);
  });
});

describe('AiService chat flow', () => {
  it('rejects blank chat messages', async () => {
    const { service, database } = createHarness();

    await expect(service.sendMessage({ content: '   ' }, context)).rejects.toThrow(
      'content is required.',
    );
    expect(database.query).not.toHaveBeenCalled();
  });

  it('creates a new conversation and conservative task draft when no enabled provider is available', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T03:00:00.000Z'));
    const userMessage = '帮我创建一个明天截止的数据库作业任务';
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      const contextRows = emptyContextRows(sql);
      if (contextRows) return contextRows;
      if (hasSql(sql, 'SELECT id::text AS id, provider_key, model FROM ai_conversations')) {
        return result();
      }
      if (source === 'db' && hasSql(sql, 'INSERT INTO ai_conversations')) {
        return result([{ id: 'conversation-1', provider_key: null, model: null }]);
      }
      if (hasSql(sql, 'FROM ai_provider_configs')) return result();
      if (hasSql(sql, 'INSERT INTO ai_messages') && source === 'db') return result();
      if (hasSql(sql, 'FROM ai_messages') && hasSql(sql, 'ORDER BY created_at DESC')) {
        return result([{ role: 'user', content: userMessage }]);
      }
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_operation_drafts')) {
        return result([{ id: 'draft-fallback' }]);
      }
      if (source === 'tx' && hasSql(sql, "VALUES ($1, $2, 'assistant'")) {
        return result([{ id: 'assistant-message-1', createdAt: '2026-06-08T03:00:00Z' }]);
      }
      return result();
    });

    await expect(
      service.sendMessage(
        { conversationId: 'missing-conversation', content: userMessage },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      conversationId: 'conversation-1',
      assistant: {
        role: 'assistant',
        content:
          'AI API 尚未配置或未启用。请先在管理端填写 Provider、Base URL、模型名称和 API Key，然后再发送消息。',
      },
      draftIds: ['draft-fallback'],
    });

    const draftCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_operation_drafts'),
    );
    const requestPayload = JSON.parse(String(draftCall?.params[8]));
    const proposedPayload = JSON.parse(String(draftCall?.params[9]));
    expect(requestPayload).toMatchObject({
      userMessage,
      providerKey: null,
      schema: 'OperationDraft.create_task.v1',
    });
    expect(requestPayload.note).toContain('conservative draft');
    expect(proposedPayload).toMatchObject({
      title: '数据库作业',
      estimatedMinutes: 60,
      taskBookName: '默认任务本',
      priority: 'normal',
      status: 'pending',
      source: 'ai_confirmed',
      createdBy: 'ai_controlled_executor',
      operationDraftSchema: 'OperationDraft.create_task.v1',
    });
    expect(typeof proposedPayload.dueAt).toBe('string');
  });

  it('creates a summarized conversation title and skips the model when the provider has no api key', async () => {
    const longMessage = `Please create a task ${'with many details '.repeat(6)}`;
    const expectedTitle = `${longMessage.replace(/\s+/g, ' ').trim().slice(0, 40)}...`;
    const { service, databaseCalls, transactionCalls } = createHarness(
      (sql, params, source) => {
        const contextRows = emptyContextRows(sql);
        if (contextRows) return contextRows;
        if (source === 'db' && hasSql(sql, 'INSERT INTO ai_conversations')) {
          return result([{ id: 'conversation-from-summary', provider_key: null, model: null }]);
        }
        if (hasSql(sql, 'FROM ai_provider_configs')) {
          return result([providerRow({ api_key_ciphertext: null })]);
        }
        if (source === 'db' && hasSql(sql, 'INSERT INTO ai_messages')) return result();
        if (hasSql(sql, 'FROM ai_messages') && hasSql(sql, 'ORDER BY created_at DESC')) {
          return result([{ role: 'user', content: longMessage }]);
        }
        if (source === 'tx' && hasSql(sql, "VALUES ($1, $2, 'assistant'")) {
          return result([{ id: 'assistant-message-1', createdAt: '2026-06-08T03:00:00Z' }]);
        }
        return result();
      },
    );

    await expect(service.sendMessage({ content: longMessage }, context)).resolves.toEqual({
      ok: true,
      conversationId: 'conversation-from-summary',
      assistant: {
        role: 'assistant',
        content: expect.any(String),
      },
      draftIds: [],
    });

    expect(
      databaseCalls.some((call) =>
        hasSql(call.sql, 'SELECT id::text AS id, provider_key, model FROM ai_conversations'),
      ),
    ).toBe(false);
    const conversationInsert = databaseCalls.find(
      (call) => hasSql(call.sql, 'INSERT INTO ai_conversations') && call.params[2] === expectedTitle,
    );
    expect(conversationInsert?.params).toEqual([
      context.userId,
      'flowplanv2',
      expectedTitle,
      null,
      null,
      JSON.stringify({}),
    ]);
    const conversationUpdate = transactionCalls.find((call) =>
      hasSql(call.sql, 'UPDATE ai_conversations'),
    );
    expect(conversationUpdate?.params[4]).toBe(expectedTitle);
  });

  it('uses an enabled provider response to create valid drafts and audit blocked model actions', async () => {
    const modelContent = JSON.stringify({
      assistant_message: '我会先创建一个待确认草案。',
      operation_drafts: [
        {
          title: 'Create task draft',
          proposed_action: 'create_task',
          proposed_payload: {
            name: 'Finish report',
            dueDate: '2026-06-09T23:59:00.000Z',
            estimated_minutes: '45',
            task_book_name: 'Work',
            description: 'Use the monthly template',
          },
        },
        { proposed_action: 'delete_task', proposed_payload: { title: 'Nope' } },
        { proposed_action: 'answer_only' },
      ],
      usage: { promptTokens: 10 },
    });
    const fetchMock = mockFetchContent(`prefix ${modelContent} suffix`);
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      const contextRows = emptyContextRows(sql);
      if (contextRows) return contextRows;
      if (hasSql(sql, 'SELECT id::text AS id, provider_key, model FROM ai_conversations')) {
        return result([
          {
            id: 'conversation-1',
            provider_key: 'conversation-provider',
            model: 'old-model',
          },
        ]);
      }
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      if (hasSql(sql, 'INSERT INTO ai_messages') && source === 'db') return result();
      if (hasSql(sql, 'FROM ai_messages') && hasSql(sql, 'ORDER BY created_at DESC')) {
        return result([
          { role: 'assistant', content: 'Earlier answer' },
          { role: 'user', content: 'Create a task' },
        ]);
      }
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_operation_drafts')) {
        return result([{ id: 'draft-from-model' }]);
      }
      if (source === 'tx' && hasSql(sql, "VALUES ($1, $2, 'assistant'")) {
        return result([{ id: 'assistant-message-1', createdAt: '2026-06-08T03:00:00Z' }]);
      }
      return result();
    });

    await expect(
      service.sendMessage(
        {
          conversationId: 'conversation-1',
          providerKey: 'openai-main',
          content: 'Please create a task for my report',
        },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      conversationId: 'conversation-1',
      assistant: { role: 'assistant', content: '我会先创建一个待确认草案。' },
      draftIds: ['draft-from-model'],
    });

    const body = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(body.messages).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ role: 'system' }),
        expect.objectContaining({ role: 'assistant', content: 'Earlier answer' }),
        expect.objectContaining({ role: 'user', content: 'Create a task' }),
      ]),
    );
    const draftCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_operation_drafts'),
    );
    expect(JSON.parse(String(draftCall?.params[9]))).toMatchObject({
      title: 'Finish report',
      dueAt: '2026-06-09T23:59:00.000Z',
      estimatedMinutes: 45,
      taskBookName: 'Work',
      notes: 'Use the monthly template',
    });
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.draft.blocked']),
        }),
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.draft.create']),
        }),
      ]),
    );
  });

  it('uses model field fallbacks for assistant content, draft action, title, and payload defaults', async () => {
    const modelContent = JSON.stringify({
      assistantMessage: 'Camel case reply',
      operationDrafts: [
        {},
        {
          proposed_action: 'create_task',
          proposed_payload: {
            title: 'Task only',
          },
        },
      ],
    });
    mockFetchContent(modelContent);
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      const contextRows = emptyContextRows(sql);
      if (contextRows) return contextRows;
      if (hasSql(sql, 'SELECT id::text AS id, provider_key, model FROM ai_conversations')) {
        return result([{ id: 'conversation-1', provider_key: null, model: null }]);
      }
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      if (source === 'db' && hasSql(sql, 'INSERT INTO ai_messages')) return result();
      if (hasSql(sql, 'FROM ai_messages') && hasSql(sql, 'ORDER BY created_at DESC')) {
        return result([{ role: 'user', content: 'Please create a task' }]);
      }
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_operation_drafts')) {
        return result([{ id: 'draft-defaults' }]);
      }
      if (source === 'tx' && hasSql(sql, "VALUES ($1, $2, 'assistant'")) {
        return result([{ id: 'assistant-message-1' }]);
      }
      return result();
    });

    await expect(
      service.sendMessage(
        { conversationId: 'conversation-1', content: 'Please create a task' },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      conversationId: 'conversation-1',
      assistant: { role: 'assistant', content: 'Camel case reply' },
      draftIds: ['draft-defaults'],
    });

    const blockedAudit = transactionCalls.find(
      (call) =>
        hasSql(call.sql, 'INSERT INTO audit_logs') &&
        call.params.includes('ai.draft.blocked'),
    );
    expect(JSON.parse(String(blockedAudit?.params[6]))).toMatchObject({
      action: 'unknown',
    });
    const draftCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO ai_operation_drafts'),
    );
    expect(draftCall?.params[2]).toEqual(expect.any(String));
    expect(String(draftCall?.params[2]).length).toBeGreaterThan(0);
    expect(draftCall?.params[3]).toBeNull();
    expect(JSON.parse(String(draftCall?.params[9]))).toMatchObject({
      title: 'Task only',
      dueAt: null,
      estimatedMinutes: 60,
      priority: 'normal',
      status: 'pending',
    });
  });
});

describe('AiService activity explanation', () => {
  it('rejects explanation requests when no provider is configured', async () => {
    const { service } = createHarness();

    await expect(
      service.explainActivitySegment('segment-1', {}, context),
    ).rejects.toThrow('AI provider is not configured or enabled.');
  });

  it('requires an enabled provider with an API key before explaining activity', async () => {
    const { service } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) {
        return result([providerRow({ status: 'disabled' })]);
      }
      return result();
    });

    await expect(
      service.explainActivitySegment('segment-1', {}, context),
    ).rejects.toThrow('AI provider is not configured or enabled.');
  });

  it('rejects explanation requests for unknown activity segments', async () => {
    const { service } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      if (hasSql(sql, 'FROM activity_segments')) return result();
      return result();
    });

    await expect(
      service.explainActivitySegment('segment-1', {}, context),
    ).rejects.toThrow('activity segment not found.');
  });

  it('creates a safe activity explanation suggestion draft from model JSON', async () => {
    const fetchMock = mockFetchContent(
      JSON.stringify({
        suggested_title: 'Likely design work',
        suggested_summary: 'The window title matches a design task.',
        likely_task_uid: 'task-uid-1',
        confidence: '0.82',
        reasons: ['window', 'app', 'file', 'project', 'duration', 'task', 'recent', 'category', 'extra'],
      }),
    );
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      if (hasSql(sql, 'FROM activity_segments')) {
        return result([
          {
            id: 'segment-1',
            segmentUid: 'segment-uid-1',
            title: 'Figma',
            category: 'design',
            confidence: 0.4,
          },
        ]);
      }
      if (hasSql(sql, "object_type IN ('task_item')")) {
        return result([
          {
            uid: 'task-uid-1',
            payload: { title: 'Design homepage', status: 'pending' },
          },
        ]);
      }
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_operation_drafts')) {
        return result([
          {
            id: 'draft-activity',
            title: params[1],
            status: 'pending_review',
            riskLevel: 'low',
            proposedPayload: JSON.parse(String(params[5])),
          },
        ]);
      }
      return result();
    });

    await expect(
      service.explainActivitySegment('segment-1', { providerKey: 'openai-main' }, context),
    ).resolves.toEqual({
      ok: true,
      suggestion: {
        suggestedTitle: 'Likely design work',
        suggestedSummary: 'The window title matches a design task.',
        likelyTaskUid: 'task-uid-1',
        confidence: 0.82,
        reasons: ['window', 'app', 'file', 'project', 'duration', 'task', 'recent', 'category'],
        model: 'gpt-test',
      },
      draft: {
        id: 'draft-activity',
        title: 'AI activity explanation suggestion',
        status: 'pending_review',
        riskLevel: 'low',
        proposedPayload: {
          suggestedTitle: 'Likely design work',
          suggestedSummary: 'The window title matches a design task.',
          likelyTaskUid: 'task-uid-1',
          confidence: 0.82,
          reasons: ['window', 'app', 'file', 'project', 'duration', 'task', 'recent', 'category'],
          model: 'gpt-test',
        },
      },
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.activity_explain.suggest']),
        }),
      ]),
    );
  });

  it('falls back to the raw model text for suggestion summary and empty reasons', async () => {
    const rawSuggestion = 'Plain activity explanation without JSON.';
    mockFetchContent(rawSuggestion);
    const { service, transactionCalls } = createHarness((sql, params, source) => {
      if (hasSql(sql, 'FROM ai_provider_configs')) return result([providerRow()]);
      if (hasSql(sql, 'FROM activity_segments')) {
        return result([
          {
            id: 'segment-1',
            segmentUid: 'segment-uid-1',
            title: 'Editor',
            category: 'coding',
            confidence: '0.33',
          },
        ]);
      }
      if (hasSql(sql, "object_type IN ('task_item')")) return result();
      if (source === 'tx' && hasSql(sql, 'INSERT INTO ai_operation_drafts')) {
        return result([
          {
            id: 'draft-activity-defaults',
            title: params[1],
            status: 'pending_review',
            riskLevel: 'low',
            proposedPayload: JSON.parse(String(params[5])),
          },
        ]);
      }
      return result();
    });

    await expect(
      service.explainActivitySegment('segment-1', {}, context),
    ).resolves.toMatchObject({
      ok: true,
      suggestion: {
        suggestedSummary: rawSuggestion,
        confidence: 0.33,
        reasons: [],
        model: 'gpt-test',
      },
      draft: {
        id: 'draft-activity-defaults',
        proposedPayload: {
          suggestedSummary: rawSuggestion,
          confidence: 0.33,
          reasons: [],
          model: 'gpt-test',
        },
      },
    });
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          sql: expect.stringContaining('INSERT INTO audit_logs'),
          params: expect.arrayContaining(['ai.activity_explain.suggest']),
        }),
      ]),
    );
  });
});

describe('AiService draft listing, review, and confirmation', () => {
  it('lists operation drafts with pagination metadata', async () => {
    const drafts = [{ id: 'draft-1' }, { id: 'draft-2' }];
    const { service, databaseCalls } = createHarness((sql) => {
      if (hasSql(sql, 'FROM ai_operation_drafts') && hasSql(sql, 'ORDER BY created_at DESC')) {
        return result(drafts);
      }
      return result();
    });

    await expect(
      service.toolDrafts({ status: 'pending_review', limit: '2', offset: '3' }, context),
    ).resolves.toEqual({
      limit: 2,
      offset: 3,
      hasMore: true,
      drafts,
    });
    expect(databaseCalls[0].params).toEqual([context.userId, 'pending_review', 2, 3]);
  });

  it('reviews a draft and reports whether an update happened', async () => {
    const { service } = createHarness((sql, params, source) => {
      if (source === 'tx' && hasSql(sql, 'UPDATE ai_operation_drafts')) {
        return result(
          params[1] === 'draft-1'
            ? [
                {
                  id: 'draft-1',
                  status: params[2],
                  reviewNote: params[3],
                  reviewedAt: '2026-06-08T00:00:00Z',
                },
              ]
            : [],
        );
      }
      return result();
    });

    await expect(
      service.reviewDraft(
        'draft-1',
        { status: 'rejected', reviewNote: 'Not safe enough' },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      draft: {
        id: 'draft-1',
        status: 'rejected',
        reviewNote: 'Not safe enough',
        reviewedAt: '2026-06-08T00:00:00Z',
      },
    });
    await expect(service.reviewDraft('missing', {}, context)).resolves.toEqual({
      ok: false,
      draft: null,
    });
  });

  it.each([
    {
      name: 'missing draft',
      draft: null,
      policy: null,
      message: 'draft not found.',
    },
    {
      name: 'rejected draft',
      draft: { action: 'create_task', status: 'rejected', payload: { title: 'Task' } },
      policy: null,
      message: 'rejected draft cannot be executed.',
    },
    {
      name: 'already reviewed draft',
      draft: { action: 'create_task', status: 'approved', payload: { title: 'Task' } },
      policy: null,
      message: 'draft status approved cannot be executed.',
    },
    {
      name: 'disabled policy',
      draft: { action: 'create_task', status: 'pending_review', payload: { title: 'Task' } },
      policy: { permissionLevel: 'disabled' },
      message: 'this AI tool is disabled by policy.',
    },
    {
      name: 'draft only policy',
      draft: { action: 'create_task', status: 'pending_review', payload: { title: 'Task' } },
      policy: { permissionLevel: 'draft_only' },
      message: 'this AI tool may only create suggestions or drafts.',
    },
    {
      name: 'read only policy',
      draft: { action: 'create_task', status: 'pending_review', payload: { title: 'Task' } },
      policy: { permissionLevel: 'read_only' },
      message: 'this AI tool may only create suggestions or drafts.',
    },
    {
      name: 'unsupported policy',
      draft: { action: 'create_task', status: 'pending_review', payload: { title: 'Task' } },
      policy: { permissionLevel: 'owner_only' },
      message: 'unsupported AI tool permission level: owner_only',
    },
    {
      name: 'non task action',
      draft: {
        action: 'create_calendar_event',
        status: 'pending_review',
        payload: { title: 'Event' },
      },
      policy: { permissionLevel: 'confirm_required' },
      message: 'Only create_task drafts are executable in the MVP AI flow.',
    },
    {
      name: 'missing second confirmation',
      draft: { action: 'create_task', status: 'pending_review', payload: { title: 'Task' } },
      policy: { permissionLevel: 'second_confirm_required', requiresSecondConfirm: true },
      message: 'second confirmation phrase CONFIRM is required.',
    },
    {
      name: 'invalid task payload',
      draft: { action: 'create_task', status: 'pending_review', payload: { title: '   ' } },
      policy: { permissionLevel: 'confirm_required' },
      message: 'create_task draft requires title.',
    },
  ])('rejects confirmation for $name', async ({ draft, policy, message }) => {
    const { service } = createConfirmHarness(draft, policy);

    await expect(service.confirmDraft('draft-1', {}, context)).rejects.toThrow(message);
  });

  it('executes a create_task draft, records sync changes, updates draft status, and logs the tool call', async () => {
    const { service, transactionCalls } = createConfirmHarness(
      {
        action: 'create_task',
        status: 'pending_review',
        payload: {
          title: ' Ship proposal ',
          due_at: '2026-06-09T23:59:00Z',
          estimatedMinutes: '95',
          priority: 'high',
        },
      },
      { permissionLevel: 'draft_then_confirm', requiresSecondConfirm: false },
    );

    await expect(
      service.confirmDraft('draft-1', { reviewNote: 'Approved' }, context),
    ).resolves.toEqual({
      ok: true,
      draft: {
        id: 'draft-1',
        status: 'approved',
        executionStatus: 'executed',
        executionResult: {
          objectType: 'task_item',
          objectId: 'object-1',
          uid: expect.stringMatching(/^task_item-ai-/),
        },
      },
    });

    const syncObjectCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO sync_objects'),
    );
    expect(syncObjectCall?.params[1]).toBe('task_item');
    expect(String(syncObjectCall?.params[2])).toMatch(/^task_item-ai-/);
    expect(JSON.parse(String(syncObjectCall?.params[3]))).toMatchObject({
      title: 'Ship proposal',
      dueAt: '2026-06-09T23:59:00Z',
      estimatedMinutes: 95,
      taskBookName: '默认任务本',
      priority: 'high',
      status: 'pending',
      source: 'ai_confirmed',
      createdBy: 'ai_controlled_executor',
    });
    expect(transactionCalls).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ sql: expect.stringContaining('INSERT INTO sync_changes') }),
        expect.objectContaining({
          sql: expect.stringContaining('UPDATE ai_operation_drafts'),
          params: expect.arrayContaining([
            context.userId,
            'draft-1',
            'Approved',
            'executed',
          ]),
        }),
        expect.objectContaining({ sql: expect.stringContaining('INSERT INTO ai_tool_calls') }),
      ]),
    );
  });

  it('executes a create_task draft with default review note and payload defaults', async () => {
    const { service, transactionCalls } = createConfirmHarness(
      {
        action: 'create_task',
        status: 'pending_review',
        payload: {
          title: ' Defaulted task ',
        },
      },
      { permissionLevel: 'confirm_required' },
    );

    await expect(service.confirmDraft('draft-1', {}, context)).resolves.toMatchObject({
      ok: true,
      draft: {
        id: 'draft-1',
        status: 'approved',
        executionStatus: 'executed',
      },
    });

    const syncObjectCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'INSERT INTO sync_objects'),
    );
    const payload = JSON.parse(String(syncObjectCall?.params[3]));
    expect(payload).toMatchObject({
      title: 'Defaulted task',
      estimatedMinutes: 60,
      taskBookName: expect.any(String),
      priority: 'normal',
      status: 'pending',
      source: 'ai_confirmed',
      createdBy: 'ai_controlled_executor',
    });
    expect(payload.dueAt).toBeNull();
    const updateCall = transactionCalls.find((call) =>
      hasSql(call.sql, 'UPDATE ai_operation_drafts'),
    );
    expect(updateCall?.params[2]).toEqual(expect.any(String));
    expect(String(updateCall?.params[2]).length).toBeGreaterThan(0);
  });
});

describe('AiService model caller and internal draft executors', () => {
  it('falls back to raw structured model content and empty drafts when JSON fields are absent', async () => {
    const rawContent = JSON.stringify({ note: 'no assistant fields', usage: null });
    mockFetchContent(rawContent);
    const { service } = createHarness();

    await expect(
      privateApi(service).callStructuredModel(
        providerRow(),
        'sk-unit-test',
        [{ role: 'user', content: 'hello' }],
        { objectCounts: [] },
      ),
    ).resolves.toEqual({
      assistantContent: rawContent,
      drafts: [],
      usage: {},
    });
  });

  it('retries transient model failures and returns the later successful response', async () => {
    vi.useFakeTimers();
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: false,
        status: 500,
        text: vi.fn(async () => 'temporary outage'),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        text: vi.fn(async () =>
          JSON.stringify({ choices: [{ message: { content: 'Recovered' } }] }),
        ),
      });
    vi.stubGlobal('fetch', fetchMock);
    const { service } = createHarness();

    const promise = privateApi(service).callModel(
      providerRow(),
      'sk-unit-test',
      [{ role: 'user', content: 'hello' }],
      2,
    );
    await vi.advanceTimersByTimeAsync(1000);

    await expect(promise).resolves.toBe('Recovered');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('surfaces model caller validation, HTTP, timeout, and empty-content errors without network access', async () => {
    const { service } = createHarness();
    await expect(
      privateApi(service).callModel(
        providerRow({ provider_type: 'anthropic' }),
        'sk-unit-test',
        [],
        1,
      ),
    ).rejects.toThrow('Unsupported AI provider type: anthropic');

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: false,
        status: 400,
        text: vi.fn(async () => 'bad request body'),
      })),
    );
    await expect(
      privateApi(service).callModel(providerRow(), 'sk-unit-test', [], 1),
    ).rejects.toThrow('AI API 400: bad request body');

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () => JSON.stringify({ choices: [{ message: { content: '' } }] })),
      })),
    );
    await expect(
      privateApi(service).callModel(providerRow(), 'sk-unit-test', [], 1),
    ).rejects.toThrow('AI API response did not contain message content.');

    process.env.AI_REQUEST_TIMEOUT_MS = '5';
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => {
        throw new DOMException('aborted', 'AbortError');
      }),
    );
    await expect(
      privateApi(service).callModel(providerRow(), 'sk-unit-test', [], 1),
    ).rejects.toThrow('AI API request timed out after 5ms');
  });

  it('handles empty raw bodies, missing choices, and non-Error retry failures', async () => {
    const { service } = createHarness();

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () => ''),
      })),
    );
    await expect(
      privateApi(service).callModel(providerRow(), 'sk-unit-test', [], 1),
    ).rejects.toThrow('AI API response did not contain message content.');

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () => JSON.stringify({})),
      })),
    );
    await expect(
      privateApi(service).callModel(providerRow(), 'sk-unit-test', [], 1),
    ).rejects.toThrow('AI API response did not contain message content.');

    vi.useFakeTimers();
    const fetchMock = vi
      .fn()
      .mockRejectedValueOnce('temporary string failure')
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        text: vi.fn(async () =>
          JSON.stringify({ choices: [{ message: { content: 'Recovered after string error' } }] }),
        ),
      });
    vi.stubGlobal('fetch', fetchMock);

    const promise = privateApi(service).callModel(
      providerRow(),
      'sk-unit-test',
      [{ role: 'user', content: 'hello' }],
      2,
    );
    await vi.advanceTimersByTimeAsync(1000);

    await expect(promise).resolves.toBe('Recovered after string error');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('returns the generic retry failure when no model attempts are available', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const { service } = createHarness();

    await expect(
      privateApi(service).callModel(providerRow(), 'sk-unit-test', [], 0),
    ).rejects.toThrow('AI API request failed after retries');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('aborts pending model requests when the configured timeout elapses', async () => {
    vi.useFakeTimers();
    process.env.AI_REQUEST_TIMEOUT_MS = '5';
    const fetchMock = vi.fn(
      async (_url: string, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener('abort', () => {
            reject(new DOMException('aborted', 'AbortError'));
          });
        }),
    );
    vi.stubGlobal('fetch', fetchMock);
    const { service } = createHarness();

    const promise = privateApi(service).callModel(
      providerRow(),
      'sk-unit-test',
      [{ role: 'user', content: 'wait' }],
      1,
    );
    const assertion = expect(promise).rejects.toThrow('AI API request timed out after 5ms');
    await vi.advanceTimersByTimeAsync(5);

    await assertion;
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('falls back for task draft parsing and malformed model JSON content', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T00:00:00.000Z'));
    const { service } = createHarness();
    const api = privateApi(service);

    expect(api.extractTaskTitle('Ship coverage task')).toBe('Ship coverage task');
    expect(api.extractTaskTitle('')).toEqual(expect.any(String));
    expect(api.extractTaskTitle('')).not.toHaveLength(0);
    expect(api.inferDueAt('plain request without a date')).toBeNull();
    const relativeTokens = [
      ...String(api.inferDueAt).matchAll(/\/([^/]+)\/\.test\(value\)/g),
    ].map((match) => match[1]);
    const tomorrowToken = relativeTokens[0];
    const laterToken = relativeTokens[1];
    const todayToken = relativeTokens[2];
    expect(api.inferDueAt(tomorrowToken as string)).toContain('2026-06-09');
    expect(laterToken).toEqual(expect.any(String));
    expect(api.inferDueAt(laterToken as string)).toContain('2026-06-10');
    expect(api.inferDueAt(todayToken as string)).toContain('2026-06-08');
    const fallbackDraft = api.fallbackTaskDraft('Create a task to sort the inbox');
    const fallbackPayload = fallbackDraft.payload as Record<string, unknown>;
    expect(fallbackPayload.dueAt).toBeNull();
    expect(String(fallbackDraft.summary)).toContain(String(fallbackPayload.title));
    expect(String(fallbackDraft.summary)).not.toContain('null');
    expect(api.parseModelJson('plain assistant response')).toEqual({
      assistant_message: 'plain assistant response',
      operation_drafts: [],
    });
    expect(api.parseModelJson('prefix {not valid json} suffix')).toEqual({
      assistant_message: 'prefix {not valid json} suffix',
      operation_drafts: [],
    });
    expect(api.summarize('  Short   title  ')).toBe('Short title');
    expect(api.summarize('x'.repeat(41))).toBe(`${'x'.repeat(40)}...`);
  });

  it('covers non-chat draft executor outcomes that are guarded from MVP confirmation', async () => {
    const txClient = {
      query: vi.fn(async (sql: string) => {
        if (hasSql(sql, 'INSERT INTO sync_objects')) {
          return result([{ id: 'calendar-object-1', serverVersion: 11 }]);
        }
        if (hasSql(sql, 'INSERT INTO actual_activity_logs')) {
          return result([{ id: 'actual-1' }]);
        }
        return result();
      }),
    };
    const { service } = createHarness();

    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'create_calendar_event',
        { title: 'Planning' },
      ),
    ).resolves.toEqual({
      status: 'needs_more_information',
      result: { reason: 'create_calendar_event requires startAt and endAt.' },
    });
    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'create_calendar_event',
        {
          summary: 'Planning',
          startAt: '2026-06-08T09:00:00Z',
          endAt: '2026-06-08T10:00:00Z',
        },
      ),
    ).resolves.toMatchObject({
      status: 'executed',
      result: { objectType: 'calendar_event', objectId: 'calendar-object-1' },
    });
    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'create_calendar_event',
        {
          startAt: '2026-06-08T11:00:00Z',
          endAt: '2026-06-08T12:00:00Z',
        },
      ),
    ).resolves.toMatchObject({
      status: 'executed',
      result: { objectType: 'calendar_event', objectId: 'calendar-object-1' },
    });
    const calendarPayloads = txClient.query.mock.calls
      .filter(([sql]) => hasSql(String(sql), 'INSERT INTO sync_objects'))
      .map(([, params]) => JSON.parse(String((params as unknown[])[3])));
    const defaultCalendarPayload = calendarPayloads[calendarPayloads.length - 1];
    expect(defaultCalendarPayload).toMatchObject({
      startAt: '2026-06-08T11:00:00Z',
      endAt: '2026-06-08T12:00:00Z',
      title: expect.any(String),
    });
    expect(String(defaultCalendarPayload.title)).not.toHaveLength(0);
    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'create_actual_record',
        { title: 'Focus block' },
      ),
    ).resolves.toEqual({
      status: 'needs_more_information',
      result: { reason: 'create_actual_record requires startAt and endAt.' },
    });
    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'create_actual_record',
        {
          title: 'Focus block',
          start_at: '2026-06-08T09:00:00Z',
          end_at: '2026-06-08T10:00:00Z',
        },
      ),
    ).resolves.toEqual({ status: 'executed', result: { actualId: 'actual-1' } });
    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'create_actual_record',
        {
          startAt: '2026-06-08T11:00:00Z',
          endAt: '2026-06-08T12:00:00Z',
        },
      ),
    ).resolves.toEqual({ status: 'executed', result: { actualId: 'actual-1' } });
    const actualInsertCalls = txClient.query.mock.calls.filter(([sql]) =>
      hasSql(String(sql), 'INSERT INTO actual_activity_logs'),
    );
    const actualInsertCall = actualInsertCalls[actualInsertCalls.length - 1];
    const actualInsertParams = actualInsertCall?.[1] as unknown[];
    expect(actualInsertParams?.[2]).toEqual(expect.any(String));
    expect(String(actualInsertParams?.[2])).not.toHaveLength(0);
    await expect(
      privateApi(service).executeDraft(
        txClient,
        context.userId,
        context.deviceId,
        'reschedule_plan',
        {},
      ),
    ).resolves.toMatchObject({
      status: 'queued_for_manual_executor',
      result: { action: 'reschedule_plan' },
    });
  });
});

function createConfirmHarness(
  draft:
    | null
    | {
        action: string;
        status: string;
        payload: Record<string, unknown>;
      },
  policy: null | Record<string, unknown>,
) {
  return createHarness((sql, params, source) => {
    if (source === 'tx' && hasSql(sql, 'SELECT id::text AS id, proposed_action AS action')) {
      return result(
        draft
          ? [
              {
                id: 'draft-1',
                action: draft.action,
                target_type: 'task',
                target_id: null,
                risk_level: 'low',
                payload: draft.payload,
                status: draft.status,
              },
            ]
          : [],
      );
    }
    if (source === 'db' && hasSql(sql, 'INSERT INTO ai_tool_policies')) return result();
    if (source === 'db' && hasSql(sql, 'UPDATE ai_tool_policies')) return result();
    if (source === 'db' && hasSql(sql, 'FROM ai_tool_policies')) {
      return result(
        policy
          ? [
              {
                permissionLevel: policy.permissionLevel,
                riskLevel: policy.riskLevel ?? 'low',
                allowedScopes: policy.allowedScopes ?? ['task'],
                deniedScopes: policy.deniedScopes ?? [],
                requiresConfirmation: policy.requiresConfirmation ?? true,
                requiresSecondConfirm: policy.requiresSecondConfirm ?? false,
              },
            ]
          : [],
      );
    }
    if (source === 'tx' && hasSql(sql, 'INSERT INTO sync_objects')) {
      return result([{ id: 'object-1', serverVersion: 5 }]);
    }
    if (source === 'tx' && hasSql(sql, 'UPDATE ai_operation_drafts')) {
      return result([
        {
          id: params[1],
          status: 'approved',
          executionStatus: params[3],
          executionResult: JSON.parse(String(params[4])),
        },
      ]);
    }
    return result();
  });
}
