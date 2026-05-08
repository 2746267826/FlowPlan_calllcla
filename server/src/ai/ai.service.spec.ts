import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { DatabaseService } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { AiService } from './ai.service';
import { cleanDatabase, createTestUser, createTestDevice } from '../common/test/test-utils';
import type { FlowPlanV2RequestContext } from '../common/request-context';

describe('AiService', () => {
  let db: DatabaseService;
  let service: AiService;
  let ctx: FlowPlanV2RequestContext;

  beforeAll(async () => {
    db = new DatabaseService();
    await db.onModuleInit();
    const devices = new DevicesService(db);
    service = new AiService(db, devices);
  });

  afterAll(async () => {
    await db.onModuleDestroy();
  });

  beforeEach(async () => {
    await cleanDatabase(db);
    const user = await createTestUser(db, { id: '00000000-0000-0000-0000-000000000001' });
    const dev = await createTestDevice(db, user.id, { id: '00000000-0000-0000-0000-000000000101' });
    ctx = { userId: user.id, deviceId: dev.id };
  });

  it('returns empty AI settings', async () => {
    const result = await service.settings(ctx);
    expect(Array.isArray(result.providers)).toBe(true);
    expect(result.defaultProvider).toBeNull();
  });

  it('creates and lists an AI provider', async () => {
    const result = await service.upsertProvider('test-provider', {
      providerType: 'openai_compatible',
      displayName: 'Test AI',
      baseUrl: 'https://api.example.com/v1',
      model: 'gpt-test',
      apiKey: 'sk-test-key',
    }, ctx);
    expect(result.ok).toBe(true);

    const settings = await service.settings(ctx);
    expect(settings.providers.length).toBe(1);
    expect(settings.providers[0].providerKey).toBe('test-provider');
  });

  it('returns AI context summary', async () => {
    const result = await service.context(ctx);
    expect(result.scope).toBe('sanitized_server_summary');
    expect(result.context).toBeDefined();
  });

  it('lists tool policies with defaults', async () => {
    const result = await service.toolPolicies(ctx);
    expect(result.policies.length).toBeGreaterThan(0);
    // create_task should be enabled by default
    const createTask = result.policies.find((p: Record<string, unknown>) => p.toolName === 'create_task');
    expect(createTask).toBeDefined();
    expect(createTask.permissionLevel).toBe('draft_then_confirm');
  });

  it('returns empty conversations', async () => {
    const result = await service.conversations({}, ctx);
    expect(result.conversations).toEqual([]);
  });

  it('returns empty tool drafts', async () => {
    const result = await service.toolDrafts({}, ctx);
    expect(result.drafts).toEqual([]);
  });
});
