import { describe, expect, it, vi } from 'vitest';
import { AdminController } from '../admin/admin.controller';
import { ClientController } from '../client/client.controller';

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

describe('Outlook controller forwarding', () => {
  it('forwards every admin Outlook endpoint with request context and admin sync trigger', () => {
    const admin = mockMethods(['alerts']);
    const sync = mockMethods(['resolveConflict']);
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

    expect(controller.outlook(headers)).toEqual({ method: 'status', args: [context] });
    expect(controller.outlookStatus(headers)).toEqual({ method: 'status', args: [context] });
    expect(controller.outlookAuthStart({ clientId: 'client-id' }, headers)).toEqual({
      method: 'startAuth',
      args: [{ clientId: 'client-id' }, context],
    });
    expect(controller.outlookAuthComplete({ code: 'code', state: 'state' }, headers)).toEqual({
      method: 'completeAuth',
      args: [{ code: 'code', state: 'state' }, context],
    });
    expect(controller.outlookSync(headers)).toEqual({
      method: 'syncNow',
      args: [context, 'admin'],
    });
    expect(controller.outlookReset(headers)).toEqual({ method: 'reset', args: [context] });
    expect(controller.outlookPrepareWrite({ title: 'Draft' }, headers)).toEqual({
      method: 'prepareWrite',
      args: [{ title: 'Draft' }, context],
    });
    expect(controller.outlookDrafts(headers)).toEqual({ method: 'drafts', args: [context] });
    expect(controller.outlookConfirmWrite('draft-1', { confirmationPhrase: 'CONFIRM' }, headers)).toEqual({
      method: 'confirmWrite',
      args: ['draft-1', { confirmationPhrase: 'CONFIRM' }, context],
    });
    expect(controller.outlookRejectWrite('draft-1', { reviewNote: 'No' }, headers)).toEqual({
      method: 'rejectWrite',
      args: ['draft-1', { reviewNote: 'No' }, context],
    });
    expect(controller.outlookCalendars(headers)).toEqual({
      method: 'calendars',
      args: [context],
    });
    expect(controller.outlookRuns(headers)).toEqual({ method: 'runs', args: [context] });
    expect(controller.outlookDiagnostics(headers)).toEqual({
      method: 'diagnostics',
      args: [context],
    });
  });

  it('forwards client Outlook refresh with request context and client sync trigger', () => {
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

    expect(controller.refreshOutlook(headers)).toEqual({
      method: 'syncNow',
      args: [context, 'client'],
    });
  });

  it('uses default request context when Outlook headers are missing or invalid', () => {
    const admin = mockMethods(['alerts']);
    const sync = mockMethods(['resolveConflict']);
    const outlook = mockMethods(['status']);
    const controller = new AdminController(admin as never, sync as never, outlook as never);

    expect(controller.outlookStatus({ 'x-flowplanv2-user-id': 'not-a-uuid' })).toEqual({
      method: 'status',
      args: [context],
    });
  });
});
