import 'reflect-metadata';
import { describe, expect, it } from 'vitest';
import { validate } from 'class-validator';
import { GenerateReportDto, PolishReportDto } from './reports.dto';

describe('reports DTO validation', () => {
  it('accepts complete generate report input with optional bounds and LLM flag', async () => {
    const dto = Object.assign(new GenerateReportDto(), {
      reportType: 'daily',
      date: '2026-06-08',
      start: '2026-06-08T00:00:00Z',
      end: '2026-06-09T00:00:00Z',
      useLlm: true,
      locationId: 'weather-1',
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('rejects missing report type and non-string optional fields', async () => {
    const dto = Object.assign(new GenerateReportDto(), {
      date: 20260608,
      start: 1,
      end: {},
      useLlm: 'true',
      locationId: 42,
    });

    const errors = await validate(dto);

    expect(errors.map((error) => error.property).sort()).toEqual([
      'date',
      'end',
      'locationId',
      'reportType',
      'start',
      'useLlm',
    ]);
  });

  it('accepts optional polish prompts and rejects non-string prompts', async () => {
    await expect(validate(new PolishReportDto())).resolves.toHaveLength(0);
    await expect(
      validate(Object.assign(new PolishReportDto(), { prompt: 'make it concise' })),
    ).resolves.toHaveLength(0);

    const errors = await validate(Object.assign(new PolishReportDto(), { prompt: 123 }));

    expect(errors.map((error) => error.property)).toEqual(['prompt']);
  });
});
