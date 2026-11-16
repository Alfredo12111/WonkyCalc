import {
  mkdir,
  mkdtemp,
  readFile,
  writeFile,
  copyFile,
  rm,
  stat,
} from "node:fs/promises";
import path from "node:path";
import { performance } from "node:perf_hooks";
import {
  ROOT,
  runtimes,
  stages,
  runProcess,
  validateRequest,
} from "./runtime.mjs";

const numberPattern = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;
const scalar = (s) => ({ shape: [], values: [s] });
const jNumber = (s) => {
  if (!numberPattern.test(s))
    throw new Error("A worker returned an invalid number.");
  return s.replaceAll("-", "_").replaceAll("+", "").replaceAll("E", "e");
};
const packet = (v) =>
  [v.shape.length, ...v.shape, v.values.length, ...v.values].join("\n") + "\n";
function unpack(text) {
  const lines = text.trim().replaceAll("¯", "-").split(/\r?\n/);
  const rank = Number(lines.shift());
  if (!Number.isInteger(rank) || rank < 0 || rank > 2)
    throw new Error("Invalid array rank.");
  const shape = lines.splice(0, rank).map(Number),
    count = Number(lines.shift());
  if (
    count !== lines.length ||
    count < 1 ||
    count > 256 ||
    lines.some((s) => !numberPattern.test(s) || !Number.isFinite(Number(s)))
  )
    throw new Error("Invalid array result.");
  return { shape, values: lines };
}
function bracket(v, values = v.values) {
  if (!v.shape.length) return values[0];
  if (v.shape.length === 1) return `[${values.join(", ")}]`;
  const rows = [];
  for (let i = 0; i < v.shape[0]; i++)
    rows.push(
      `[${values.slice(i * v.shape[1], (i + 1) * v.shape[1]).join(", ")}]`,
    );
  return `[${rows.join(", ")}]`;
}

export async function journey(input, onEvent = () => {}, signal) {
  const request = validateRequest(input),
    started = performance.now();
  await mkdir(path.join(ROOT, ".cache/jobs"), { recursive: true });
  const dir = await mkdtemp(path.join(ROOT, ".cache/jobs/calc-"));
  const trace = [],
    handoffs = [],
    graph = [],
    used = new Map();
  let numericMs = 0,
    buildMs = 0,
    activeStage = null;
  const read = async (name) =>
    (await readFile(path.join(dir, name), "utf8")).trim();
  const write = (name, text) => writeFile(path.join(dir, name), text, "utf8");
  const bytes = async (names) => {
    let total = 0;
    for (const n of names)
      try {
        total += (await stat(path.join(dir, n))).size;
      } catch {}
    return total;
  };
  const exe = { ...runtimes };
  async function run(id, label, args, output, inputs = [], parents = []) {
    const stage = stages.find((s) => s.id === id),
      at = performance.now();
    activeStage = id;
    await rm(path.join(dir, "error.txt"), { force: true });
    await rm(path.join(dir, output), { force: true });
    const key = `p${handoffs.length + 1}`,
      inputBytes = await bytes(inputs);
    onEvent({ type: "stage", id, status: "running", label });
    try {
      let cmd = exe[id];
      if (id === "tcl" && !exe.tcl) {
        cmd = exe.python;
        args = [path.join(ROOT, "scripts/tcl-host.py"), ...args];
      }
      await runProcess(cmd, args, dir, signal, id === "factor" ? 30000 : 15000);
      if (!output) throw new Error("Missing worker output contract.");
      const text = await read(output);
      const ms = performance.now() - at;
      const handoff = {
        key,
        id,
        name: stage.name,
        label,
        parents,
        ms: Math.round(ms * 10) / 10,
        bytes: inputBytes + (await bytes([output])),
        output: text.slice(0, 5000),
      };
      handoffs.push(handoff);
      const entry = used.get(id) || {
        id,
        name: stage.name,
        role: stage.role,
        ms: 0,
        calls: 0,
        status: "complete",
        output: "",
      };
      entry.ms = Math.round((entry.ms + ms) * 10) / 10;
      entry.calls++;
      entry.output = text;
      used.set(id, entry);
      onEvent({ type: "handoff", ...handoff });
      onEvent({ type: "stage", ...entry });
      return { text, key };
    } catch (error) {
      let message;
      try {
        message = await read("error.txt");
      } catch {}
      message ||= `${stage.name}: ${error.message.slice(0, 600)}`;
      onEvent({
        type: "stage",
        id,
        status: "error",
        message,
        ms: Math.round(performance.now() - at),
      });
      const failure = new Error(message);
      failure.stage = id;
      failure.trace = [...used.values()];
      throw failure;
    }
  }
  const check = async (op, args, parents = []) => {
    await write(
      "contract-input.txt",
      `${op}\n${args.length}\n${args.map(packet).join("")}`,
    );
    return run(
      "eiffel",
      `Contract: ${op}`,
      [],
      "contracts.txt",
      ["contract-input.txt"],
      parents,
    );
  };
  const j = async (op, template, inputs, parents = []) => {
    // Tcl owns all executable J plans; this host only copies plans and data.
    await copyFile(path.join(dir, template), path.join(dir, "plan.ijs"));
    const r = await run(
      "j",
      op,
      ["-jprofile", "engine.ijs"],
      "result.txt",
      ["plan.ijs", ...inputs],
      parents,
    );
    numericMs += Number((await read("math-ms.txt")).replaceAll("_", "-")) || 0;
    return { value: scalar(r.text), key: r.key };
  };
  const bqn = async (op, args, parents = []) => {
    await write(
      "array-input.txt",
      `${op}\n${args.length}\n${args.map(packet).join("")}`,
    );
    const r = await run(
      "bqn",
      op,
      ["array.bqn"],
      "array-result.txt",
      ["array-input.txt"],
      parents,
    );
    try {
      numericMs += Number((await read("bqn-ms.txt")).replaceAll("¯", "-")) || 0;
    } catch {}
    return { value: unpack(r.text), key: r.key };
  };
  try {
    for (const s of stages)
      if (s.file && !["eiffel", "mercury", "icon"].includes(s.id))
        await copyFile(
          path.join(ROOT, "workers", s.file),
          path.join(dir, s.file),
        );
    await write("request.txt", request.expression);
    await write(
      "context.txt",
      `${request.mode}\n${request.ans}\n${request.precision}\n`,
    );
    onEvent({ type: "route", expected: 12 });
    {
      onEvent({
        type: "build",
        status: "running",
        message: "Rebuilding Mercury, Eiffel and Icon before this calculation…",
      });
      const at = performance.now();
      await runProcess(
        "powershell.exe",
        [
          "-NoProfile",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          path.join(ROOT, "scripts/build-workers.ps1"),
          "-OutputDirectory",
          path.join(dir, "compiled"),
        ],
        ROOT,
        signal,
        180000,
      );
      buildMs = performance.now() - at;
      for (const [id, file] of [
        ["eiffel", "contracts.exe"],
        ["mercury", "units.exe"],
        ["icon", "explain.exe"],
      ])
        exe[id] = path.join(dir, "compiled", file);
      onEvent({
        type: "build",
        status: "complete",
        ms: Math.round(buildMs),
        message: "Mercury, Eiffel and Icon rebuilt from source.",
      });
    }
    let prior = (
      await run(
        "rebol",
        "Normalize",
        ["-s", "--quiet", "normalize.reb"],
        "normalized.txt",
        ["request.txt"],
      )
    ).key;
    prior = (
      await run(
        "raku",
        "Parse",
        ["parse.raku"],
        "tokens.txt",
        ["normalized.txt"],
        [prior],
      )
    ).key;
    const parsed = prior;
    prior = (
      await run(
        "prolog",
        "Validate",
        ["-q", "-f", "validate.pl"],
        "validated.txt",
        ["tokens.txt"],
        [prior],
      )
    ).key;
    prior = (
      await run(
        "mercury",
        "Check dimensions",
        [],
        "units.txt",
        ["validated.txt"],
        [prior],
      )
    ).key;
    const unitLines = (await read("units.txt")).split(/\r?\n/);
    // Dimensionless results start with a blank line; read() trims that line.
    const unit = unitLines.length > 1 ? unitLines[0] : "";
    prior = (
      await run(
        "tcl",
        "Build operation graph",
        ["plan.tcl"],
        "nodes.tsv",
        ["validated.txt", "context.txt"],
        [prior],
      )
    ).key;
    const values = new Map(),
      nodeKeys = new Map();
    const nodes = (await read("nodes.tsv")).split(/\r?\n/).map((line) => {
      const [id, kind, op, refs] = line.split("\t");
      return { id, kind, op, refs: refs === "-" ? [] : refs.split(",") };
    });
    for (const node of nodes) {
      const args = node.refs.map((id) => values.get(id));
      let parents = node.refs.map((id) => nodeKeys.get(id) || parsed),
        result;
      if (node.kind === "N") {
        result = { value: scalar(node.op), key: parsed };
      } else if (node.kind === "C") {
        result = await j(
          `constant ${node.op}`,
          `plan-${node.id}.ijs`,
          [],
          parents,
        );
      } else {
        const arrays =
          args.some((v) => v.shape.length > 0) ||
          ["array", "dot", "matmul", "det", "transpose", "norm"].includes(
            node.op,
          );
        {
          const c = await check(node.op, args, parents);
          parents = [c.key];
        }
        result = arrays
          ? await bqn(node.op, args, parents)
          : await j(
              node.op,
              `plan-${node.id}.ijs`,
              node.refs.map((id) => `value${id}.txt`),
              parents,
            );
        {
          const c = await check("result", [result.value], [result.key]);
          result.key = c.key;
        }
      }
      values.set(node.id, result.value);
      await write(
        `value${node.id}.txt`,
        result.value.values.map(jNumber).join(" "),
      );
      nodeKeys.set(node.id, result.key);
      const graphNode = {
        id: node.id,
        op: node.op,
        kind: node.kind,
        inputs: node.refs,
        value: bracket(result.value),
        handoff: result.key,
      };
      graph.push(graphNode);
      onEvent({ type: "node", ...graphNode });
    }
    let value = values.get(nodes.at(-1).id),
      finalParent = nodeKeys.get(nodes.at(-1).id);
    if (!used.has("j")) {
      await write("audit-value.txt", jNumber(value.values[0]));
      const audit = await j(
        "Audit a result element",
        "audit.ijs",
        ["audit-value.txt"],
        [finalParent],
      );
      finalParent = audit.key;
    }
    const audited = await bqn("audit", [value], [finalParent]);
    value = audited.value;
    finalParent = audited.key;
    await check("final result", [value], [finalParent]);
    const raw = bracket(value);
    await write("result.txt", value.shape.length ? raw : value.values[0]);
    const factor = await run(
      "factor",
      "Independent scalar evaluation",
      ["-no-user-init", "check.factor"],
      "factor.txt",
      ["tokens.txt", "context.txt"],
      [parsed],
    );
    const decimal = await run(
      "rexx",
      "50-digit decimal evaluation",
      ["decimal.rexx"],
      "rexx.txt",
      ["tokens.txt", "context.txt", "result.txt"],
      [parsed, finalParent],
    );
    const decode = (text) => {
      const [status, result, delta] = text.split(/\r?\n/);
      return { status, result, delta };
    };
    const homework = {
      j: raw,
      factor: decode(factor.text),
      rexx: decode(decimal.text),
    };
    const formatted = [];
    for (const v of value.values) {
      await write("result.txt", v);
      const f = await run(
        "red",
        "Format a result component",
        ["format.red"],
        "formatted.txt",
        ["result.txt", "context.txt"],
        [finalParent],
      );
      formatted.push(f.text);
    }
    const result = bracket(value, formatted) + (unit ? ` ${unit}` : "");
    const journeyLines = handoffs.map(
      (h) => `${h.name}: ${h.label}; ${h.ms} ms; ${h.bytes} payload bytes.`,
    );
    await write("journey.txt", journeyLines.join("\n") + "\n");
    const explanation = (
      await run(
        "icon",
        "Explain recorded handoffs",
        [],
        "explanation.txt",
        ["journey.txt"],
        handoffs.slice(-1).map((h) => h.key),
      )
    ).text;
    trace.push(...used.values());
    const workerMs = handoffs.reduce((n, h) => n + h.ms, 0);
    return {
      expression: request.expression,
      mode: request.mode,
      precision: request.precision,
      raw,
      result,
      unit,
      shape: value.shape,
      trace,
      graph,
      handoffs,
      homework,
      explanation,
      ms: Math.round(performance.now() - started),
      receipt: {
        languages: [...used.keys()],
        processes: handoffs.length,
        payloadBytes: handoffs.reduce((n, h) => n + h.bytes, 0),
        numericMs: Math.round(numericMs * 100) / 100,
        overheadMs: Math.round(Math.max(0, workerMs - numericMs)),
        buildMs: Math.round(buildMs),
        compiled: ["Mercury", "Eiffel", "Icon"],
      },
    };
  } catch (error) {
    error.stage ??= activeStage;
    throw error;
  } finally {
    await rm(dir, { recursive: true, force: true, maxRetries: 3 });
  }
}
