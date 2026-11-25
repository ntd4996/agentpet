import assert from "node:assert/strict";
import test from "node:test";
import { applyBackup, snapshot } from "../src/backup.ts";

// Run with Node 22.18+ (native TypeScript stripping): node --test scripts/backup.test.mjs
class QuotaStorage {
  constructor(data, quota, failAt = Infinity) {
    this.data = new Map(Object.entries(data));
    this.quota = quota;
    this.failAt = failAt;
    this.writes = 0;
  }
  get length() { return this.data.size; }
  key(i) { return [...this.data.keys()][i] ?? null; }
  getItem(k) { return this.data.get(k) ?? null; }
  removeItem(k) { this.data.delete(k); }
  clear() { this.data.clear(); }
  setItem(k, v) {
    this.writes++;
    const next = new Map(this.data).set(k, v);
    const size = [...next.values()].reduce((sum, s) => sum + s.length, 0);
    if (this.writes === this.failAt || size > this.quota) {
      throw new DOMException("Quota exceeded", "QuotaExceededError");
    }
    this.data = next;
  }
}
const old = { ap_a: "AAAA", ap_b: "BBBBBB" };
const backup = { format: "agentpet-backup", version: 1, exportedAt: "", data: { ap_a: "X", ap_b: "YYYYYYYYY", ap_c: "Z" } };

test("quota failure at third write restores all old values", () => {
  const ls = new QuotaStorage(old, 10);
  assert.throws(() => applyBackup(backup, ls), { name: "QuotaExceededError" });
  assert.deepEqual(snapshot(ls), old);
});

test("failure at each write restores snapshot without touching device or foreign keys", () => {
  for (const k of [1, 2, 3]) {
    const initial = { ...old, ap_care_token: "device", ap_care_login: "login", ap_usage_dirty: "dirty", foreign: "other" };
    const ls = new QuotaStorage(initial, 100, k);
    assert.throws(() => applyBackup(backup, ls), { name: "QuotaExceededError" });
    assert.deepEqual(Object.fromEntries(ls.data), initial);
  }
});

test("successful restore replaces only AgentPet backup keys", () => {
  const ls = new QuotaStorage({ ...old, ap_stale: "stale", foreign: "keep" }, 100);
  assert.equal(applyBackup(backup, ls), 3);
  assert.deepEqual(snapshot(ls), backup.data);
  assert.equal(ls.getItem("foreign"), "keep");
});
