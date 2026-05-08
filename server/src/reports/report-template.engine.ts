/**
 * FlowPlanV2 report template engine.
 *
 * Supports:
 *   {{variable}}              — simple variable substitution
 *   {{#if variable}}...{{/if}} — conditional block (truthy = shown)
 *   {{#each items}}...{{/each}} — loop over array of records
 *   {{@key}}                  — current iteration key inside #each
 *   {{@index}}                — current iteration index (0-based) inside #each
 *
 * Usage:
 *   const engine = new ReportTemplateEngine();
 *   const result = engine.render(template, variables);
 */

export interface TemplateContext {
  [key: string]: unknown;
}

export class ReportTemplateEngine {
  /**
   * Render a template string with the given context.
   */
  render(template: string, context: TemplateContext): string {
    let result = template;

    // 1. Process #each blocks (innermost first)
    result = this.processEach(result, context);

    // 2. Process #if blocks
    result = this.processIf(result, context);

    // 3. Process simple {{variable}} substitutions
    result = result.replace(/\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\}\}/g, (_, key: string) => {
      return this.resolve(key, context) ?? '';
    });

    return result;
  }

  // ---- #each ----

  private processEach(template: string, context: TemplateContext): string {
    const eachRegex = /\{\{#each\s+([a-zA-Z_][a-zA-Z0-9_]*)\}\}([\s\S]*?)\{\{\/each\}\}/g;

    return template.replace(eachRegex, (_, varName: string, body: string) => {
      const items = context[varName];
      if (!Array.isArray(items)) return '';

      return items
        .map((item: unknown, index: number) => {
          const itemContext: TemplateContext = {
            ...context,
            '@index': index,
          };
          if (typeof item === 'object' && item !== null) {
            Object.assign(itemContext, item as Record<string, unknown>);
          }
          // First pass: simple variables inside loop body
          let rendered = body.replace(
            /\{\{\s*([a-zA-Z_@][a-zA-Z0-9_.]*)\s*\}\}/g,
            (_, key: string) => {
              if (key === '@index') return String(index);
              if (key.startsWith('@')) return '';
              return this.resolve(key, itemContext as Record<string, unknown>) ?? '';
            },
          );
          // Process nested #if inside #each
          rendered = this.processIfInLoop(rendered, itemContext);
          return rendered;
        })
        .join('');
    });
  }

  // ---- #if ----

  private processIf(template: string, context: TemplateContext): string {
    const ifRegex = /\{\{#if\s+([a-zA-Z_][a-zA-Z0-9_.]*)\}\}([\s\S]*?)\{\{\/if\}\}/g;

    return template.replace(ifRegex, (_, varName: string, body: string) => {
      const value = this.resolve(varName, context);
      // Truthy: non-null, non-undefined, non-empty-string
      const isTruthy = value !== null && value !== undefined && value !== '';
      if (!isTruthy) return '';

      // Re-process simple variables inside the if body
      return body.replace(
        /\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\}\}/g,
        (innerMatch: string, key: string) => {
          return this.resolve(key, context) ?? '';
        },
      );
    });
  }

  private processIfInLoop(body: string, context: TemplateContext): string {
    const ifRegex = /\{\{#if\s+([a-zA-Z_][a-zA-Z0-9_.]*)\}\}([\s\S]*?)\{\{\/if\}\}/g;
    return body.replace(ifRegex, (_, varName: string, ifBody: string) => {
      const value: unknown = context[varName];
      const isTruthy = value != null && value !== '' && value !== false;
      return isTruthy
        ? ifBody.replace(/\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\}\}/g, (__: string, key: string) =>
            key === '@index' ? String(context['@index'] ?? '') : (context[key] as string) ?? '')
        : '';
    });
  }

  // ---- variable resolution ----

  private resolve(key: string, context: Record<string, unknown>): string | null {
    const parts = key.split('.');
    let current: unknown = context;
    for (const part of parts) {
      if (current && typeof current === 'object') {
        current = (current as Record<string, unknown>)[part];
      } else {
        return null;
      }
    }
    if (current === null || current === undefined) return null;
    if (typeof current === 'boolean') return current ? 'true' : '';
    if (typeof current === 'string') return current;
    if (typeof current === 'number') return String(current);
    return JSON.stringify(current);
  }
}
