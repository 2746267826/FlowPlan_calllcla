import 'reflect-metadata';
import { validate } from 'class-validator';
import { describe, expect, it } from 'vitest';
import { LoginDto, LogoutDto, RefreshDto } from './auth.dto';

describe('auth DTO validation', () => {
  it('accepts optional login identity fields when they are well formed', async () => {
    const dto = Object.assign(new LoginDto(), {
      userId: '11111111-1111-4111-8111-111111111111',
      displayName: 'Desktop user',
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
    await expect(validate(new LoginDto())).resolves.toHaveLength(0);
  });

  it('rejects login identity fields with invalid runtime types', async () => {
    const dto = Object.assign(new LoginDto(), {
      userId: 'not-a-uuid',
      displayName: 123,
    });

    const errors = await validate(dto);

    expect(errors.map((error) => error.property).sort()).toEqual([
      'displayName',
      'userId',
    ]);
  });

  it('requires refresh tokens to be strings', async () => {
    await expect(
      validate(Object.assign(new RefreshDto(), { refreshToken: 'refresh-token' })),
    ).resolves.toHaveLength(0);

    const errors = await validate(
      Object.assign(new RefreshDto(), { refreshToken: 42 }),
    );

    expect(errors.map((error) => error.property)).toEqual(['refreshToken']);
  });

  it('allows logout without a token but rejects non-string tokens', async () => {
    await expect(validate(new LogoutDto())).resolves.toHaveLength(0);
    await expect(
      validate(Object.assign(new LogoutDto(), { refreshToken: 'refresh-token' })),
    ).resolves.toHaveLength(0);

    const errors = await validate(
      Object.assign(new LogoutDto(), { refreshToken: false }),
    );

    expect(errors.map((error) => error.property)).toEqual(['refreshToken']);
  });
});
