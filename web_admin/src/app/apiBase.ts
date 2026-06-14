import { normalizeApiBase } from '../api/adminApi';
import { defaultApiBase } from './constants';

export interface ApiBaseSources {
  storedValue: string | null;
  viteValue?: string;
}

export function resolveInitialApiBase({
  storedValue,
  viteValue,
}: ApiBaseSources): string {
  const selected = storedValue !== null ? storedValue : viteValue;
  if (selected == null || selected.trim() === '') {
    return normalizeApiBase(defaultApiBase);
  }
  return normalizeApiBase(selected);
}
