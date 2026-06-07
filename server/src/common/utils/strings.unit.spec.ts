import { describe, expect, it } from 'vitest';
import { asString, basename, clean, searchPattern, summarize, truncate } from './strings';

describe('string utilities', () => {
  it('trims non-empty strings and rejects blanks', () => {
    expect(clean('  Inbox  ')).toBe('Inbox');
    expect(clean('   ')).toBeNull();
    expect(clean(123)).toBeNull();
    expect(asString('  Device  ')).toBe('Device');
    expect(asString('')).toBeUndefined();
  });

  it('truncates and summarizes long content', () => {
    expect(truncate('short', 10)).toBe('short');
    expect(truncate('abcdefghij', 4)).toBe('abcd...');
    expect(summarize('  A   B \n C  ', 10)).toBe('A B C');
    expect(summarize('abcdefghijklmnopqrstuvwxyz', 5)).toBe('abcde...');
  });

  it('extracts path basenames across separators', () => {
    expect(basename('/tmp/flow/file.txt')).toBe('file.txt');
    expect(basename('C:\\Users\\flow\\file.txt')).toBe('file.txt');
    expect(basename('')).toBe('');
  });

  it('builds SQL search patterns only for non-blank queries', () => {
    expect(searchPattern('  task  ')).toBe('%task%');
    expect(searchPattern('   ')).toBeNull();
    expect(searchPattern(undefined)).toBeNull();
  });
});
