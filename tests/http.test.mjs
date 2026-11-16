import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { setTimeout as delay } from "node:timers/promises";
import { ROOT } from "../runtime.mjs";

test("HTTP boundary and live NDJSON trace", async () => {
  const port = 3291;
  const child = spawn(process.execPath, ["server.mjs"], {
    cwd: ROOT,
    env: { ...process.env, PORT: String(port) },
    windowsHide: true,
    stdio: "pipe",
  });
  const base = `http://127.0.0.1:${port}`;
  try {
    let ready = false;
    for (let i = 0; i < 30; i++) {
      try {
        const response = await fetch(`${base}/api/health`);
        if (response.ok) {
          ready = true;
          break;
        }
      } catch {}
      await delay(100);
    }
    assert.ok(ready, "Test server must start");
    const page = await fetch(base);
    assert.equal(page.status, 200);
    const html = await page.text();
    assert.match(html, /WonkyCalc/);
    assert.doesNotMatch(
      html,
      /type="checkbox"|id="(?:homework|per-operation|unnecessary)"/,
    );
    const request = (body, headers = {}) =>
      fetch(`${base}/api/calculate`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...headers },
        body: JSON.stringify(body),
      });
    assert.equal((await request({ expression: "" })).status, 400);
    assert.equal(
      (
        await request(
          { expression: "2+2" },
          { Origin: "https://unrelated.example" },
        )
      ).status,
      403,
    );
    assert.equal(
      (await fetch(`${base}/api/calculate`, { method: "POST", body: "2+2" }))
        .status,
      415,
    );
    assert.equal((await fetch(`${base}/not-a-file`)).status, 404);
    const response = await request({ expression: "sqrt(144)+1" });
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-type"), /ndjson/);
    const events = (await response.text()).trim().split("\n").map(JSON.parse);
    assert.equal(
      events.filter((e) => e.type === "stage" && e.status === "running").length,
      events.at(-1).receipt.processes,
    );
    assert.equal(
      events.filter((e) => e.type === "stage" && e.status === "complete")
        .length,
      events.at(-1).receipt.processes,
    );
    assert.equal(
      new Set(events.filter((e) => e.type === "handoff").map((e) => e.id)).size,
      12,
    );
    assert.equal(events.at(-1).type, "result");
    assert.equal(events.at(-1).raw, "13");
    assert.deepEqual(
      events.filter((e) => e.type === "build").map((e) => e.status),
      ["running", "complete"],
    );
    assert.ok(events.at(-1).receipt.buildMs > 0);
  } finally {
    child.kill();
    await new Promise((resolve) => {
      if (child.exitCode !== null) resolve();
      else child.once("close", resolve);
    });
  }
});
