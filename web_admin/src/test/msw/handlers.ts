import { http, HttpResponse } from 'msw';
import {
  dashboardPayload,
  monitoringHealthPayload,
  scheduleRows,
  syncHealthPayload,
  taskRows,
} from '../fixtures/adminData';

export const adminApiHandlers = [
  http.post('*/api/auth/login', () =>
    HttpResponse.json({
      accessToken: 'test-token',
      refreshToken: 'refresh-token',
      user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
    }),
  ),
  http.post('*/api/auth/refresh', () =>
    HttpResponse.json({
      accessToken: 'test-token',
      refreshToken: 'refresh-token',
      user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
    }),
  ),
  http.get('*/api/health', () => HttpResponse.json({ ok: true })),
  http.get('*/api/admin/dashboard', () =>
    HttpResponse.json(dashboardPayload),
  ),
  http.get('*/api/admin/monitoring/health', () =>
    HttpResponse.json(monitoringHealthPayload),
  ),
  http.get('*/api/admin/sync-health', () =>
    HttpResponse.json(syncHealthPayload),
  ),
  http.get('*/api/admin/data/tasks', () =>
    HttpResponse.json({ items: taskRows }),
  ),
  http.get('*/api/admin/data/schedules', () =>
    HttpResponse.json({ items: scheduleRows }),
  ),
  http.get('*/api/admin/data/:domain', () =>
    HttpResponse.json({ items: [] }),
  ),
  http.patch('*/api/admin/data/:domain/:id', () =>
    HttpResponse.json({ ok: true }),
  ),
];
