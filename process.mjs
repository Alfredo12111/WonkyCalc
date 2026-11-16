import { spawn } from "node:child_process";

/** Fresh hidden workers, bounded output, and cancellation of owned process trees. */
export function runProcess(exe, args, cwd, signal, timeout = 15000) {
  if (signal?.aborted)
    return Promise.reject(new Error("Calculation cancelled."));
  return new Promise((resolve, reject) => {
    const child = spawn(exe, args, {
      cwd,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    });
    let output = "",
      stopReason = null,
      settled = false;
    function stop(message) {
      if (settled || stopReason) return;
      stopReason = new Error(message);
      if (process.platform === "win32" && child.pid) {
        const killer = spawn(
          "taskkill.exe",
          ["/PID", String(child.pid), "/T", "/F"],
          { windowsHide: true, stdio: "ignore" },
        );
        killer.on("error", () => child.kill());
        killer.on("close", (code) => {
          if (code !== 0 && !settled) child.kill();
        });
      } else child.kill();
    }
    const abort = () => stop("Calculation cancelled.");
    const timer = setTimeout(
      () => stop(`The language worker timed out. ${output.slice(-1000)}`),
      timeout,
    );
    const cleanup = () => {
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
    };
    signal?.addEventListener("abort", abort, { once: true });
    // Rebol needs a real pipe with EOF; an ignored stdin can leave it waiting.
    child.stdin.on("error", () => {});
    child.stdin.end();
    child.stdout.on("data", (b) => {
      output = (output + b).slice(-6000);
    });
    child.stderr.on("data", (b) => {
      output = (output + b).slice(-6000);
    });
    child.once("error", (error) => {
      cleanup();
      reject(error);
    });
    child.once("close", (code) => {
      cleanup();
      if (stopReason) reject(stopReason);
      else if (code === 0) resolve(output);
      else reject(new Error(output || `Worker exited with code ${code}.`));
    });
  });
}
