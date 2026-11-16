import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdtemp,
  writeFile,
  readFile,
  copyFile,
  rm,
  mkdir,
} from "node:fs/promises";
import path from "node:path";
import { ROOT, runtimes, runProcess } from "../runtime.mjs";

test("Red formats decimal strings without destroying tiny numbers or rounding carry", async () => {
  const cases = [
    ["1e-300", 12, "1e-300"],
    ["-1.23456789e-300", 6, "-1.23457e-300"],
    ["1.0000000000000001e300", 12, "1e300"],
    ["0.0000001", 12, "1e-7"],
    ["0.000001", 12, "0.000001"],
    ["999.9999", 6, "1000"],
    ["9.999999e99", 6, "1e100"],
    ["0.0009999999", 6, "0.001"],
    ["-0", 12, "0"],
    ["0", 12, "0"],
    ["1200", 12, "1200"],
    ["-0.000123456789", 6, "-0.000123457"],
    ["0.33333333333333331", 6, "0.333333"],
    ["7.257415615308004e306", 12, "7.25741561531e306"],
    ["9.8813129168249309e-324", 12, "9.88131291682e-324"],
  ];
  await mkdir(path.join(ROOT, ".cache"), { recursive: true });
  const directory = await mkdtemp(path.join(ROOT, ".cache", "format-"));
  try {
    await copyFile(
      path.join(ROOT, "workers/format.red"),
      path.join(directory, "format.red"),
    );
    for (const [raw, precision, expected] of cases) {
      await writeFile(path.join(directory, "result.txt"), raw);
      await writeFile(
        path.join(directory, "context.txt"),
        `DEG\n0\n${precision}\n`,
      );
      await runProcess(runtimes.red, ["format.red"], directory);
      assert.equal(
        (await readFile(path.join(directory, "formatted.txt"), "utf8")).trim(),
        expected,
        `${raw} at ${precision} digits`,
      );
    }
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
