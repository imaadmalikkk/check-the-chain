import { useState, useEffect, useRef, useCallback } from "react";

type PendingRequest = {
  resolve: (embedding: number[]) => void;
  reject: (error: Error) => void;
};

export function useEmbedding() {
  const [ready, setReady] = useState(false);
  const [progress, setProgress] = useState(0);
  const workerRef = useRef<Worker | null>(null);
  const pendingRef = useRef<Map<string, PendingRequest>>(new Map());
  const idCounter = useRef(0);
  const fileProgressRef = useRef<Map<string, number>>(new Map());

  useEffect(() => {
    // Start at 5% immediately for instant feedback
    setProgress(5);

    const worker = new Worker(
      new URL("./embedding-worker.ts", import.meta.url),
      { type: "module" },
    );
    workerRef.current = worker;

    worker.onmessage = (e: MessageEvent) => {
      const { type, id, embedding, error, data } = e.data;

      if (type === "progress") {
        if (data?.status === "progress" && data.file && typeof data.progress === "number") {
          fileProgressRef.current.set(data.file, data.progress);
          const files = fileProgressRef.current;
          const avg = [...files.values()].reduce((a, b) => a + b, 0) / files.size;
          // Map 0-100 avg into 5-95 range (5% base, 100% reserved for ready)
          setProgress(Math.round(5 + (avg / 100) * 90));
        }
        return;
      }

      if (type === "ready") {
        setProgress(100);
        setReady(true);
        return;
      }

      if (type === "result") {
        const pending = pendingRef.current.get(id);
        if (pending) {
          pending.resolve(embedding);
          pendingRef.current.delete(id);
        }
        return;
      }

      if (type === "error" && id) {
        const pending = pendingRef.current.get(id);
        if (pending) {
          pending.reject(new Error(error));
          pendingRef.current.delete(id);
        }
      }
    };

    // Warm up: preload model immediately
    worker.postMessage({ type: "init" });

    return () => {
      worker.terminate();
      workerRef.current = null;
      // Reject any pending requests
      for (const [, pending] of pendingRef.current) {
        pending.reject(new Error("Worker terminated"));
      }
      pendingRef.current.clear();
    };
  }, []);

  const embed = useCallback((text: string): Promise<number[]> => {
    return new Promise((resolve, reject) => {
      if (!workerRef.current) {
        reject(new Error("Worker not initialized"));
        return;
      }
      const id = String(++idCounter.current);
      pendingRef.current.set(id, { resolve, reject });
      workerRef.current.postMessage({ type: "embed", id, text });
    });
  }, []);

  return { embed, ready, progress };
}
