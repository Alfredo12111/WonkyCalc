import test from "node:test";
import assert from "node:assert/strict";
import { calculate, validateRequest, stages } from "../runtime.mjs";

function near(actual, expected, label) {
  const tolerance = expected === 0 ? 1e-14 : Math.abs(expected) * 1e-12;
  assert.ok(
    Math.abs(Number(actual) - expected) <= tolerance,
    `${label}: expected ${expected}, got ${actual}`,
  );
}
const cases = [
  ["2+3*4", 14],
  ["(2+3)*4", 20],
  ["2^3^2", 512],
  ["-2^2", -4],
  ["(-2)^2", 4],
  ["2^-3", 0.125],
  ["3!!", 720],
  ["5!+ncr(52,5)", 2599080],
  ["npr(10,3)", 720],
  ["200+10%", 200.1],
  ["sin(30)+cos(60)", 1],
  ["tan(45)", 1],
  ["asin(0.5)+acos(0.5)", 90],
  ["atan(1)", 45],
  ["atan2(1,-1)", 135],
  ["sin(pi/2)", 1, "RAD"],
  ["asin(1)", Math.PI / 2, "RAD"],
  ["cos(tau)", 1, "RAD"],
  ["ln(e)+log(100)+log2(8)+logn(81,3)", 10],
  ["sqrt(81)+cbrt(-27)+root(-32,5)", 4],
  ["sum(1,2,3,4)", 10],
  ["mean(2,4,6)", 4],
  ["mean(7)", 7],
  ["median(9,2,4,6)", 5],
  ["median(9,2,4)", 4],
  ["variance(1,2,3)", 2 / 3],
  ["stdev(2,4,4,4,5,5,7,9)", 2],
  ["stdev(7)", 0],
  ["min(2,-1,9)+max(2,-1,9)", 8],
  ["hypot(3,4)", 5],
  ["gcd(48,18)+lcm(4,6)", 18],
  ["mod(-5,3)", 1],
  ["abs(-3)+floor(2.9)+ceil(2.1)+round(-1.5)", 6],
  ["recip(4)+exp(0)", 1.25],
  ["sinh(0)+cosh(0)+tanh(0)+asinh(0)+acosh(1)+atanh(0)", 1],
  ["deg(pi)+rad(180)", 180 + Math.PI],
  ["2 × 3 + √(16) + 2³", 18],
  ["1e-20+1e-20", 2e-20],
  ["ans*3", 7.5, "DEG", "2.5"],
  ["0!+ncr(0,0)+npr(0,0)", 3],
  ["1e-300", 1e-300],
  ["1e300", 1e300],
  ["170!", 7.257415615307999e306],
];
for (const [expression, expected, mode = "DEG", ans = "0"] of cases) {
  test(`six real languages: ${expression} (${mode})`, async () => {
    const events = [];
    const result = await calculate({ expression, mode, ans }, (e) =>
      events.push(e),
    );
    near(result.raw, expected, expression);
    assert.deepEqual(
      result.trace.map((t) => t.id),
      stages.map((s) => s.id),
    );
    assert.equal(events.filter((e) => e.status === "complete").length, 6);
    assert.ok(
      Number.isFinite(Number(result.result)),
      `Display must be finite: ${result.result}`,
    );
    const displayTolerance =
      expected === 0 ? 1e-12 : Math.abs(expected) * 2e-11;
    assert.ok(
      Math.abs(Number(result.result) - expected) <= displayTolerance,
      `Displayed ${result.result} must preserve ${expected} to 12 significant digits`,
    );
    assert.ok(result.trace.every((t) => t.output && t.ms >= 0));
  });
}
const failures = [
  ["1/0", "j", /zero/],
  ["sqrt(-1)", "j", /non-negative/],
  ["ln(0)", "j", /positive/],
  ["tan(90)", "j", /undefined/],
  ["asin(2)", "j", /between/],
  ["171!", "j", /170/],
  ["1.5!", "j", /integer/],
  ["ncr(3,5)", "j", /integers/],
  ["(-2)^0.5", "j", /complex/],
  ["0^0", "j", /undefined/],
  ["root(-4,2)", "j", /odd/],
  ["logn(2,1)", "j", /base/],
  ["exp(1000)", "j", /range/],
  ["mean()", "prolog", /argument/],
  ["sin(1,2)", "prolog", /argument/],
  ["bogus(1)", "prolog", /Unknown/],
  ["2+", "raku", /Check/],
  ["2(pi)", "raku", /multiplication/],
  ["1;quit", "raku", /Check/],
  ["1+process.exit()", "raku", /Check/],
  ["abs((-2)^0.5)", "j", /complex/],
  ["exp(1000)^0", "j", /range/],
];
for (const [expression, stage, message] of failures) {
  test(`rejects ${expression} in ${stage}`, async () => {
    await assert.rejects(calculate({ expression }), (e) => {
      assert.equal(e.stage, stage);
      assert.match(e.message, message);
      return true;
    });
  });
}
test("display precision changes the presentation, not Ans", async () => {
  const result = await calculate({ expression: "1/3", precision: 6 });
  assert.equal(result.result, "0.333333");
  near(result.raw, 1 / 3, "unrounded answer");
  const chained = await calculate({ expression: "ans*3", ans: result.raw });
  near(chained.raw, 1, "Ans chain");
});
test("request validation rejects source injection and invalid options before spawning", () => {
  for (const input of [
    { expression: "2", ans: "1;exit" },
    { expression: "2", mode: "gradians" },
    { expression: "2", precision: 100 },
    { expression: "x".repeat(1025) },
    { expression: "" },
  ])
    assert.throws(() => validateRequest(input));
});
test("independent calculations cannot exchange intermediate files", async () => {
  const results = await Promise.all([
    calculate({ expression: "ncr(10,2)" }),
    calculate({ expression: "sqrt(144)" }),
  ]);
  assert.equal(results[0].raw, "45");
  assert.equal(results[1].raw, "12");
});
