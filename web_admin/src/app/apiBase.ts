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
  if (storedValue !== null) {
    if (storedValue === '') return '';
    return normalizeApiBase(storedValue);
  }
  if (viteValue == null || viteValue.trim() === '') {
    return normalizeApiBase(defaultApiBase);
  }
  return normalizeApiBase(viteValue);
}
