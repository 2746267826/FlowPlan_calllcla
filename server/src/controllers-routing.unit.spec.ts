import 'reflect-metadata';
import { RequestMethod } from '@nestjs/common';
import { METHOD_METADATA, PATH_METADATA } from '@nestjs/common/constants';
import { describe, expect, it, vi } from 'vitest';
import { ActivityController } from './activity/activity.controller';
import { AdminController } from './admin/admin.controller';
import { ClientController } from './client/client.controller';
import { DevicesController } from './devices/devices.controller';
import { ModelsController } from './models/models.controller';
import { CronJobsController } from './scheduler/cron-jobs.controller';

const headers = {
  'x-flowplanv2-user-id': '00000000-0000-4000-8000-000000000001',
  'x-flowplanv2-device-id': '00000000-0000-4000-8000-000000000101',
};
const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function mockMethods<T extends string>(methods: T[]) {
  return Object.fromEntries(
    methods.map((method) => [
      method,
      vi.fn((...args: unknown[]) => ({ method, args })),
    ]),
  ) as Record<T, ReturnType<typeof vi.fn>>;
}

function routeMetadata(controller: { prototype: Record<string, unknown> }, methodName: string) {
  const handler = controller.prototype[methodName];
  return {
    controllerPath: Reflect.getMetadata(PATH_METADATA, controller),
    methodPath: Reflect.getMetadata(PATH_METADATA, handler),
    requestMethod: Reflect.getMetadata(METHOD_METADATA, handler),
  };
}

describe('controller routing adapters', () => {
  it('keeps selected controller route metadata aligned with public HTTP contracts', () => {
    expect(routeMetadata(DevicesController, 'update')).toEqual({
      controllerPath: 'devices',
      methodPath: ':deviceId',
      requestMethod: RequestMethod.PATCH,
    });
    expect(routeMetadata(ClientController, 'pushMutations')).toEqual({
      controllerPath: 'client',
      methodPath: 'mutations',
      requestMethod: RequestMethod.POST,
    });
    expect(routeMetadata(AdminController, 'resolveConflict')).toEqual({
      controllerPath: 'admin',
      methodPath: 'conflicts/:conflictId/resolve',
      requestMethod: RequestMethod.POST,
    });
    expect(routeMetadata(ModelsController, 'activate')).toEqual({
      controllerPath: 'models',
      methodPath: ':modelKey/versions/:versionId/activate',
      requestMethod: RequestMethod.POST,
    });
    expect(routeMetadata(ActivityController, 'confirm')).toEqual({
      controllerPath: 'activity',
      methodPath: 'segments/:segmentId/confirm',
      requestMethod: RequestMethod.POST,
    });
    expect(routeMetadata(CronJobsController, 'triggerJob')).toEqual({
      controllerPath: 'admin/jobs',
      methodPath: ':jobName/trigger',
      requestMethod: RequestMethod.POST,
    });
  });

  it('forwards devices endpoints to DevicesService with request context', () => {
    const service = mockMethods(['register', 'list', 'update', 'revoke', 'heartbeat']);
    const controller = new DevicesController(service as never);

    expect(controller.register({ deviceName: 'desk' }, headers)).toEqual({
      method: 'register',
      args: [{ deviceName: 'desk' }, context],
    });
    expect(controller.list(headers)).toEqual({ method: 'list', args: [context] });
    expect(controller.update('device-1', { platform: 'win' }, headers)).toEqual({
      method: 'update',
      args: ['device-1', { platform: 'win' }, context],
    });
    expect(controller.revoke('device-1', { reason: 'lost' }, headers)).toEqual({
      method: 'revoke',
      args: ['device-1', { reason: 'lost' }, context],
    });
    expect(controller.heartbeat('device-1', { appVersion: '1.0' }, headers)).toEqual({
      method: 'heartbeat',
      args: ['device-1', { appVersion: '1.0' }, context],
    });
  });

  it('normalizes array headers and defaults invalid device ids independently', () => {
    const service = mockMethods(['register']);
    const controller = new DevicesController(service as never);
    const body = { deviceName: 'tablet' };

    expect(
      controller.register(body, {
        'x-flowplanv2-user-id': [context.userId],
        'x-flowplanv2-device-id': 'not-a-uuid',
      }),
    ).toEqual({
      method: 'register',
      args: [
        body,
        {
          userId: context.userId,
          deviceId: '00000000-0000-4000-8000-000000000101',
        },
      ],
    });
    expect(service.register.mock.calls[0][0]).toBe(body);
  });

  it('forwards model endpoints to ModelsService', () => {
    const service = mockMethods([
      'list',
      'llmHealth',
      'versions',
      'runs',
      'feedback',
      'evaluate',
      'learn',
      'activate',
    ]);
    const controller = new ModelsController(service as never);

    expect(controller.list(headers)).toEqual({ method: 'list', args: [context] });
    expect(controller.llmHealth(headers)).toEqual({ method: 'llmHealth', args: [context] });
    expect(controller.versions('scheduler.v1', headers)).toEqual({
      method: 'versions',
      args: ['scheduler.v1', context],
    });
    expect(controller.runs('scheduler.v1', { limit: '5' }, headers)).toEqual({
      method: 'runs',
      args: ['scheduler.v1', { limit: '5' }, context],
    });
    expect(controller.feedback('scheduler.v1', { feedbackType: 'accepted' }, headers)).toEqual({
      method: 'feedback',
      args: ['scheduler.v1', { feedbackType: 'accepted' }, context],
    });
    expect(controller.evaluate('scheduler.v1', { limit: 3 }, headers)).toEqual({
      method: 'evaluate',
      args: ['scheduler.v1', { limit: 3 }, context],
    });
    expect(controller.learn('scheduler.v1', { autoActivate: false }, headers)).toEqual({
      method: 'learn',
      args: ['scheduler.v1', { autoActivate: false }, context],
    });
    expect(controller.activate('scheduler.v1', 'version-1', { confirmationToken: 'CONFIRM' }, headers)).toEqual({
      method: 'activate',
      args: ['scheduler.v1', 'version-1', { confirmationToken: 'CONFIRM' }, context],
    });
  });

  it('forwards client endpoints across client, web, sync, and outlook services', () => {
    const client = mockMethods([
      'bootstrap',
      'settings',
      'effectiveSettings',
      'updateSetting',
      'settingsPolicy',
      'createLocalSnapshotImport',
      'importStatus',
      'confirmImport',
      'cancelImport',
    ]);
    const web = mockMethods([
      'tasks',
      'createTask',
      'updateTask',
      'completeTask',
      'deleteTask',
      'events',
      'createEvent',
      'updateEvent',
      'deleteEvent',
      'actualRecords',
    ]);
    const sync = mockMethods(['push']);
    const outlook = mockMethods(['syncNow']);
    const controller = new ClientController(
      client as never,
      web as never,
      sync as never,
      outlook as never,
    );

    expect(controller.bootstrap(headers)).toEqual({ method: 'bootstrap', args: [context] });
    expect(controller.settings(headers)).toEqual({ method: 'settings', args: [context] });
    expect(controller.effectiveSettings(headers)).toEqual({ method: 'effectiveSettings', args: [context] });
    expect(controller.updateSetting('theme', { value: { dark: true } }, headers)).toEqual({
      method: 'updateSetting',
      args: ['theme', { value: { dark: true } }, context],
    });
    expect(controller.settingsPolicy()).toEqual({ method: 'settingsPolicy', args: [] });
    expect(controller.tasks({ status: 'open' }, headers)).toEqual({
      method: 'tasks',
      args: [{ status: 'open' }, context],
    });
    expect(controller.createTask({ title: 'T' }, headers)).toEqual({
      method: 'createTask',
      args: [{ title: 'T' }, context],
    });
    expect(controller.updateTask('task-1', { title: 'T2' }, headers)).toEqual({
      method: 'updateTask',
      args: ['task-1', { title: 'T2' }, context],
    });
    expect(controller.completeTask('task-1', { completedAt: 'now' }, headers)).toEqual({
      method: 'completeTask',
      args: ['task-1', { completedAt: 'now' }, context],
    });
    expect(controller.deleteTask('task-1', headers)).toEqual({
      method: 'deleteTask',
      args: ['task-1', context],
    });
    expect(controller.events({ from: 'today' }, headers)).toEqual({
      method: 'events',
      args: [{ from: 'today' }, context],
    });
    expect(controller.createEvent({ title: 'E' }, headers)).toEqual({
      method: 'createEvent',
      args: [{ title: 'E' }, context],
    });
    expect(controller.updateEvent('event-1', { title: 'E2' }, headers)).toEqual({
      method: 'updateEvent',
      args: ['event-1', { title: 'E2' }, context],
    });
    expect(controller.deleteEvent('event-1', headers)).toEqual({
      method: 'deleteEvent',
      args: ['event-1', context],
    });
    expect(controller.actualRecords({ status: 'confirmed' }, headers)).toEqual({
      method: 'actualRecords',
      args: [{ status: 'confirmed' }, context],
    });
    expect(controller.pushMutations({ mutations: [] } as never, headers)).toEqual({
      method: 'push',
      args: [{ mutations: [] }, context],
    });
    expect(controller.refreshOutlook(headers)).toEqual({
      method: 'syncNow',
      args: [context, 'client'],
    });
    expect(controller.createLocalSnapshotImport({ snapshot: {} }, headers)).toEqual({
      method: 'createLocalSnapshotImport',
      args: [{ snapshot: {} }, context],
    });
    expect(controller.importStatus('import-1', headers)).toEqual({
      method: 'importStatus',
      args: ['import-1', context],
    });
    expect(controller.confirmImport('import-1', headers)).toEqual({
      method: 'confirmImport',
      args: ['import-1', context],
    });
    expect(controller.cancelImport('import-1', { reason: 'nope' }, headers)).toEqual({
      method: 'cancelImport',
      args: ['import-1', { reason: 'nope' }, context],
    });
  });

  it('forwards activity and cron job endpoints', () => {
    const activity = mockMethods(['segments', 'confirmSegment', 'rejectSegment']);
    const activityController = new ActivityController(activity as never);
    expect(activityController.segments({ limit: '10' }, headers)).toEqual({
      method: 'segments',
      args: [{ limit: '10' }, context],
    });
    expect(activityController.confirm('segment-1', { title: 'Focus' }, headers)).toEqual({
      method: 'confirmSegment',
      args: ['segment-1', { title: 'Focus' }, context],
    });
    expect(activityController.reject('segment-1', { reason: 'wrong' }, headers)).toEqual({
      method: 'rejectSegment',
      args: ['segment-1', { reason: 'wrong' }, context],
    });

    const cron = mockMethods(['listJobs', 'triggerJob', 'pauseJob', 'resumeJob']);
    const cronController = new CronJobsController(cron as never);
    expect(cronController.listJobs()).toEqual({ jobs: { method: 'listJobs', args: [] } });
    expect(cronController.triggerJob('refresh-weather-cache')).toEqual({
      method: 'triggerJob',
      args: ['refresh-weather-cache'],
    });
    expect(cronController.pauseJob('refresh-weather-cache')).toEqual({
      method: 'pauseJob',
      args: ['refresh-weather-cache'],
    });
    expect(cronController.resumeJob('refresh-weather-cache')).toEqual({
      method: 'resumeJob',
      args: ['refresh-weather-cache'],
    });
  });

  it('forwards admin endpoints and records conflict-resolution audit action', async () => {
    const admin = mockMethods([
      'overview',
      'dashboard',
      'syncHealth',
      'adminData',
      'adminDataDetail',
      'deviceOnlineSummary',
      'newInfo',
      'deviceConnectionHistory',
      'updateAdminData',
      'adminSettings',
      'upsertRemoteConfig',
      'monitoringHealth',
      'monitoringLogs',
      'monitoringJobs',
      'prepareOperation',
      'confirmOperation',
      'objects',
      'updateObject',
      'actualRecords',
      'updateActualRecord',
      'files',
      'updateFile',
      'conflicts',
      'recordAdminAction',
      'alerts',
      'auditLogs',
      'reports',
      'pushDeliveries',
      'aiDrafts',
      'updateAiDraft',
      'jobs',
      'upsertJob',
      'remoteConfigs',
      'runtimeEnv',
      'uploadEnv',
    ]);
    const sync = {
      resolveConflict: vi.fn(async (...args: unknown[]) => ({ method: 'resolveConflict', args })),
    };
    const outlook = mockMethods([
      'status',
      'startAuth',
      'completeAuth',
      'syncNow',
      'reset',
      'prepareWrite',
      'drafts',
      'confirmWrite',
      'rejectWrite',
      'calendars',
      'runs',
      'diagnostics',
    ]);
    const controller = new AdminController(admin as never, sync as never, outlook as never);

    expect(controller.overview(headers)).toEqual({ method: 'overview', args: [context] });
    expect(controller.dashboard(headers)).toEqual({ method: 'dashboard', args: [context] });
    expect(controller.syncHealth(headers)).toEqual({ method: 'syncHealth', args: [context] });
    expect(controller.adminData('tasks', { limit: '5' }, headers)).toEqual({
      method: 'adminData',
      args: ['tasks', { limit: '5' }, context],
    });
    expect(controller.adminDataDetail('tasks', 'id-1', headers)).toEqual({
      method: 'adminDataDetail',
      args: ['tasks', 'id-1', context],
    });
    expect(controller.deviceOnlineSummary(headers)).toEqual({ method: 'deviceOnlineSummary', args: [context] });
    expect(controller.newInfo({ since: '2026-01-01T00:00:00Z' }, headers)).toEqual({
      method: 'newInfo',
      args: [{ since: '2026-01-01T00:00:00Z' }, context],
    });
    expect(controller.deviceConnectionHistory('device-1', headers)).toEqual({
      method: 'deviceConnectionHistory',
      args: ['device-1', context],
    });
    expect(controller.updateAdminData('tasks', 'id-1', { title: 'A' }, headers)).toEqual({
      method: 'updateAdminData',
      args: ['tasks', 'id-1', { title: 'A' }, context],
    });
    expect(controller.adminSettings(headers)).toEqual({ method: 'adminSettings', args: [context] });
    expect(controller.upsertAdminSetting('theme', { value: {} }, headers)).toEqual({
      method: 'upsertRemoteConfig',
      args: ['theme', { value: {} }, context],
    });
    expect(controller.monitoringHealth(headers)).toEqual({ method: 'monitoringHealth', args: [context] });
    expect(controller.monitoringLogs({ limit: '10' }, headers)).toEqual({
      method: 'monitoringLogs',
      args: [{ limit: '10' }, context],
    });
    expect(controller.monitoringJobs(headers)).toEqual({ method: 'monitoringJobs', args: [context] });
    expect(controller.prepareOperation('retry_sync', { targetId: 'all' }, headers)).toEqual({
      method: 'prepareOperation',
      args: ['retry_sync', { targetId: 'all' }, context],
    });
    expect(controller.confirmOperation('retry_sync', { confirmationToken: 't' }, headers)).toEqual({
      method: 'confirmOperation',
      args: ['retry_sync', { confirmationToken: 't' }, context],
    });
    expect(controller.objects({ domain: 'tasks' }, headers)).toEqual({
      method: 'objects',
      args: [{ domain: 'tasks' }, context],
    });
    expect(controller.updateObject('object-1', { payload: {} }, headers)).toEqual({
      method: 'updateObject',
      args: ['object-1', { payload: {} }, context],
    });
    expect(controller.actualRecords({ status: 'confirmed' }, headers)).toEqual({
      method: 'actualRecords',
      args: [{ status: 'confirmed' }, context],
    });
    expect(controller.updateActualRecord('actual-1', { note: 'n' }, headers)).toEqual({
      method: 'updateActualRecord',
      args: ['actual-1', { note: 'n' }, context],
    });
    expect(controller.files({ q: 'report' }, headers)).toEqual({
      method: 'files',
      args: [{ q: 'report' }, context],
    });
    expect(controller.updateFile('file-1', { displayName: 'R' }, headers)).toEqual({
      method: 'updateFile',
      args: ['file-1', { displayName: 'R' }, context],
    });
    expect(controller.conflicts({ deviceId: 'all' }, headers)).toEqual({
      method: 'conflicts',
      args: [{ deviceId: 'all' }, context],
    });

    await expect(
      controller.resolveConflict('conflict-1', { strategy: 'server_wins' } as never, headers),
    ).resolves.toEqual({
      method: 'resolveConflict',
      args: ['conflict-1', { strategy: 'server_wins' }, context],
    });
    expect(admin.recordAdminAction).toHaveBeenCalledWith(
      context,
      'admin.conflict.resolve',
      { conflictId: 'conflict-1', strategy: 'server_wins' },
    );

    expect(controller.outlook(headers)).toEqual({ method: 'status', args: [context] });
    expect(controller.outlookStatus(headers)).toEqual({ method: 'status', args: [context] });
    expect(controller.outlookAuthStart({ redirectUri: 'u' }, headers)).toEqual({
      method: 'startAuth',
      args: [{ redirectUri: 'u' }, context],
    });
    expect(controller.outlookAuthComplete({ code: 'c' }, headers)).toEqual({
      method: 'completeAuth',
      args: [{ code: 'c' }, context],
    });
    expect(controller.outlookSync(headers)).toEqual({ method: 'syncNow', args: [context, 'admin'] });
    expect(controller.outlookReset(headers)).toEqual({ method: 'reset', args: [context] });
    expect(controller.outlookPrepareWrite({ title: 'Draft' }, headers)).toEqual({
      method: 'prepareWrite',
      args: [{ title: 'Draft' }, context],
    });
    expect(controller.outlookDrafts(headers)).toEqual({ method: 'drafts', args: [context] });
    expect(controller.outlookConfirmWrite('draft-1', { confirmationToken: 'ok' }, headers)).toEqual({
      method: 'confirmWrite',
      args: ['draft-1', { confirmationToken: 'ok' }, context],
    });
    expect(controller.outlookRejectWrite('draft-1', { reason: 'bad' }, headers)).toEqual({
      method: 'rejectWrite',
      args: ['draft-1', { reason: 'bad' }, context],
    });
    expect(controller.alerts(headers)).toEqual({
      method: 'alerts',
      args: [context.userId],
    });
    expect(controller.outlookCalendars(headers)).toEqual({ method: 'calendars', args: [context] });
    expect(controller.outlookRuns(headers)).toEqual({ method: 'runs', args: [context] });
    expect(controller.outlookDiagnostics(headers)).toEqual({ method: 'diagnostics', args: [context] });
    expect(controller.auditLogs({ limit: '4' }, headers)).toEqual({
      method: 'auditLogs',
      args: [{ limit: '4' }, context],
    });
    expect(controller.reports({ status: 'ready' }, headers)).toEqual({
      method: 'reports',
      args: [{ status: 'ready' }, context],
    });
    expect(controller.pushDeliveries({ status: 'failed' }, headers)).toEqual({
      method: 'pushDeliveries',
      args: [{ status: 'failed' }, context],
    });
    expect(controller.aiDrafts({ status: 'pending' }, headers)).toEqual({
      method: 'aiDrafts',
      args: [{ status: 'pending' }, context],
    });
    expect(controller.updateAiDraft('draft-2', { status: 'approved' }, headers)).toEqual({
      method: 'updateAiDraft',
      args: ['draft-2', { status: 'approved' }, context],
    });
    expect(controller.jobs(headers)).toEqual({ method: 'jobs', args: [context] });
    expect(controller.upsertJob('daily', { status: 'enabled' }, headers)).toEqual({
      method: 'upsertJob',
      args: ['daily', { status: 'enabled' }, context],
    });
    expect(controller.remoteConfigs(headers)).toEqual({ method: 'remoteConfigs', args: [context] });
    expect(controller.upsertRemoteConfig('cfg', { value: 1 }, headers)).toEqual({
      method: 'upsertRemoteConfig',
      args: ['cfg', { value: 1 }, context],
    });
    expect(controller.env()).toEqual({ method: 'runtimeEnv', args: [] });
    expect(controller.envUpload({ content: 'DATABASE_URL=x' })).toEqual({
      method: 'uploadEnv',
      args: ['DATABASE_URL=x'],
    });
    expect(controller.envUpload({})).toEqual({
      method: 'uploadEnv',
      args: [''],
    });
  });

  it('does not record the admin conflict audit action when conflict resolution fails', async () => {
    const error = new Error('sync conflict disappeared');
    const admin = {
      recordAdminAction: vi.fn(),
    };
    const sync = {
      resolveConflict: vi.fn(async () => {
        throw error;
      }),
    };
    const controller = new AdminController(admin as never, sync as never, {} as never);
    const dto = { strategy: 'server_wins' } as never;

    await expect(controller.resolveConflict('conflict-1', dto, headers)).rejects.toBe(error);
    expect(sync.resolveConflict).toHaveBeenCalledWith('conflict-1', dto, context);
    expect(admin.recordAdminAction).not.toHaveBeenCalled();
  });
});
