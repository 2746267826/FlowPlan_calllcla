import { describe, expect, it } from 'vitest';
import {
  readInt,
  readLimit,
  readNullableNumber,
  readNumber,
  readOffset,
  toNumber,
} from './numbers';

describe('number utilities', () => {
  it('reads finite numbers or falls back', () => {
    expect(readNumber('42.5', 1)).toBe(42.5);
    expect(readNumber(Number.POSITIVE_INFINITY, 7)).toBe(7);
    expect(readNumber('nope', 3)).toBe(3);
  });

  it('truncates and clamps integer values', () => {
    expect(readInt('9.8', 1, 0, 10)).toBe(9);
    expect(readInt('-4', 1, 0, 10)).toBe(0);
    expect(readInt('40', 1, 0, 10)).toBe(10);
    expect(readInt('bad', 6, 0, 10)).toBe(6);
  });

  it('reads nullable non-negative integers', () => {
    expect(readNullableNumber('12.9')).toBe(12);
    expect(readNullableNumber('-2')).toBe(0);
    expect(readNullableNumber(undefined)).toBeNull();
  });

  it('normalizes pagination limits and offsets', () => {
    expect(readLimit('0', 20)).toBe(1);
    expect(readLimit('999', 20, 1, 100)).toBe(100);
    expect(readOffset('-10')).toBe(0);
    expect(readOffset('12.9')).toBe(12);
  });

  it('coerces supported values to finite numbers', () => {
    expect(toNumber(3.5)).toBe(3.5);
    expect(toNumber('8')).toBe(8);
    expect(toNumber(Number.NaN)).toBe(0);
    expect(toNumber({})).toBe(0);
  });
});
