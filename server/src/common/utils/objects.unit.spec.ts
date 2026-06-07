import { describe, expect, it } from 'vitest';
import { asArray, asRecord, deepClone, pick } from './objects';

describe('object utilities', () => {
  it('casts only plain object values to records', () => {
    expect(asRecord({ id: 'task-1' })).toEqual({ id: 'task-1' });
    expect(asRecord(null)).toEqual({});
    expect(asRecord(['not', 'record'])).toEqual({});
  });

  it('casts arrays without accepting other values', () => {
    expect(asArray(['a'])).toEqual(['a']);
    expect(asArray({ 0: 'a' })).toEqual([]);
  });

  it('deep clones JSON-serializable values', () => {
    const original = { nested: { title: 'Task' } };
    const copy = deepClone(original);

    copy.nested.title = 'Changed';

    expect(original.nested.title).toBe('Task');
    expect(copy.nested.title).toBe('Changed');
  });

  it('picks requested keys without mutating the source object', () => {
    const source = { id: 'task-1', title: 'Task', ignored: true };

    expect(pick(source, ['id', 'title', 'missing'])).toEqual({
      id: 'task-1',
      title: 'Task',
    });
    expect(source).toEqual({ id: 'task-1', title: 'Task', ignored: true });
  });
});
