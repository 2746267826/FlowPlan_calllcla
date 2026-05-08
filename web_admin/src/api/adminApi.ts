import { defaultApiBase } from '../app/constants';
import type { AdminContext, ApiRecord, DatasetDomain } from '../types';
import { extractRows } from '../utils/format';

export class AdminApiClient {
  constructor(private readonly context: AdminContext) {}

  async request<T>(path: string, options: RequestInit = {}): Promise<T> {
    const headers = new Headers(options.headers);
    if (!headers.has('content-type') && options.body) {
      headers.set('content-type', 'application/json');
    }
    headers.set('authorization', `Bearer ${this.context.accessToken}`);
    headers.set('x-flowplanv2-device-id', this.context.deviceId);
    headers.set('x-flowplanv2-platform', 'web-admin');

    const response = await fetch(buildApiUrl(this.context.apiBase, path), {
      ...options,
      headers,
    });

    // Token expired — caller should refresh and retry
    if (response.status === 401) {
      throw new TokenExpiredError('Access token expired');
    }

    const text = await response.text();
    if (!response.ok) {
      throw new Error(formatHttpError(response, text));
    }
    return parseApiResponse<T>(text);
  }

  // ---- Auth ----

  async login(displayName?: string) {
    return this.requestUnauthed<{
      accessToken: string;
      refreshToken: string;
      user: { id: string; displayName: string };
    }>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ displayName: displayName ?? 'FlowPlanV2 Admin' }),
    });
  }

  async refreshToken(refreshToken: string) {
    return this.requestUnauthed<{
      accessToken: string;
      refreshToken: string;
      user: { id: string; displayName: string };
    }>('/api/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refreshToken }),
    });
  }

  // ---- Data ----

  health() {
    return this.requestUnauthed<ApiRecord>('/api/health');
  }

  dashboard() {
    return this.request<ApiRecord>('/api/admin/dashboard');
  }

  monitoringHealth() {
    return this.request<ApiRecord>('/api/admin/monitoring/health');
  }

  syncHealth() {
    return this.request<ApiRecord>('/api/admin/sync-health');
  }

  deviceOnlineSummary(deviceId?: string) {
    const search = new URLSearchParams();
    if (deviceId && deviceId !== 'all') search.set('deviceId', deviceId);
    const suffix = search.toString() ? `?${search.toString()}` : '';
    return this.request<ApiRecord>(`/api/admin/devices/online-summary${suffix}`);
  }

  deviceConnectionHistory(deviceId: string) {
    return this.request<ApiRecord>(
      `/api/admin/devices/${encodeURIComponent(deviceId)}/connection-history`,
    );
  }

  adminData(
    domain: DatasetDomain | string,
    query: Record<string, string | number | undefined> = {},
  ) {
    const search = new URLSearchParams();
    Object.entries(query).forEach(([key, value]) => {
      if (value !== undefined && value !== '') search.set(key, String(value));
    });
    const suffix = search.toString() ? `?${search.toString()}` : '';
    return this.request<unknown>(`/api/admin/data/${domain}${suffix}`);
  }

  adminRows(
    domain: DatasetDomain | string,
    query: Record<string, string | number | undefined> = {},
  ) {
    return this.adminData(domain, query).then(extractRows);
  }

  adminDataDetail(domain: DatasetDomain | string, id: string) {
    return this.request<unknown>(
      `/api/admin/data/${domain}/${encodeURIComponent(id)}`,
    );
  }

  patchAdminData(
    domain: DatasetDomain | string,
    id: string,
    body: ApiRecord,
  ) {
    return this.request<ApiRecord>(
      `/api/admin/data/${domain}/${encodeURIComponent(id)}`,
      { method: 'PATCH', body: JSON.stringify(body) },
    );
  }

  driveRoots(query?: string) {
    const search = new URLSearchParams();
    if (query?.trim()) search.set('q', query.trim());
    const suffix = search.toString() ? `?${search.toString()}` : '';
    return this.request<ApiRecord>(`/api/files/drive/roots${suffix}`);
  }

  upsertDriveRoot(body: {
    name: string;
    rootUri: string;
    rootDisplayPath?: string;
    syncPolicy?: string;
  }) {
    return this.request<ApiRecord>('/api/files/roots', {
      method: 'POST',
      body: JSON.stringify({
        name: body.name,
        rootUri: body.rootUri,
        rootDisplayPath: body.rootDisplayPath,
        providerType: 'server_storage',
        isManaged: true,
        syncPolicy: body.syncPolicy ?? 'metadata_only',
        metadata: { source: 'web_admin_drive_root' },
      }),
    });
  }

  scanDriveRoot(rootId: string) {
    return this.request<ApiRecord>(
      `/api/files/drive/roots/${encodeURIComponent(rootId)}/scan`,
      { method: 'POST', body: JSON.stringify({}) },
    );
  }

  deleteDriveRoot(rootId: string) {
    return this.request<ApiRecord>(
      `/api/files/drive/roots/${encodeURIComponent(rootId)}`,
      { method: 'DELETE' },
    );
  }

  settings() {
    return this.request<ApiRecord>('/api/admin/settings');
  }

  patchSetting(configKey: string, body: ApiRecord) {
    return this.request<ApiRecord>(
      `/api/admin/settings/${encodeURIComponent(configKey)}`,
      { method: 'PATCH', body: JSON.stringify(body) },
    );
  }

  outlookStatus() {
    return this.request<ApiRecord>('/api/admin/outlook/status');
  }

  outlookCalendars() {
    return this.request<ApiRecord>('/api/admin/outlook/calendars');
  }

  outlookRuns() {
    return this.request<ApiRecord>('/api/admin/outlook/runs');
  }

  outlookDiagnostics() {
    return this.request<ApiRecord>('/api/admin/outlook/diagnostics');
  }

  startOutlookAuth(clientId: string) {
    return this.request<ApiRecord>('/api/admin/outlook/auth/start', {
      method: 'POST',
      body: JSON.stringify({ clientId }),
    });
  }

  completeOutlookAuth(callbackUrl: string, state?: unknown) {
    return this.request<ApiRecord>('/api/admin/outlook/auth/complete', {
      method: 'POST',
      body: JSON.stringify({ callbackUrl, state }),
    });
  }

  saveOutlookTokenSecret(secret: string, confirmRotation: boolean) {
    return this.request<ApiRecord>('/api/admin/outlook/token-secret', {
      method: 'POST',
      body: JSON.stringify({ secret, confirmRotation }),
    });
  }

  syncOutlook() {
    return this.request<ApiRecord>('/api/admin/outlook/sync', {
      method: 'POST',
    });
  }

  resetOutlook() {
    return this.request<ApiRecord>('/api/admin/outlook/reset', {
      method: 'POST',
    });
  }

  prepareOperation(operationKey: string, payload: unknown) {
    return this.request<ApiRecord>(
      `/api/admin/operations/${encodeURIComponent(operationKey)}/prepare`,
      {
        method: 'POST',
        body: JSON.stringify({ payload, reason: 'web_admin prepare' }),
      },
    );
  }

  confirmOperation(
    operationKey: string,
    payload: unknown,
    confirmationToken: string,
  ) {
    return this.request<ApiRecord>(
      `/api/admin/operations/${encodeURIComponent(operationKey)}/confirm`,
      {
        method: 'POST',
        body: JSON.stringify({
          payload,
          confirmationToken,
          reason: 'web_admin confirm',
        }),
      },
    );
  }

  // ---- internal ----

  /** Call an endpoint that does NOT require auth (login, refresh, health). */
  private async requestUnauthed<T>(
    path: string,
    options: RequestInit = {},
  ): Promise<T> {
    const headers = new Headers(options.headers);
    if (!headers.has('content-type') && options.body) {
      headers.set('content-type', 'application/json');
    }
    // Send device context even for unauthenticated requests
    headers.set('x-flowplanv2-device-id', this.context.deviceId);
    headers.set('x-flowplanv2-platform', 'web-admin');

    const response = await fetch(buildApiUrl(this.context.apiBase, path), {
      ...options,
      headers,
    });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(formatHttpError(response, text));
    }
    return parseApiResponse<T>(text);
  }
}

export class TokenExpiredError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TokenExpiredError';
  }
}

export function normalizeApiBase(value: string): string {
  const trimmed = value.trim().replace(/\/+$/, '');
  if (!trimmed) return defaultApiBase;
  try {
    const url = new URL(trimmed);
    if (url.pathname === '/api') {
      url.pathname = '';
    } else if (url.pathname.endsWith('/api')) {
      url.pathname = url.pathname.slice(0, -4);
    }
    url.search = '';
    url.hash = '';
    return url.toString().replace(/\/$/, '');
  } catch {
    return trimmed;
  }
}

export function buildApiUrl(apiBase: string, path: string): string {
  if (path.startsWith('http')) return path;
  const base = normalizeApiBase(apiBase);
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${base}${normalizedPath}`;
}

function formatHttpError(response: Response, text: string): string {
  const detail = extractErrorDetail(text);
  const status = `${response.status} ${response.statusText}`.trim();
  return detail ? `${status}: ${detail}` : status;
}

function extractErrorDetail(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return '';
  try {
    const parsed = JSON.parse(trimmed) as ApiRecord;
    const message = parsed.message;
    if (Array.isArray(message)) return message.join('; ');
    if (typeof message === 'string') return message;
    if (typeof parsed.error === 'string') return parsed.error;
    return JSON.stringify(parsed);
  } catch {
    return trimmed;
  }
}

function parseApiResponse<T>(text: string): T {
  const trimmed = text.trim();
  if (!trimmed) return {} as T;
  try {
    return JSON.parse(trimmed) as T;
  } catch {
    throw new Error(
      `服务端返回了非 JSON 响应：${trimmed.slice(0, 200)}`,
    );
  }
}
