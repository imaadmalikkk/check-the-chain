import { useState, useEffect, useCallback, useRef } from "react";

type PendingRequest = {
  resolve: (embedding: number[]) => void;
  reject: (error: Error) => void;
};

type EmbeddingState = {
  worker: Worker | null;
  ready: boolean;
  progress: number;
  pending: Map<string, PendingRequest>;
  idCounter: number;
  searchCount: number;
  fileProgress: Map<string, number>;
  listeners: Set<() => void>;
};

// Persist on globalThis so the worker survives HMR module re-evaluation.
const KEY = "__embedding_worker_state__" as const;

// Terminate and recreate the worker every N searches to reclaim WASM heap memory.
// WASM linear memory can grow but NEVER shrink within a worker — the only way
// to free it is to terminate the worker entirely.
const MAX_SEARCHES_BEFORE_RECYCLE = 10;

function getState(): EmbeddingState {
  const g = globalThis as unknown as Record<string, EmbeddingState>;
  if (!g[KEY]) {
    g[KEY] = {
      worker: null,
      ready: false,
      progress: 0,
      pending: new Map(),
      idCounter: 0,
      searchCount: 0,
      fileProgress: new Map(),
      listeners: new Set(),
    };
  }
  return g[KEY];
}

function notify() {
  const s = getState();
  for (const fn of s.listeners) fn();
}

function recycleWorker() {
  const s = getState();
  if (s.worker) {
    s.worker.terminate();
    s.worker = null;
  }
  s.ready = false;
  s.progress = 0;
  s.searchCount = 0;
  s.fileProgress.clear();
  // Create a fresh worker immediately
  getWorker();
}

function getWorker(): Worker {
  const s = getState();
  if (s.worker) return s.worker;

  const worker = new Worker(
    new URL("./embedding-worker.ts", import.meta.url),
    { type: "module" },
  );

  worker.onmessage = (e: MessageEvent) => {
    const state = getState();
    const { type, id, embedding, error, data } = e.data;

    if (type === "progress") {
      if (data?.status === "progress" && data.file && typeof data.progress === "number") {
        state.fileProgress.set(data.file, data.progress);
        const avg = [...state.fileProgress.values()].reduce((a, b) => a + b, 0) / state.fileProgress.size;
        state.progress = Math.round(5 + (avg / 100) * 90);
        notify();
      }
      return;
    }

    if (type === "ready") {
      state.progress = 100;
      state.ready = true;
      state.fileProgress.clear();
      notify();
      return;
    }

    if (type === "result") {
      const pending = state.pending.get(id);
      if (pending) {
        pending.resolve(embedding);
        state.pending.delete(id);
      }

      // Check if we need to recycle the worker to free WASM memory
      state.searchCount++;
      if (state.searchCount >= MAX_SEARCHES_BEFORE_RECYCLE) {
        recycleWorker();
        notify();
      }
      return;
    }

    if (type === "error" && id) {
      const pending = state.pending.get(id);
      if (pending) {
        pending.reject(new Error(error));
        state.pending.delete(id);
      }
    }
  };

  worker.onerror = (e) => {
    const state = getState();
    console.error("Embedding worker error:", e.message);
    for (const [, pending] of state.pending) {
      pending.reject(new Error("Worker crashed"));
    }
    state.pending.clear();
    state.worker = null;
    state.ready = false;
    state.progress = 0;
    notify();
  };

  s.worker = worker;
  s.progress = 5;
  worker.postMessage({ type: "init" });
  return worker;
}

export function useEmbedding() {
  const s = getState();
  const [ready, setReady] = useState(s.ready);
  const [progress, setProgress] = useState(s.progress || 5);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    const state = getState();

    // Ensure worker is started
    getWorker();

    // Sync current state (worker may already be ready from a previous mount)
    setReady(state.ready);
    setProgress(state.progress || 5);

    // Subscribe to updates
    const onUpdate = () => {
      if (!mountedRef.current) return;
      const current = getState();
      setReady(current.ready);
      setProgress(current.progress);
    };
    state.listeners.add(onUpdate);

    return () => {
      mountedRef.current = false;
      state.listeners.delete(onUpdate);
    };
  }, []);

  const embed = useCallback((text: string): Promise<number[]> => {
    return new Promise((resolve, reject) => {
      const state = getState();
      // If worker was recycled and not ready yet, wait for it
      if (!state.worker) {
        getWorker();
      }
      const w = state.worker;
      if (!w) {
        reject(new Error("Worker not initialized"));
        return;
      }
      const id = String(++state.idCounter);
      state.pending.set(id, { resolve, reject });
      w.postMessage({ type: "embed", id, text });
    });
  }, []);

  return { embed, ready, progress };
}
