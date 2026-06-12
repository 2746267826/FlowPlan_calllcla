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

  it.each([
    ['object', { items: { title: 'A' } }],
    ['string', { items: 'not-array' }],
    ['null', { items: null }],
    ['undefined', {}],
  ])('returns empty when #each receives a non-array %s value', (_, context) => {
    const result = engine.render('before{{#each items}}x{{/each}}after', context);
    expect(result).toBe('beforeafter');
  });

  it('keeps primitive #each items unavailable while resolving loop metadata', () => {
    const result = engine.render(
      '{{#each items}}[{{@index}}|{{item}}|{{value}}|{{@key}}|{{@missing}}]{{/each}}',
      { items: ['alpha', 42, true, null] },
    );

    expect(result).toBe('[0||||][1||||][2||||][3||||]');
  });

  it('evaluates nested #if blocks inside #each with loop indexes and nested paths', () => {
    const result = engine.render(
      '{{#each items}}{{#if enabled}}{{@index}}={{details.label}};{{/if}}{{/each}}',
      {
        items: [
          { enabled: true, details: { label: 'Alpha' } },
          { enabled: false, details: { label: 'Beta' } },
          { enabled: null, details: { label: 'Gamma' } },
          { enabled: 0, details: { label: 'Delta' } },
        ],
      },
    );

    expect(result).toBe('0=Alpha;3=Delta;');
  });

  it('resolves top-level #if nested dot paths and key truthiness cases', () => {
    const result = engine.render(
      [
        '{{#if user.profile.active}}nested={{user.profile.name}}{{/if}}',
        '{{#if user.profile.active}}missing={{user.profile.missing}}{{/if}}',
        '{{#if empty}}empty{{/if}}',
        '{{#if zero}}zero{{/if}}',
        '{{#if boolFalse}}false{{/if}}',
        '{{#if nil}}nil{{/if}}',
        '{{#if undef}}undef{{/if}}',
        '{{#if missing.path}}missing{{/if}}',
      ].join('|'),
      {
        user: { profile: { active: true, name: 'Alice' } },
        empty: '',
        zero: 0,
        boolFalse: false,
        nil: null,
        undef: undefined,
      },
    );

    expect(result).toBe('nested=Alice|missing=||zero||||');
  });

  it('renders booleans numbers objects and missing nested variables predictably', () => {
    const result = engine.render(
      'true={{flagTrue}} false={{flagFalse}} count={{count}} object={{payload}} missing={{user.name.first}}',
      {
        flagTrue: true,
        flagFalse: false,
        count: 42,
        payload: { id: 7, title: 'Report' },
        user: {},
      },
    );

    expect(result).toBe(
      'true=true false= count=42 object={"id":7,"title":"Report"} missing=',
    );
  });
});
