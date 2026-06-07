import { TEST_NOW } from './determinism';

export const MOCK_AI_CHAT_RESPONSE = {
  id: 'mock-ai-response-001',
  content: 'Create a deterministic test task.',
  createdAt: TEST_NOW.toISOString(),
};

export const MOCK_GRAPH_EVENT = {
  id: 'mock-graph-event-001',
  subject: 'Deterministic calendar event',
  start: { dateTime: '2026-01-02T09:00:00.000Z', timeZone: 'UTC' },
  end: { dateTime: '2026-01-02T10:00:00.000Z', timeZone: 'UTC' },
};

export const MOCK_KOPIA_SNAPSHOT = {
  id: 'mock-kopia-snapshot-001',
  path: 'C:/FlowPlanV2/test-file.txt',
  size: 1024,
  createdAt: TEST_NOW.toISOString(),
};
