import 'reflect-metadata';
import { describe, expect, it } from 'vitest';
import { validate } from 'class-validator';
import { AppendChunkDto, CompleteBatchDto, CreateBatchDto } from './tracking.dto';

describe('tracking DTO validation', () => {
  it('accepts optional create batch fields and records arrays', async () => {
    const dto = Object.assign(new CreateBatchDto(), {
      batchUid: 'batch-1',
      dataKind: 'activity',
      compression: 'none',
      payloadHash: 'sha256',
      startAt: '2026-06-08T00:00:00Z',
      endAt: '2026-06-08T01:00:00Z',
      records: [{ appName: 'Code' }],
      metadata: { source: 'test' },
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('rejects non-string create batch fields and non-array records', async () => {
    const dto = Object.assign(new CreateBatchDto(), {
      batchUid: 1,
      dataKind: 2,
      compression: 3,
      payloadHash: 4,
      startAt: 5,
      endAt: 6,
      records: {},
    });

    const errors = await validate(dto);

    expect(errors.map((error) => error.property).sort()).toEqual([
      'batchUid',
      'compression',
      'dataKind',
      'endAt',
      'payloadHash',
      'records',
      'startAt',
    ]);
  });

  it('validates append chunk indexes and optional checksums', async () => {
    await expect(
      validate(
        Object.assign(new AppendChunkDto(), {
          chunkIndex: 0,
          payload: { rows: [] },
          payloadBase64: 'W10=',
          checksum: 'sha256',
        }),
      ),
    ).resolves.toHaveLength(0);

    const errors = await validate(
      Object.assign(new AppendChunkDto(), {
        chunkIndex: '0',
        payloadBase64: 123,
        checksum: 456,
      }),
    );

    expect(errors.map((error) => error.property).sort()).toEqual([
      'checksum',
      'chunkIndex',
      'payloadBase64',
    ]);
  });

  it('validates complete batch records as an optional array', async () => {
    await expect(
      validate(Object.assign(new CompleteBatchDto(), { records: [{ id: 'record-1' }] })),
    ).resolves.toHaveLength(0);

    const errors = await validate(Object.assign(new CompleteBatchDto(), { records: {} }));

    expect(errors.map((error) => error.property)).toEqual(['records']);
  });
});
