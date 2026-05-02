import { useCallback, useState } from 'react';

export function useAsyncAction() {
  const [loading, setLoading] = useState(false);

  const run = useCallback(async <T,>(action: () => Promise<T>): Promise<T | undefined> => {
    setLoading(true);
    try {
      return await action();
    } finally {
      setLoading(false);
    }
  }, []);

  return { loading, run };
}

export function safeRandomId(): string {
  if ('crypto' in window && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
  return `web-admin-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}
