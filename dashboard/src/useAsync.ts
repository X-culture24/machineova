import { useCallback, useEffect, useRef, useState } from "react";

/** Runs an async loader on mount and whenever deps change; `reload` re-runs it. */
export function useAsync<T>(load: () => Promise<T>, deps: unknown[]) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const seq = useRef(0);

  const run = useCallback(() => {
    const id = ++seq.current;
    setLoading(true);
    load()
      .then((d) => {
        if (id === seq.current) {
          setData(d);
          setError(null);
        }
      })
      .catch((e: Error) => id === seq.current && setError(e.message))
      .finally(() => id === seq.current && setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(run, [run]);
  return { data, error, loading, reload: run };
}
