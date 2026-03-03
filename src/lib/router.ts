"use client";

import { useSyncExternalStore } from "react";

export type Route =
  | { page: "search" }
  | { page: "browse" }
  | { page: "collection"; slug: string }
  | { page: "hadith"; slug: string; number: string };

function parseHash(hash: string): Route {
  const path = hash.replace(/^#\/?/, "");
  const segments = path.split("/").filter(Boolean);

  if (segments[0] === "browse" && segments[1]) {
    return { page: "collection", slug: segments[1] };
  }
  if (segments[0] === "browse") {
    return { page: "browse" };
  }
  if (segments[0] === "hadith" && segments[1] && segments[2]) {
    return { page: "hadith", slug: segments[1], number: segments[2] };
  }
  return { page: "search" };
}

let currentRoute: Route = { page: "search" };
let listeners: Array<() => void> = [];

function notify() {
  for (const fn of listeners) fn();
}

function subscribe(fn: () => void): () => void {
  listeners.push(fn);
  return () => {
    listeners = listeners.filter((l) => l !== fn);
  };
}

function getSnapshot(): Route {
  return currentRoute;
}

const SERVER_SNAPSHOT: Route = { page: "search" };

function getServerSnapshot(): Route {
  return SERVER_SNAPSHOT;
}

if (typeof window !== "undefined") {
  currentRoute = parseHash(window.location.hash);
  window.addEventListener("hashchange", () => {
    currentRoute = parseHash(window.location.hash);
    notify();
  });
}

export function useRoute(): Route {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);
}

export function navigate(path: string) {
  window.location.hash = path.startsWith("/") ? `#${path}` : `#/${path}`;
}

export function hadithUrl(slug: string, number: string): string {
  return `/#/hadith/${slug}/${number}`;
}

export function collectionUrl(slug: string): string {
  return `/#/browse/${slug}`;
}

export function browseUrl(): string {
  return "/#/browse";
}

export function searchUrl(): string {
  return "/";
}
