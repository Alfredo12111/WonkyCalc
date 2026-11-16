import { runProcess } from "./process.mjs";
export { runProcess };
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

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
  factor: resolve("factor", ".runtimes/factor/factor/factor.exe"),
  rexx: resolve("rexx", ".runtimes/rexx/rexx.exe"),
  bqn: resolve("bqn", ".runtimes/bqn/bqn/BQN.exe"),
  mercury: resolve("mercury", ".cache/bin/units.exe"),
  eiffel: resolve("eiffel", ".cache/bin/contracts.exe"),
  icon: resolve("icon", ".cache/bin/explain.exe"),
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
    output: "nodes.tsv",
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
stages.splice(3, 0, {
  id: "mercury",
  name: "Mercury",
  role: "Check units",
  description: "Checks dimensions before numbers travel any further.",
  file: "units.m",
  output: "units.txt",
});
stages.splice(5, 0, {
  id: "eiffel",
  name: "Eiffel",
  role: "Enforce contracts",
  description: "Checks shapes, domains and finite results.",
  file: "contracts/contracts.e",
  output: "contracts.txt",
});
stages.splice(
  7,
  0,
  {
    id: "bqn",
    name: "BQN",
    role: "Array math",
    description: "Calculates vectors and matrices, and audits scalar results.",
    file: "array.bqn",
    output: "array-result.txt",
  },
  {
    id: "factor",
    name: "Factor",
    role: "Second opinion",
    description: "Independently evaluates supported scalar expressions.",
    file: "check.factor",
    output: "factor.txt",
  },
  {
    id: "rexx",
    name: "Rexx",
    role: "Decimal audit",
    description: "Recomputes supported expressions with 50 decimal digits.",
    file: "decimal.rexx",
    output: "rexx.txt",
  },
);
stages.push({
  id: "icon",
  name: "Icon",
  role: "Explain",
  description: "Turns real handoffs into a readable calculation receipt.",
  file: "explain.icn",
  output: "explanation.txt",
});

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
  for (const option of ["homework", "perOperation", "unnecessary"])
    if (input[option] !== undefined && typeof input[option] !== "boolean")
      throw new Error(`${option} must be true or false.`);
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
  const { journey } = await import("./pipeline.mjs");
  return journey(input, onEvent, signal);
}
