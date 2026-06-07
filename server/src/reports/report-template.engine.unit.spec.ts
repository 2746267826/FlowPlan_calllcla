import { describe, it, expect } from 'vitest';
import { ReportTemplateEngine } from './report-template.engine';

describe('ReportTemplateEngine', () => {
  const engine = new ReportTemplateEngine();

  it('substitutes simple variables', () => {
    const result = engine.render('Hello {{name}}!', { name: 'World' });
    expect(result).toBe('Hello World!');
  });

  it('resolves nested dot-path variables', () => {
    const result = engine.render('{{user.name}}', { user: { name: 'Alice' } });
    expect(result).toBe('Alice');
  });

  it('shows content when #if is truthy', () => {
    const result = engine.render('{{#if hasData}}yes{{/if}}', { hasData: true });
    expect(result).toBe('yes');
  });

  it('hides content when #if is falsy', () => {
    const result = engine.render('{{#if hasData}}yes{{/if}}', { hasData: false });
    expect(result).toBe('');
  });

  it('loops over array with #each', () => {
    const result = engine.render(
      '{{#each items}}- {{title}}\n{{/each}}',
      { items: [{ title: 'A' }, { title: 'B' }] },
    );
    expect(result).toContain('- A');
    expect(result).toContain('- B');
  });

  it('uses @index in #each', () => {
    const result = engine.render(
      '{{#each items}}{{@index}}:{{title}} {{/each}}',
      { items: [{ title: 'X' }] },
    );
    expect(result).toContain('0:X');
  });

  it('combines #if inside #each', () => {
    const result = engine.render(
      '{{#each items}}{{title}}{{#if done}}✓{{/if}} {{/each}}',
      { items: [{ title: 'A', done: true }, { title: 'B', done: false }] },
    );
    expect(result).toContain('A✓');
    expect(result).toContain('B ');
  });

  it('returns empty for empty array', () => {
    const result = engine.render('{{#each items}}x{{/each}}', { items: [] });
    expect(result).toBe('');
  });
});
