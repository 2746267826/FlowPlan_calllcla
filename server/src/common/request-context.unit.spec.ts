import { describe, expect, it } from 'vitest';
import { readRequestContext } from './request-context';

describe('readRequestContext', () => {
  it('trims valid user and device headers', () => {
    expect(
      readRequestContext({
        'x-flowplanv2-user-id': ' 11111111-1111-4111-8111-111111111111 ',
        'x-flowplanv2-device-id': ' 22222222-2222-4222-8222-222222222222 ',
      }),
    ).toEqual({
      userId: '11111111-1111-4111-8111-111111111111',
      deviceId: '22222222-2222-4222-8222-222222222222',
    });
  });

  it('uses the first array header value and defaults invalid values independently', () => {
    expect(
      readRequestContext({
        'x-flowplanv2-user-id': ['33333333-3333-4333-8333-333333333333'],
        'x-flowplanv2-device-id': ['not-a-uuid'],
      }),
    ).toEqual({
      userId: '33333333-3333-4333-8333-333333333333',
      deviceId: '00000000-0000-4000-8000-000000000101',
    });
  });

  it('falls back to stable defaults when headers are absent or blank', () => {
    expect(
      readRequestContext({
        'x-flowplanv2-user-id': ' ',
      }),
    ).toEqual({
      userId: '00000000-0000-4000-8000-000000000001',
      deviceId: '00000000-0000-4000-8000-000000000101',
    });
  });
});
