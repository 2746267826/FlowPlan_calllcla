export interface FlowPlanRequestContext {
  userId: string;
  deviceId: string;
}

export function readRequestContext(headers: Record<string, unknown>) {
  const rawUserId = readHeader(headers, 'x-flowplan-user-id');
  const rawDeviceId = readHeader(headers, 'x-flowplan-device-id');
  const userId = isUuid(rawUserId)
    ? rawUserId
    : '00000000-0000-4000-8000-000000000001';
  const deviceId = isUuid(rawDeviceId)
    ? rawDeviceId
    : '00000000-0000-4000-8000-000000000101';
  return { userId, deviceId };
}

function readHeader(headers: Record<string, unknown>, key: string) {
  const value = headers[key] ?? headers[key.toLowerCase()];
  if (Array.isArray(value)) {
    return value[0];
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    return value.trim();
  }
  return undefined;
}

function isUuid(value: string | undefined): value is string {
  return !!value &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
}
