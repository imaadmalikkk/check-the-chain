import { useState, useEffect, useCallback, useRef } from "react";

type PendingRequest = {
  resolve: (embedding: number[]) => void;
  reject: (error: Error) => void;
};

// Module-level singleton — the worker and model persist across component
// mounts/unmounts so the 31MB model only loads once per page session.
let singletonWorker: Worker | null = null;
let singletonReady = false;
let singletonProgress = 0;
const singletonPending = new Map<string, PendingRequest>();
let singletonIdCounter = 0;
const fileProgress = new Map<string, number>();
const listeners = new Set<() => void>();

function notify() {
  for (const fn of listeners) fn();
}

function getWorker(): Worker {
  if (singletonWorker) return singletonWorker;

  const worker = new Worker(
    new URL("./embedding-worker.ts", import.meta.url),
    { type: "module" },
  );

  worker.onmessage = (e: MessageEvent) => {
    const { type, id, embedding, error, data } = e.data;

    if (type === "progress") {
      if (data?.status === "progress" && data.file && typeof data.progress === "number") {
        fileProgress.set(data.file, data.progress);
        const avg = [...fileProgress.values()].reduce((a, b) => a + b, 0) / fileProgress.size;
        singletonProgress = Math.round(5 + (avg / 100) * 90);
        notify();
      }
      return;
    }

    if (type === "ready") {
      singletonProgress = 100;
      singletonReady = true;
      notify();
      return;
    }

    if (type === "result") {
      const pending = singletonPending.get(id);
      if (pending) {
        pending.resolve(embedding);
        singletonPending.delete(id);
      }
      return;
    }

    if (type === "error" && id) {
      const pending = singletonPending.get(id);
      if (pending) {
        pending.reject(new Error(error));
        singletonPending.delete(id);
      }
    }
  };

  worker.onerror = (e) => {
    console.error("Embedding worker error:", e.message);
    // Reject all pending requests so callers don't hang
    for (const [, pending] of singletonPending) {
      pending.reject(new Error("Worker crashed"));
    }
    singletonPending.clear();
    // Reset singleton so next call recreates the worker
    singletonWorker = null;
    singletonReady = false;
    singletonProgress = 0;
    notify();
  };

  singletonWorker = worker;
  singletonProgress = 5;
  worker.postMessage({ type: "init" });
  return worker;
}

export function useEmbedding() {
  const [ready, setReady] = useState(singletonReady);
  const [progress, setProgress] = useState(singletonProgress || 5);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;

    // Ensure worker is started
    getWorker();

    // Sync current state (worker may already be ready from a previous mount)
    setReady(singletonReady);
    setProgress(singletonProgress || 5);

    // Subscribe to updates
    const onUpdate = () => {
      if (!mountedRef.current) return;
      setReady(singletonReady);
      setProgress(singletonProgress);
    };
    listeners.add(onUpdate);

    return () => {
      mountedRef.current = false;
      listeners.delete(onUpdate);
      // Do NOT terminate the worker — it's a singleton
    };
  }, []);

  const embed = useCallback((text: string): Promise<number[]> => {
    return new Promise((resolve, reject) => {
      const worker = singletonWorker;
      if (!worker) {
        reject(new Error("Worker not initialized"));
        return;
      }
      const id = String(++singletonIdCounter);
      singletonPending.set(id, { resolve, reject });
      worker.postMessage({ type: "embed", id, text });
    });
  }, []);

  return { embed, ready, progress };
}
