import { describe, expect, it } from 'vitest';
import { TfidfMatcher } from './tfidf';

describe('TfidfMatcher', () => {
  it('returns no matches when the index or query has no terms', () => {
    const matcher = new TfidfMatcher();

    expect(matcher.bestMatch('calendar planning')).toBeNull();
    expect(matcher.matches('calendar planning')).toEqual([]);

    matcher.addDocument('blank', '   ');

    expect(matcher.size).toBe(0);
    expect(matcher.bestMatch('   ')).toBeNull();
    expect(matcher.matches('   ')).toEqual([]);
  });

  it('selects the indexed document with the strongest term overlap', () => {
    const matcher = new TfidfMatcher();

    matcher.addDocument('task-calendar', 'calendar planning schedule timeline');
    matcher.addDocument('task-files', 'file upload transfer storage');

    expect(matcher.bestMatch('a')).toBeNull();
    expect(matcher.matches('a')).toEqual([]);

    const best = matcher.bestMatch('weekly calendar schedule review');

    expect(best).not.toBeNull();
    expect(best?.id).toBe('task-calendar');
    expect(best?.score).toBeGreaterThan(0);

    expect(matcher.bestMatch('unindexed-term-only')).toEqual({
      id: 'task-calendar',
      score: 0,
    });
  });

  it('indexes CJK bigrams so adjacent Chinese terms can match across separators', () => {
    const matcher = new TfidfMatcher();

    matcher.addDocument('machine-learning', '机械 学习');
    matcher.addDocument('calendar-review', '日程 复盘');

    expect(matcher.bestMatch('械学')?.id).toBe('machine-learning');
  });

  it('returns matches sorted by descending score and applies thresholds', () => {
    const matcher = new TfidfMatcher();

    matcher.addDocument('primary', 'focus focus schedule');
    matcher.addDocument('secondary', 'focus notes');
    matcher.addDocument('unrelated', 'archive storage');

    const matches = matcher.matches('focus schedule', 0.01);

    expect(matches.map((match) => match.id)).toEqual(['primary', 'secondary']);
    expect(matches[0].score).toBeGreaterThan(matches[1].score);
    expect(matcher.matches('focus schedule', matches[0].score + 0.01)).toEqual([]);
  });

  it('clears indexed documents and document frequencies on reset', () => {
    const matcher = new TfidfMatcher();

    matcher.addDocument('before-reset', 'daily focus plan');
    expect(matcher.size).toBe(1);
    expect(matcher.bestMatch('focus')?.id).toBe('before-reset');

    matcher.reset();

    expect(matcher.size).toBe(0);
    expect(matcher.bestMatch('focus')).toBeNull();
    expect(matcher.matches('focus')).toEqual([]);
  });
});
