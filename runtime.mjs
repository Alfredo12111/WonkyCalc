import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import {
  mkdtemp,
  mkdir,
  readFile,
  writeFile,
  rm,
  copyFile,
} from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { performance } from "node:perf_hooks";

export const ROOT = path.dirname(fileURLToPath(import.meta.url));
const localFile = path.join(ROOT, "runtime.local.json");
const local = existsSync(localFile)
  ? JSON.parse(readFileSync(localFile, "utf8"))
  : {};
const resolve = (name, fallback) =>
  process.env[`WONKYCALC_${name.toUpperCase()}`] ||
  local[name] ||
  path.join(ROOT, fallback);
export const runtimes = {
  rebol: resolve("rebol", ".runtimes/rebol.exe"),
  raku: resolve(
    "raku",
    ".runtimes/raku/rakudo-moar-2026.09-01-win-x86_64-msvc/bin/raku.exe",
  ),
  prolog: resolve("prolog", ".runtimes/prolog/bin/swipl.exe"),
  tcl: process.env.WONKYCALC_TCL || local.tcl || null,
  python: process.env.WONKYCALC_PYTHON || local.python || "python",
  j: resolve("j", ".runtimes/j/j64/jconsole.exe"),
  red: resolve("red", ".runtimes/red.exe"),
};

export const stages = [
  {
    id: "rebol",
    name: "Rebol",
    role: "Normalize",
    description: "Cleans symbols and prepares your expression.",
    file: "normalize.reb",
    output: "normalized.txt",
  },
  {
    id: "raku",
    name: "Raku",
    role: "Parse",
    description: "Turns your expression into a postfix instruction stream.",
    file: "parse.raku",
    output: "tokens.txt",
  },
  {
    id: "prolog",
    name: "Prolog",
    role: "Validate",
    description: "Proves the operations and argument counts are valid.",
    file: "validate.pl",
    output: "validated.txt",
  },
  {
    id: "tcl",
    name: "Tcl",
    role: "Plan",
    description: "Builds a named execution plan for the numeric engine.",
    file: "plan.tcl",
    output: "plan.ijs",
  },
  {
    id: "j",
    name: "J",
    role: "Calculate",
    description: "Evaluates arithmetic, scientific functions, and statistics.",
    file: "engine.ijs",
    output: "result.txt",
  },
  {
    id: "red",
    name: "Red",
    role: "Format",
    description: "Rounds the answer to your chosen display precision.",
    file: "format.red",
    output: "formatted.txt",
  },
];

function command(stage, directory) {
  // Rebol's Windows CLI splits absolute script paths containing spaces.
  // Every worker is copied into the isolated cwd, so a basename is sufficient.
  const file = stage.file;
  if (stage.id === "prolog") return [runtimes.prolog, ["-q", "-f", file]];
  if (stage.id === "tcl")
    return runtimes.tcl
      ? [runtimes.tcl, [file]]
      : [runtimes.python, [path.join(ROOT, "scripts/tcl-host.py"), file]];
  if (stage.id === "j") return [runtimes.j, ["-jprofile", file]];
  if (stage.id === "rebol") return [runtimes.rebol, ["-s", "--quiet", file]];
  return [runtimes[stage.id], [file]];
}

export function runProcess(exe, args, cwd, signal, timeout = 12000) {
  return new Promise((resolve, reject) => {
    const child = spawn(exe, args, {
      cwd,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
      signal,
    });
    child.stdin.on("error", () => {});
    child.stdin.end();
    let output = "";
    const timer = setTimeout(() => {
      child.kill();
      reject(
        new Error(`The language worker timed out. ${output.slice(-1000)}`),
      );
    }, timeout);
    child.stdout.on("data", (b) => {
      output = (output + b).slice(-4000);
    });
    child.stderr.on("data", (b) => {
      output = (output + b).slice(-4000);
    });
    child.on("error", (e) => {
      clearTimeout(timer);
      reject(e);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      code === 0
        ? resolve(output)
        : reject(new Error(output || `Worker exited with code ${code}.`));
    });
  });
}

export async function health() {
  let tcl = false;
  try {
    if (runtimes.tcl) tcl = existsSync(runtimes.tcl);
    else {
      await runProcess(
        runtimes.python,
        ["-c", 'import tkinter; print(tkinter.Tcl().eval("info patchlevel"))'],
        ROOT,
        undefined,
        3000,
      );
      tcl = true;
    }
  } catch {}
  return stages.map((s) => ({
    ...s,
    available: s.id === "tcl" ? tcl : existsSync(runtimes[s.id]),
  }));
}

export function validateRequest(input) {
  if (
    !input ||
    typeof input.expression !== "string" ||
    !input.expression.trim()
  )
    throw new Error("Enter an expression first.");
  if (input.expression.length > 1024)
    throw new Error("Keep expressions under 1,024 characters.");
  if (!["DEG", "RAD"].includes(input.mode ?? "DEG"))
    throw new Error("Angle mode must be DEG or RAD.");
  if (![6, 10, 12, 14].includes(input.precision ?? 12))
    throw new Error("Unsupported display precision.");
  const ans = String(input.ans ?? "0");
  if (
    !/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(ans) ||
    !Number.isFinite(Number(ans))
  )
    throw new Error("Invalid previous answer.");
  return {
    ...input,
    ans,
    mode: input.mode ?? "DEG",
    precision: input.precision ?? 12,
  };
}

export async function calculate(input, onEvent = () => {}, signal) {
  const request = validateRequest(input);
  const cache = path.join(ROOT, ".cache", "jobs");
  await mkdir(cache, { recursive: true });
  const directory = await mkdtemp(path.join(cache, "calc-"));
  const trace = [];
  const started = performance.now();
  try {
    await writeFile(
      path.join(directory, "request.txt"),
      request.expression,
      "utf8",
    );
    await writeFile(
      path.join(directory, "context.txt"),
      `${request.mode}\n${request.ans}\n${request.precision}\n`,
      "utf8",
    );
    for (const stage of stages) {
      const at = performance.now();
      onEvent({ type: "stage", id: stage.id, status: "running" });
      try {
        await copyFile(
          path.join(ROOT, "workers", stage.file),
          path.join(directory, stage.file),
        );
        const [exe, args] = command(stage, directory);
        await runProcess(exe, args, directory, signal);
        const output = (
          await readFile(path.join(directory, stage.output), "utf8")
        ).trim();
        if (!output)
          throw new Error("The language worker returned an empty result.");
        const entry = {
          id: stage.id,
          name: stage.name,
          role: stage.role,
          ms: Math.round((performance.now() - at) * 10) / 10,
          output,
          status: "complete",
        };
        trace.push(entry);
        onEvent({ type: "stage", ...entry });
      } catch (error) {
        let message;
        try {
          message = (
            await readFile(path.join(directory, "error.txt"), "utf8")
          ).trim();
        } catch {}
        message ||=
          error.code === "ENOENT"
            ? `${stage.name} is not installed. Run npm run setup, then npm run doctor.`
            : `${stage.name} could not complete this calculation. ${error.message.slice(0, 300)}`;
        onEvent({
          type: "stage",
          id: stage.id,
          status: "error",
          message,
          ms: Math.round(performance.now() - at),
        });
        const failure = new Error(message);
        failure.trace = trace;
        failure.stage = stage.id;
        throw failure;
      }
    }
    const raw = (
      await readFile(path.join(directory, "result.txt"), "utf8")
    ).trim();
    if (!Number.isFinite(Number(raw)))
      throw new Error("The engine returned a non-finite result.");
    return {
      expression: request.expression,
      mode: request.mode,
      precision: request.precision,
      raw,
      result: trace.at(-1).output,
      trace,
      ms: Math.round(performance.now() - started),
    };
  } finally {
    await rm(directory, { recursive: true, force: true, maxRetries: 3 });
  }
}
