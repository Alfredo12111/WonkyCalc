import test from "node:test";
import assert from "node:assert/strict";
import { calculate } from "../runtime.mjs";

const arrays = [
  ["[1,2,3]", [1, 2, 3]],
  ["[1,2]+[3,4]", [4, 6]],
  ["2*[1,2,3]", [2, 4, 6]],
  ["dot([1,2,3],[4,5,6])", 32],
  ["det([[1,2],[3,4]])", -2],
  ["det([[1,2,3],[0,1,4],[5,6,0]])", 1],
  [
    "matmul([[1,2],[3,4]],[[5,6],[7,8]])",
    [
      [19, 22],
      [43, 50],
    ],
  ],
  ["matmul([[1,2,3]],[[4],[5],[6]])", [[32]]],
  [
    "transpose([[1,2,3],[4,5,6]])",
    [
      [1, 4],
      [2, 5],
      [3, 6],
    ],
  ],
  ["norm([3,4])", 5],
  ["sum([[1,2],[3,4]])", 10],
  ["mean([2,4,6])", 4],
];
for (const [expression, wanted] of arrays)
  test(`BQN calculates ${expression}`, async () => {
    const result = await calculate({ expression });
    assert.deepEqual(JSON.parse(result.raw), wanted);
    assert.ok(
      result.handoffs.some((h) => h.id === "bqn" && h.label !== "audit"),
    );
    assert.equal(result.homework.factor.status, "unsupported");
    assert.equal(result.homework.rexx.status, "unsupported");
  });
for (const [expression, wanted, unit] of [
  ["5 m + 30 cm", 5.3, "m"],
  ["10 m / 2 s", 5, "m s^-1"],
  ["2 kg * 3 m / (1 s)^2", 6, "m kg s^-2"],
  ["sqrt((4 m)^2)", 4, "m"],
  ["1 km + 100 m", 1100, "m"],
  ["[1,2] m + [3,4] m", [4, 6], "m"],
  ["det(2*([[1,2],[3,4]] m))", -8, "m^2"],
  ["det([[norm([3,4] m),0 m],[0 m,1 m]])", 5, "m^2"],
])
  test(`Mercury checks ${expression}`, async () => {
    const r = await calculate({ expression });
    assert.deepEqual(JSON.parse(r.raw), wanted);
    assert.equal(r.unit, unit);
  });
for (const [expression, stage, pattern] of [
  ["5 m + 3 seconds", "mercury", /Incompatible units/],
  ["sin(2 m)", "mercury", /dimensionless/],
  ["variance(1 m,2 s)", "mercury", /Incompatible units/],
  ["[1,2]+[3]", "eiffel", /dimensions/],
  ["[[1,2],[3]]", "eiffel", /equal lengths/],
  ["matmul([[1,2]],[[3,4]])", "eiffel", /inner dimensions/],
  ["det([[1,2,3],[4,5,6]])", "eiffel", /square/],
  ["dot([1,2],[3])", "eiffel", /equal length/],
  ["sum([1,2],[3,4])", "eiffel", /exactly one/],
])
  test(`rejects ${expression}`, async () => {
    await assert.rejects(calculate({ expression }), (e) => {
      assert.equal(e.stage, stage);
      assert.match(e.message, pattern);
      return true;
    });
  });
test("Independent decimal calculation exposes a real rounding difference", async () => {
  const r = await calculate({ expression: "0.1+0.2" });
  assert.equal(r.homework.factor.status, "ok");
  assert.equal(r.homework.rexx.status, "ok");
  assert.equal(r.homework.rexx.result, "0.3");
  assert.notEqual(Number(r.homework.rexx.delta), 0);
  assert.equal(r.receipt.languages.length, 12);
  assert.equal(r.receipt.processes, r.handoffs.length);
  assert.ok(r.receipt.payloadBytes > 0);
  assert.ok(r.receipt.numericMs >= 0);
  const known = new Set();
  for (const h of r.handoffs) {
    for (const parent of h.parents) assert.ok(known.has(parent));
    known.add(h.key);
  }
  assert.ok(r.graph.some((n) => n.op === "add" && n.inputs.length === 2));
  assert.match(r.explanation, /J: add/);
  assert.match(r.explanation, /Factor/);
});
test("Unrequested checks are skipped truthfully and scenic contracts add real launches", async () => {
  const normal = await calculate({
    expression: "2+3*4",
    homework: false,
    perOperation: false,
  });
  const scenic = await calculate({
    expression: "2+3*4",
    homework: false,
    perOperation: true,
  });
  assert.equal(normal.raw, scenic.raw);
  assert.equal(normal.receipt.languages.length, 10);
  assert.ok(!normal.trace.some((t) => t.id === "factor" || t.id === "rexx"));
  assert.ok(scenic.receipt.processes > normal.receipt.processes);
});
test(
  "Absolutely unnecessary mode recompiles real native workers",
  { timeout: 180000 },
  async () => {
    const r = await calculate({ expression: "2+2", unnecessary: true });
    assert.equal(r.raw, "4");
    assert.deepEqual(r.receipt.compiled, ["Mercury", "Eiffel", "Icon"]);
    assert.ok(r.receipt.buildMs > 0);
  },
);
