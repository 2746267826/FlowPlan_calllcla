export const taskRows = [
  {
    id: 'task-1',
    title: 'Plan review',
    status: 'open',
    source: 'local',
    dueAt: '2026-06-08T09:00:00.000Z',
    location: 'Desk',
    description: 'Review the test governance plan',
  },
];

export const scheduleRows = [
  {
    id: 'schedule-1',
    summary: 'Daily sync',
    status: 'CONFIRMED',
    source: 'outlook',
    dtstart: '2026-06-08T10:00:00.000Z',
    dtend: '2026-06-08T10:30:00.000Z',
    location: 'Calendar',
  },
];

export const dashboardPayload = {
  generatedAt: '2026-06-08T08:00:00.000Z',
  pending: {
    conflicts: 3,
    aiDrafts: 2,
    failedPushes: 1,
    failedJobs: 0,
  },
  recentAuditLogs: [
    {
      id: 'audit-1',
      action: 'admin.object.update',
      summary: 'Updated Plan review',
      entityType: 'task',
      entityId: 'task-1',
      occurredAt: '2026-06-08T08:10:00.000Z',
    },
  ],
};

export const monitoringHealthPayload = {
  database: { status: 'ok', message: 'ready' },
  api: { status: 'ok', message: 'responding' },
};

export const syncHealthPayload = {
  devices: [{ deviceId: 'device-1', status: 'online' }],
};
