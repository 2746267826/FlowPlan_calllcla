import {
  BadRequestException,
  Injectable,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
} from 'node:crypto';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

const AUTHORITY = 'https://login.microsoftonline.com/consumers';
const REDIRECT_URI =
  'https://login.microsoftonline.com/common/oauth2/nativeclient';
const SCOPE = 'openid profile offline_access User.Read Calendars.Read';
const GRAPH_BASE = 'https://graph.microsoft.com/v1.0';
const SYNC_INTERVAL_MINUTES = 15;
const GRAPH_CALENDAR_VIEW_PAGE_SIZE = 50;

type OutlookConnectionRow = {
  id: string;
  user_id: string;
  client_id: string;
  authority: string;
  redirect_uri: string;
  scope: string;
  account_email: string | null;
  account_display_name: string | null;
  refresh_token_encrypted: string | null;
  access_token_encrypted: string | null;
  access_token_expires_at: Date | string | null;
  status: string;
  sync_interval_minutes: number;
  last_sync_at: Date | string | null;
  last_error: string | null;
  updated_at: Date | string;
};

type OutlookCalendar = {
  id: string;
  name?: string;
  color?: string;
  hexColor?: string;
  isDefaultCalendar?: boolean;
};

type OutlookEvent = {
  id: string;
  subject?: string;
  bodyPreview?: string;
  body?: { content?: string };
  location?: { displayName?: string };
  start?: { dateTime?: string; timeZone?: string };
  end?: { dateTime?: string; timeZone?: string };
  showAs?: string;
  isCancelled?: boolean;
  isAllDay?: boolean;
  lastModifiedDateTime?: string;
  createdDateTime?: string;
  webLink?: string;
  '@odata.etag'?: string;
  '@removed'?: { reason?: string };
};

type SyncResult = {
  ok: boolean;
  runId: string;
  triggerSource: string;
  status: string;
  calendarCount: number;
  eventUpserts: number;
  eventDeletes: number;
  startedAt: string;
  finishedAt: string;
  errorMessage?: string | null;
};

@Injectable()
export class OutlookService implements OnModuleInit, OnModuleDestroy {
  private timer: NodeJS.Timeout | undefined;
  private readonly activeRuns = new Set<string>();

  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  onModuleInit() {
    this.timer = setInterval(() => {
      void this.runDueSyncs();
    }, 60_000);
  }

  onModuleDestroy() {
    if (this.timer) {
      clearInterval(this.timer);
    }
  }

  async status(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const [connection, calendars, lastRun, tokenSecretStatus] = await Promise.all([
      this.getConnection(userId),
      this.countCalendars(userId),
      this.latestRun(userId),
      this.tokenSecretStatus(userId),
    ]);

    return {
      readOnly: true,
      graphHttpMethodsAllowed: ['GET'],
      authority: AUTHORITY,
      redirectUri: REDIRECT_URI,
      scope: SCOPE,
      syncMode: 'server_pull_only',
      automaticSyncIntervalMinutes: SYNC_INTERVAL_MINUTES,
      tokenSecretConfigured: tokenSecretStatus.configured,
      tokenSecretSource: tokenSecretStatus.source,
      connected: connection?.status === 'connected',
      status: connection?.status ?? 'disconnected',
      accountEmail: connection?.account_email ?? null,
      accountDisplayName: connection?.account_display_name ?? null,
      clientIdConfigured: Boolean(connection?.client_id),
      lastSyncAt: this.iso(connection?.last_sync_at),
      lastError: connection?.last_error ?? null,
      calendars,
      lastRun,
      notes: [
        'Outlook is managed on the server.',
        'Clients receive Outlook calendar_book and calendar_event objects through sync pull.',
        'No Microsoft Graph write endpoints are used.',
      ],
    };
  }

  async startAuth(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const clientId = this.cleanString(body.clientId);
    if (!clientId) {
      throw new BadRequestException('clientId is required');
    }

    const state = this.base64Url(randomBytes(32));
    const codeVerifier = this.base64Url(randomBytes(48));
    const codeChallenge = this.base64Url(
      createHash('sha256').update(codeVerifier).digest(),
    );

    await this.database.transaction(async (client) => {
      await client.query(
        `
        INSERT INTO outlook_connections (
          user_id, client_id, authority, redirect_uri, scope, status,
          sync_interval_minutes, updated_at
        ) VALUES ($1, $2, $3, $4, $5, 'authorization_pending', $6, now())
        ON CONFLICT (user_id) DO UPDATE SET
          client_id = EXCLUDED.client_id,
          authority = EXCLUDED.authority,
          redirect_uri = EXCLUDED.redirect_uri,
          scope = EXCLUDED.scope,
          status = 'authorization_pending',
          sync_interval_minutes = EXCLUDED.sync_interval_minutes,
          updated_at = now()
        `,
        [userId, clientId, AUTHORITY, REDIRECT_URI, SCOPE, SYNC_INTERVAL_MINUTES],
      );
      await client.query(
        `
        INSERT INTO outlook_auth_sessions (
          user_id, state, code_verifier, client_id, redirect_uri, scope, expires_at
        ) VALUES ($1, $2, $3, $4, $5, $6, now() + interval '15 minutes')
        `,
        [userId, state, codeVerifier, clientId, REDIRECT_URI, SCOPE],
      );
    });

    const params = new URLSearchParams({
      client_id: clientId,
      response_type: 'code',
      redirect_uri: REDIRECT_URI,
      response_mode: 'query',
      scope: SCOPE,
      state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256',
      prompt: 'select_account',
    });

    return {
      authorizeUrl: `${AUTHORITY}/oauth2/v2.0/authorize?${params.toString()}`,
      state,
      redirectUri: REDIRECT_URI,
      scope: SCOPE,
      readOnly: true,
    };
  }

  async completeAuth(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    if (!(await this.hasTokenSecret(userId))) {
      throw new BadRequestException(
        'Outlook token encryption secret is required before authorization. Configure FLOWPLANV2_OUTLOOK_TOKEN_SECRET or save it in the Outlook admin panel, then retry authorization.',
      );
    }
    const parsed = this.readAuthCompletion(body);
    const session = await this.database.query<{
      state: string;
      code_verifier: string;
      client_id: string;
      redirect_uri: string;
      scope: string;
    }>(
      `
      SELECT state, code_verifier, client_id, redirect_uri, scope
      FROM outlook_auth_sessions
      WHERE user_id = $1 AND state = $2 AND used_at IS NULL AND expires_at > now()
      LIMIT 1
      `,
      [userId, parsed.state],
    );
    const authSession = session.rows[0];
    if (!authSession) {
      throw new BadRequestException(
        'Outlook authorization state is invalid or expired. Start authorization again and paste the newest callback URL.',
      );
    }

    const token = await this.exchangeCode(
      authSession.client_id,
      authSession.redirect_uri,
      authSession.scope,
      parsed.code,
      authSession.code_verifier,
    );
    if (!token.refresh_token) {
      throw new BadRequestException(
        'Outlook OAuth response did not include a refresh token. Start authorization again and make sure offline_access is granted.',
      );
    }
    const refreshToken = token.refresh_token;
    const expiresAt = new Date(Date.now() + Number(token.expires_in ?? 3600) * 1000);
    const me = await this.graphGet<Record<string, unknown>>(
      '/me?$select=displayName,mail,userPrincipalName',
      token.access_token,
    );

    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE outlook_auth_sessions
        SET used_at = now()
        WHERE user_id = $1 AND state = $2
        `,
        [userId, parsed.state],
      );
      await client.query(
        `
        UPDATE outlook_connections
        SET
          refresh_token_encrypted = $3,
          access_token_encrypted = $4,
          access_token_expires_at = $5,
          account_email = $6,
          account_display_name = $7,
          status = 'connected',
          last_error = NULL,
          updated_at = now()
        WHERE user_id = $1 AND client_id = $2
        `,
        [
          userId,
          authSession.client_id,
          this.encrypt(refreshToken),
          this.encrypt(token.access_token),
          expiresAt,
          this.cleanString(me.mail) ?? this.cleanString(me.userPrincipalName),
          this.cleanString(me.displayName),
        ],
      );
    });

    return {
      ok: true,
      readOnly: true,
      scope: SCOPE,
      accountEmail: this.cleanString(me.mail) ?? this.cleanString(me.userPrincipalName),
      accountDisplayName: this.cleanString(me.displayName),
    };
  }

  async syncNow(
    context: FlowPlanV2RequestContext,
    triggerSource: 'admin' | 'client' | 'automatic' = 'admin',
  ): Promise<SyncResult> {
    const userId = await this.devicesService.ensureUser(context.userId);
    return this.syncUser(userId, triggerSource);
  }

  async saveTokenSecret(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const secret = this.cleanString(body.secret);
    if (!secret || secret.length < 32) {
      throw new BadRequestException(
        'Outlook token encryption secret must be at least 32 characters',
      );
    }
    const confirmRotation = body.confirmRotation === true;
    const connection = await this.getConnection(userId);
    const hasTokens = Boolean(
      connection?.access_token_encrypted || connection?.refresh_token_encrypted,
    );
    if (hasTokens && !confirmRotation) {
      throw new BadRequestException(
        'Outlook tokens already exist. Confirm rotation to clear existing tokens and reconnect Outlook.',
      );
    }

    await this.database.transaction(async (client) => {
      await client.query(
        `
        INSERT INTO admin_remote_configs (
          user_id, config_key, config_value, description, is_sensitive, scope, updated_by
        ) VALUES ($1, 'outlook.token_secret', $2::jsonb, $3, true, 'outlook.connection', 'admin')
        ON CONFLICT (user_id, config_key) DO UPDATE SET
          config_value = EXCLUDED.config_value,
          description = EXCLUDED.description,
          is_sensitive = true,
          scope = EXCLUDED.scope,
          version = admin_remote_configs.version + 1,
          updated_by = 'admin',
          updated_at = now()
        `,
        [
          userId,
          JSON.stringify({ secret, configuredAt: new Date().toISOString() }),
          'Outlook token encryption secret configured from admin panel',
        ],
      );
      if (hasTokens) {
        await client.query(
          `
          UPDATE outlook_connections
          SET
            refresh_token_encrypted = NULL,
            access_token_encrypted = NULL,
            access_token_expires_at = NULL,
            status = 'disconnected',
            last_error = 'Token secret rotated; reconnect Outlook.',
            updated_at = now()
          WHERE user_id = $1
          `,
          [userId],
        );
      }
    });

    process.env.FLOWPLANV2_OUTLOOK_TOKEN_SECRET = secret;
    return {
      ok: true,
      configured: true,
      source: 'admin_panel',
      tokensCleared: hasTokens,
    };
  }

  async reset(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.transaction(async (client) => {
      const deleted = await client.query<{
        id: string;
        object_type: string;
        server_version: number;
        payload: Record<string, unknown>;
      }>(
        `
        UPDATE sync_objects
        SET deleted_at = now(), server_version = server_version + 1, updated_at = now()
        WHERE user_id = $1
          AND object_type IN ('calendar_book', 'calendar_event')
          AND deleted_at IS NULL
          AND payload->>'source' = 'outlook'
        RETURNING id::text, object_type, server_version, payload
        `,
        [userId],
      );
      for (const row of deleted.rows) {
        await this.recordChange(
          client,
          userId,
          row.id,
          row.object_type,
          'delete',
          row.server_version,
          row.payload,
        );
      }
      await client.query('DELETE FROM outlook_object_mappings WHERE user_id = $1', [
        userId,
      ]);
      await client.query('DELETE FROM outlook_calendar_states WHERE user_id = $1', [
        userId,
      ]);
      await client.query(
        `
        UPDATE outlook_connections
        SET last_sync_at = NULL, last_error = NULL, updated_at = now()
        WHERE user_id = $1
        `,
        [userId],
      );
      await client.query(
        `
        INSERT INTO outlook_sync_runs (
          user_id, trigger_source, status, finished_at, event_deletes, metadata
        ) VALUES ($1, 'admin_reset', 'succeeded', now(), $2, $3::jsonb)
        `,
        [
          userId,
          deleted.rowCount,
          JSON.stringify({ remoteOutlookDataDeleted: false }),
        ],
      );
      return { deletedObjects: deleted.rowCount };
    });

    return {
      ok: true,
      readOnly: true,
      remoteOutlookDataDeleted: false,
      ...result,
    };
  }

  async calendars(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        remote_calendar_id AS "remoteCalendarId",
        name,
        color_hex AS "colorHex",
        is_visible AS "isVisible",
        last_synced_at AS "lastSyncedAt",
        updated_at AS "updatedAt"
      FROM outlook_calendar_states
      WHERE user_id = $1
      ORDER BY name ASC NULLS LAST, updated_at DESC
      `,
      [userId],
    );
    return { calendars: result.rows };
  }

  async runs(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        id::text,
        trigger_source AS "triggerSource",
        status,
        started_at AS "startedAt",
        finished_at AS "finishedAt",
        calendar_count AS "calendarCount",
        event_upserts AS "eventUpserts",
        event_deletes AS "eventDeletes",
        error_message AS "errorMessage",
        metadata
      FROM outlook_sync_runs
      WHERE user_id = $1
      ORDER BY started_at DESC
      LIMIT 50
      `,
      [userId],
    );
    return { runs: result.rows };
  }

  async diagnostics(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const [status, objectCounts, mappings] = await Promise.all([
      this.status(context),
      this.database.query(
        `
        SELECT object_type AS "objectType", count(*)::int AS count
        FROM sync_objects
        WHERE user_id = $1
          AND deleted_at IS NULL
          AND payload->>'source' = 'outlook'
        GROUP BY object_type
        ORDER BY object_type
        `,
        [userId],
      ),
      this.database.query(
        `
        SELECT sync_state AS "syncState", count(*)::int AS count
        FROM outlook_object_mappings
        WHERE user_id = $1
        GROUP BY sync_state
        ORDER BY sync_state
        `,
        [userId],
      ),
    ]);
    return {
      ...status,
      objectCounts: objectCounts.rows,
      mappings: mappings.rows,
      writeBackEnabled: false,
      graphWriteMethodsAllowed: [],
    };
  }

  private async runDueSyncs() {
    const due = await this.database.query<OutlookConnectionRow>(
      `
      SELECT *
      FROM outlook_connections
      WHERE status = 'connected'
        AND refresh_token_encrypted IS NOT NULL
        AND (
          last_sync_at IS NULL
          OR last_sync_at <= now() - (sync_interval_minutes || ' minutes')::interval
        )
      ORDER BY COALESCE(last_sync_at, 'epoch'::timestamptz) ASC
      LIMIT 5
      `,
    );
    for (const connection of due.rows) {
      if (this.activeRuns.has(connection.user_id)) {
        continue;
      }
      void this.syncUser(connection.user_id, 'automatic').catch(() => undefined);
    }
  }

  private async syncUser(
    userId: string,
    triggerSource: 'admin' | 'client' | 'automatic',
  ): Promise<SyncResult> {
    if (this.activeRuns.has(userId)) {
      const latest = await this.latestRun(userId);
      return {
        ok: true,
        runId: latest?.id ?? 'already-running',
        triggerSource,
        status: 'already_running',
        calendarCount: latest?.calendarCount ?? 0,
        eventUpserts: latest?.eventUpserts ?? 0,
        eventDeletes: latest?.eventDeletes ?? 0,
        startedAt: this.iso(latest?.startedAt) ?? new Date().toISOString(),
        finishedAt: new Date().toISOString(),
        errorMessage: null,
      };
    }

    this.activeRuns.add(userId);
    const startedAt = new Date();
    const run = await this.database.query<{ id: string }>(
      `
      INSERT INTO outlook_sync_runs (user_id, trigger_source, status)
      VALUES ($1, $2, 'running')
      RETURNING id::text
      `,
      [userId, triggerSource],
    );
    const runId = run.rows[0].id;
    let calendarCount = 0;
    let eventUpserts = 0;
    let eventDeletes = 0;

    try {
      const connection = await this.getConnection(userId);
      if (!connection || connection.status !== 'connected') {
        throw new Error('Outlook is not connected on the server');
      }
      const accessToken = await this.ensureAccessToken(connection);
      const calendars = await this.fetchCalendars(accessToken);
      calendarCount = calendars.length;

      for (const calendar of calendars) {
        await this.syncCalendar(userId, accessToken, calendar, (delta) => {
          eventUpserts += delta.upserts;
          eventDeletes += delta.deletes;
        });
      }

      await this.database.query(
        `
        UPDATE outlook_connections
        SET last_sync_at = now(), last_error = NULL, status = 'connected', updated_at = now()
        WHERE user_id = $1
        `,
        [userId],
      );
      await this.database.query(
        `
        UPDATE outlook_sync_runs
        SET
          status = 'succeeded',
          finished_at = now(),
          calendar_count = $2,
          event_upserts = $3,
          event_deletes = $4,
          metadata = $5::jsonb
        WHERE id = $1
        `,
        [
          runId,
          calendarCount,
          eventUpserts,
          eventDeletes,
          JSON.stringify({ graphHttpMethods: ['GET'] }),
        ],
      );

      return {
        ok: true,
        runId,
        triggerSource,
        status: 'succeeded',
        calendarCount,
        eventUpserts,
        eventDeletes,
        startedAt: startedAt.toISOString(),
        finishedAt: new Date().toISOString(),
        errorMessage: null,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.database.query(
        `
        UPDATE outlook_connections
        SET last_error = $2, updated_at = now()
        WHERE user_id = $1
        `,
        [userId, message],
      );
      await this.database.query(
        `
        UPDATE outlook_sync_runs
        SET
          status = 'failed',
          finished_at = now(),
          calendar_count = $2,
          event_upserts = $3,
          event_deletes = $4,
          error_message = $5
        WHERE id = $1
        `,
        [runId, calendarCount, eventUpserts, eventDeletes, message],
      );
      return {
        ok: false,
        runId,
        triggerSource,
        status: 'failed',
        calendarCount,
        eventUpserts,
        eventDeletes,
        startedAt: startedAt.toISOString(),
        finishedAt: new Date().toISOString(),
        errorMessage: message,
      };
    } finally {
      this.activeRuns.delete(userId);
    }
  }

  private async syncCalendar(
    userId: string,
    accessToken: string,
    calendar: OutlookCalendar,
    onDelta: (delta: { upserts: number; deletes: number }) => void,
  ) {
    await this.upsertCalendarBook(userId, calendar);

    const state = await this.database.query<{ delta_link: string | null }>(
      `
      SELECT delta_link
      FROM outlook_calendar_states
      WHERE user_id = $1 AND remote_calendar_id = $2
      LIMIT 1
      `,
      [userId, calendar.id],
    );
    const deltaLink = state.rows[0]?.delta_link;
    const windowStart = new Date();
    windowStart.setFullYear(windowStart.getFullYear() - 1);
    const windowEnd = new Date();
    windowEnd.setFullYear(windowEnd.getFullYear() + 2);
    let url =
      deltaLink ??
      `${GRAPH_BASE}/me/calendars/${encodeURIComponent(
        calendar.id,
      )}/calendarView/delta?startDateTime=${encodeURIComponent(
        windowStart.toISOString(),
      )}&endDateTime=${encodeURIComponent(windowEnd.toISOString())}`;
    let newDeltaLink: string | null = null;
    let upserts = 0;
    let deletes = 0;

    while (url) {
      const page = await this.graphGet<{
        value?: OutlookEvent[];
        '@odata.nextLink'?: string;
        '@odata.deltaLink'?: string;
      }>(url, accessToken, [
        `odata.maxpagesize=${GRAPH_CALENDAR_VIEW_PAGE_SIZE}`,
      ]);
      for (const event of page.value ?? []) {
        if (event['@removed']) {
          const deleted = await this.deleteSyncObject(
            userId,
            'calendar_event',
            this.eventUid(calendar.id, event.id),
          );
          deletes += deleted ? 1 : 0;
        } else {
          const changed = await this.upsertCalendarEvent(userId, calendar, event);
          upserts += changed ? 1 : 0;
        }
      }
      url = page['@odata.nextLink'] ?? '';
      newDeltaLink = page['@odata.deltaLink'] ?? newDeltaLink;
    }

    await this.database.query(
      `
      INSERT INTO outlook_calendar_states (
        user_id, remote_calendar_id, name, color_hex, delta_link, is_visible,
        last_synced_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, true, now(), now())
      ON CONFLICT (user_id, remote_calendar_id) DO UPDATE SET
        name = EXCLUDED.name,
        color_hex = EXCLUDED.color_hex,
        delta_link = COALESCE(EXCLUDED.delta_link, outlook_calendar_states.delta_link),
        is_visible = true,
        last_synced_at = now(),
        updated_at = now()
      `,
      [
        userId,
        calendar.id,
        calendar.name ?? 'Outlook',
        this.calendarColor(calendar),
        newDeltaLink,
      ],
    );
    onDelta({ upserts, deletes });
  }

  private async upsertCalendarBook(userId: string, calendar: OutlookCalendar) {
    const uid = this.calendarUid(calendar.id);
    const payload = {
      uid,
      name: calendar.name ?? 'Outlook',
      colorHex: this.calendarColor(calendar),
      description: 'Outlook calendar synced by FlowPlanV2 server',
      isVisible: true,
      isDefault: Boolean(calendar.isDefaultCalendar),
      source: 'outlook',
      readOnly: true,
      syncUrl: calendar.id,
      remoteCalendarId: calendar.id,
      updatedAt: new Date().toISOString(),
    };
    const object = await this.upsertSyncObject(userId, 'calendar_book', uid, payload);
    if (object?.changed) {
      await this.upsertMapping(
        userId,
        'calendar_book',
        object.id,
        'calendar',
        calendar.id,
        calendar.id,
        null,
      );
    }
    return object?.changed ?? false;
  }

  private async upsertCalendarEvent(
    userId: string,
    calendar: OutlookCalendar,
    event: OutlookEvent,
  ) {
    const uid = this.eventUid(calendar.id, event.id);
    const payload = {
      uid,
      title: event.subject ?? '(No title)',
      summary: event.subject ?? '(No title)',
      description: event.bodyPreview ?? event.body?.content ?? '',
      location: event.location?.displayName ?? '',
      dtstart: this.outlookDateTime(event.start),
      dtend: this.outlookDateTime(event.end),
      status: event.isCancelled ? 'CANCELLED' : 'CONFIRMED',
      transp: event.showAs === 'free' ? 'TRANSPARENT' : 'OPAQUE',
      isBlock: event.showAs !== 'free',
      isAllDay: Boolean(event.isAllDay),
      source: 'outlook',
      readOnly: true,
      remoteCalendarId: calendar.id,
      remoteEventId: event.id,
      eventCalendarRemoteId: calendar.id,
      colorHex: this.calendarColor(calendar),
      webLink: event.webLink ?? null,
      updatedAt: event.lastModifiedDateTime ?? event.createdDateTime ?? new Date().toISOString(),
    };
    const object = await this.upsertSyncObject(userId, 'calendar_event', uid, payload);
    if (object?.changed) {
      await this.upsertMapping(
        userId,
        'calendar_event',
        object.id,
        'event',
        event.id,
        calendar.id,
        event['@odata.etag'] ?? null,
      );
    }
    return object?.changed ?? false;
  }

  private async upsertSyncObject(
    userId: string,
    objectType: 'calendar_book' | 'calendar_event',
    uid: string,
    payload: Record<string, unknown>,
  ) {
    return this.database.transaction(async (client) => {
      const existing = await client.query<{ id: string }>(
        `
        SELECT id::text
        FROM sync_objects
        WHERE user_id = $1 AND object_type = $2 AND uid = $3
        LIMIT 1
        `,
        [userId, objectType, uid],
      );
      if (!existing.rows[0]) {
        const created = await client.query<{
          id: string;
          server_version: number;
          payload: Record<string, unknown>;
        }>(
          `
          INSERT INTO sync_objects (user_id, object_type, uid, payload)
          VALUES ($1, $2, $3, $4::jsonb)
          RETURNING id::text, server_version, payload
          `,
          [userId, objectType, uid, JSON.stringify(payload)],
        );
        const object = created.rows[0];
        await this.recordChange(
          client,
          userId,
          object.id,
          objectType,
          'upsert',
          object.server_version,
          object.payload,
        );
        return { id: object.id, changed: true };
      }

      const updated = await client.query<{
        id: string;
        server_version: number;
        payload: Record<string, unknown>;
      }>(
        `
        UPDATE sync_objects
        SET
          payload = $4::jsonb,
          deleted_at = NULL,
          server_version = server_version + 1,
          updated_at = now()
        WHERE user_id = $1
          AND object_type = $2
          AND uid = $3
          AND (payload IS DISTINCT FROM $4::jsonb OR deleted_at IS NOT NULL)
        RETURNING id::text, server_version, payload
        `,
        [userId, objectType, uid, JSON.stringify(payload)],
      );
      const object = updated.rows[0];
      if (!object) {
        return { id: existing.rows[0].id, changed: false };
      }
      await this.recordChange(
        client,
        userId,
        object.id,
        objectType,
        'upsert',
        object.server_version,
        object.payload,
      );
      return { id: object.id, changed: true };
    });
  }

  private async deleteSyncObject(
    userId: string,
    objectType: 'calendar_book' | 'calendar_event',
    uid: string,
  ) {
    const result = await this.database.transaction(async (client) => {
      const deleted = await client.query<{
        id: string;
        server_version: number;
        payload: Record<string, unknown>;
      }>(
        `
        UPDATE sync_objects
        SET deleted_at = now(), server_version = server_version + 1, updated_at = now()
        WHERE user_id = $1
          AND object_type = $2
          AND uid = $3
          AND deleted_at IS NULL
        RETURNING id::text, server_version, payload
        `,
        [userId, objectType, uid],
      );
      const object = deleted.rows[0];
      if (!object) {
        return false;
      }
      await this.recordChange(
        client,
        userId,
        object.id,
        objectType,
        'delete',
        object.server_version,
        object.payload,
      );
      return true;
    });
    return result;
  }

  private recordChange(
    client: TransactionClient,
    userId: string,
    serverObjectId: string,
    objectType: string,
    action: 'upsert' | 'delete',
    serverVersion: number,
    payload: Record<string, unknown>,
  ) {
    return client.query(
      `
      INSERT INTO sync_changes (
        user_id, device_id, server_object_id, object_type, action, server_version, payload
      ) VALUES ($1, NULL, $2, $3, $4, $5, $6::jsonb)
      `,
      [userId, serverObjectId, objectType, action, serverVersion, JSON.stringify(payload)],
    );
  }

  private upsertMapping(
    userId: string,
    flowType: string,
    flowId: string,
    outlookType: string,
    outlookId: string,
    calendarId: string | null,
    etag: string | null,
  ) {
    return this.database.query(
      `
      INSERT INTO outlook_object_mappings (
        user_id, flowplanv2_object_type, flowplanv2_object_id,
        outlook_object_type, outlook_object_id, outlook_calendar_id,
        last_synced_at, sync_state, last_remote_etag, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, now(), 'synced', $7, now())
      ON CONFLICT (user_id, outlook_object_type, outlook_object_id) DO UPDATE SET
        flowplanv2_object_type = EXCLUDED.flowplanv2_object_type,
        flowplanv2_object_id = EXCLUDED.flowplanv2_object_id,
        outlook_calendar_id = EXCLUDED.outlook_calendar_id,
        last_synced_at = now(),
        sync_state = 'synced',
        last_remote_etag = EXCLUDED.last_remote_etag,
        updated_at = now()
      `,
      [userId, flowType, flowId, outlookType, outlookId, calendarId, etag],
    );
  }

  private async getConnection(userId: string) {
    const result = await this.database.query<OutlookConnectionRow>(
      'SELECT * FROM outlook_connections WHERE user_id = $1 LIMIT 1',
      [userId],
    );
    return result.rows[0] ?? null;
  }

  private async ensureAccessToken(connection: OutlookConnectionRow) {
    if (!(await this.hasTokenSecret(connection.user_id))) {
      throw new Error('Outlook token secret is required');
    }
    const expiresAt = connection.access_token_expires_at
      ? new Date(connection.access_token_expires_at).getTime()
      : 0;
    if (connection.access_token_encrypted && expiresAt > Date.now() + 120_000) {
      return this.decrypt(connection.access_token_encrypted);
    }
    if (!connection.refresh_token_encrypted) {
      throw new Error('Outlook refresh token is missing');
    }
    const refreshed = await this.refreshToken(
      connection.client_id,
      connection.redirect_uri,
      connection.scope,
      this.decrypt(connection.refresh_token_encrypted),
    );
    const expires = new Date(Date.now() + Number(refreshed.expires_in ?? 3600) * 1000);
    await this.database.query(
      `
      UPDATE outlook_connections
      SET
        access_token_encrypted = $2,
        refresh_token_encrypted = COALESCE($3, refresh_token_encrypted),
        access_token_expires_at = $4,
        updated_at = now()
      WHERE user_id = $1
      `,
      [
        connection.user_id,
        this.encrypt(refreshed.access_token),
        refreshed.refresh_token ? this.encrypt(refreshed.refresh_token) : null,
        expires,
      ],
    );
    return refreshed.access_token;
  }

  private async fetchCalendars(accessToken: string) {
    const calendars: OutlookCalendar[] = [];
    let url = `${GRAPH_BASE}/me/calendars?$top=200&$select=id,name,color,hexColor,isDefaultCalendar`;
    while (url) {
      const page = await this.graphGet<{
        value?: OutlookCalendar[];
        '@odata.nextLink'?: string;
      }>(url, accessToken);
      calendars.push(...(page.value ?? []).filter((calendar) => Boolean(calendar.id)));
      url = page['@odata.nextLink'] ?? '';
    }
    return calendars;
  }

  private async graphGet<T>(
    pathOrUrl: string,
    accessToken: string,
    preferValues: string[] = [],
  ): Promise<T> {
    const url = pathOrUrl.startsWith('https://')
      ? pathOrUrl
      : `${GRAPH_BASE}${pathOrUrl}`;
    if (!url.startsWith(`${GRAPH_BASE}/`)) {
      throw new Error('Only Microsoft Graph v1.0 GET requests are allowed');
    }
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
        Prefer: this.graphPreferHeader(preferValues),
      },
    });
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Outlook Graph GET failed (${response.status}): ${body}`);
    }
    return (await response.json()) as T;
  }

  private graphPreferHeader(preferValues: string[]) {
    return Array.from(
      new Set([...preferValues, 'outlook.timezone="UTC"'].filter(Boolean)),
    ).join(', ');
  }

  private async exchangeCode(
    clientId: string,
    redirectUri: string,
    scope: string,
    code: string,
    codeVerifier: string,
  ) {
    return this.tokenRequest({
      client_id: clientId,
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      scope,
      code_verifier: codeVerifier,
    });
  }

  private async refreshToken(
    clientId: string,
    redirectUri: string,
    scope: string,
    refreshToken: string,
  ) {
    return this.tokenRequest({
      client_id: clientId,
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      redirect_uri: redirectUri,
      scope,
    });
  }

  private async tokenRequest(params: Record<string, string>) {
    const response = await fetch(`${AUTHORITY}/oauth2/v2.0/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(params),
    });
    const body = (await response.json()) as Record<string, unknown>;
    if (!response.ok) {
      throw new Error(
        `Outlook OAuth token request failed (${response.status}): ${JSON.stringify(body)}`,
      );
    }
    if (!this.cleanString(body.access_token)) {
      throw new Error('Outlook OAuth response did not include an access token');
    }
    return body as {
      access_token: string;
      refresh_token?: string;
      expires_in?: number;
    };
  }

  private readAuthCompletion(body: Record<string, unknown>) {
    const callbackUrl = this.cleanString(body.callbackUrl);
    if (callbackUrl) {
      let url: URL;
      try {
        url = new URL(callbackUrl);
      } catch {
        throw new BadRequestException(
          'Outlook callbackUrl must be the full Microsoft redirect URL.',
        );
      }
      const code = url.searchParams.get('code') ?? '';
      const state = url.searchParams.get('state') ?? '';
      if (!code || !state) {
        throw new BadRequestException(
          'Outlook callbackUrl must include both code and state query parameters.',
        );
      }
      return {
        code,
        state,
      };
    }
    const parsed = {
      code: this.cleanString(body.code) ?? '',
      state: this.cleanString(body.state) ?? '',
    };
    if (!parsed.code || !parsed.state) {
      throw new BadRequestException(
        'Outlook authorization completion requires callbackUrl or both code and state.',
      );
    }
    return parsed;
  }

  private async countCalendars(userId: string) {
    const result = await this.database.query<{ count: number }>(
      `
      SELECT count(*)::int AS count
      FROM outlook_calendar_states
      WHERE user_id = $1
      `,
      [userId],
    );
    return result.rows[0]?.count ?? 0;
  }

  private async latestRun(userId: string) {
    const result = await this.database.query<{
      id: string;
      triggerSource: string;
      status: string;
      startedAt: Date;
      finishedAt: Date | null;
      calendarCount: number;
      eventUpserts: number;
      eventDeletes: number;
      errorMessage: string | null;
    }>(
      `
      SELECT
        id::text,
        trigger_source AS "triggerSource",
        status,
        started_at AS "startedAt",
        finished_at AS "finishedAt",
        calendar_count AS "calendarCount",
        event_upserts AS "eventUpserts",
        event_deletes AS "eventDeletes",
        error_message AS "errorMessage"
      FROM outlook_sync_runs
      WHERE user_id = $1
      ORDER BY started_at DESC
      LIMIT 1
      `,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  private calendarUid(remoteCalendarId: string) {
    return `outlook_calendar:${remoteCalendarId}`;
  }

  private eventUid(remoteCalendarId: string, remoteEventId: string) {
    return `outlook_event:${remoteCalendarId}:${remoteEventId}`;
  }

  private calendarColor(calendar: OutlookCalendar) {
    return calendar.hexColor ?? '#2563eb';
  }

  private outlookDateTime(value?: { dateTime?: string; timeZone?: string }) {
    if (!value?.dateTime) {
      return null;
    }
    const normalized = value.dateTime.endsWith('Z')
      ? value.dateTime
      : `${value.dateTime}Z`;
    const date = new Date(normalized);
    return Number.isNaN(date.getTime()) ? value.dateTime : date.toISOString();
  }

  private cleanString(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : null;
  }

  private iso(value: Date | string | null | undefined) {
    if (!value) {
      return null;
    }
    const date = value instanceof Date ? value : new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  private base64Url(input: Buffer) {
    return input
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/g, '');
  }

  private tokenKey() {
    const secret = process.env.FLOWPLANV2_OUTLOOK_TOKEN_SECRET;
    if (!secret) {
      throw new Error('Outlook token secret is required');
    }
    return createHash('sha256').update(secret).digest();
  }

  private async hasTokenSecret(userId: string) {
    return (await this.tokenSecretStatus(userId)).configured;
  }

  private async tokenSecretStatus(userId: string) {
    if (process.env.FLOWPLANV2_OUTLOOK_TOKEN_SECRET) {
      return { configured: true, source: 'environment' };
    }
    const result = await this.database.query<{ config_value: Record<string, unknown> }>(
      `
      SELECT config_value
      FROM admin_remote_configs
      WHERE user_id = $1 AND config_key = 'outlook.token_secret'
      LIMIT 1
      `,
      [userId],
    );
    const secret = this.cleanString(result.rows[0]?.config_value?.secret);
    if (!secret) {
      return { configured: false, source: 'missing' };
    }
    process.env.FLOWPLANV2_OUTLOOK_TOKEN_SECRET = secret;
    return { configured: true, source: 'admin_panel' };
  }

  private encrypt(value: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.tokenKey(), iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [iv, tag, encrypted].map((part) => this.base64Url(part)).join('.');
  }

  private decrypt(value: string) {
    const [ivRaw, tagRaw, encryptedRaw] = value.split('.');
    if (!ivRaw || !tagRaw || !encryptedRaw) {
      throw new Error('Encrypted Outlook token is malformed');
    }
    const iv = Buffer.from(ivRaw, 'base64url');
    const tag = Buffer.from(tagRaw, 'base64url');
    const encrypted = Buffer.from(encryptedRaw, 'base64url');
    const decipher = createDecipheriv('aes-256-gcm', this.tokenKey(), iv);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(encrypted), decipher.final()]).toString(
      'utf8',
    );
  }
}
