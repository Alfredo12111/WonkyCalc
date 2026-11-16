import test from "node:test";
import assert from "node:assert/strict";
import { runProcess, ROOT } from "../runtime.mjs";
test("Cancellation terminates an owned worker instead of leaving the job running", async () => {
  const controller = new AbortController();
  const work = runProcess(
    process.execPath,
    ["-e", "setInterval(()=>{},1000)"],
    ROOT,
    controller.signal,
  );
  setTimeout(() => controller.abort(), 100);
  await assert.rejects(work, /cancelled/);
});
test("A stalled worker times out and exits", async () => {
  await assert.rejects(
    runProcess(
      process.execPath,
      ["-e", "setInterval(()=>{},1000)"],
      ROOT,
      undefined,
      100,
    ),
    /timed out/,
  );
});
