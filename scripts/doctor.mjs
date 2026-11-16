import { health, calculate } from "../runtime.mjs";
const languages = await health();
for (const language of languages)
  console.log(
    `${language.available ? "OK     " : "MISSING"} ${language.name} — ${language.role}`,
  );
if (languages.some((l) => !l.available)) {
  process.exitCode = 1;
} else {
  try {
    const result = await calculate({
      expression: "sin(30)^2 + cos(30)^2",
      mode: "DEG",
    });
    console.log(
      `\nSix-language smoke test: ${result.expression} = ${result.result} (${result.ms} ms)`,
    );
    if (Math.abs(Number(result.raw) - 1) > 1e-12)
      throw new Error("Numerical smoke test failed.");
    for (const stage of result.trace)
      console.log(`  ${stage.name}: ${stage.ms} ms`);
  } catch (e) {
    console.error(e.message);
    process.exitCode = 1;
  }
}
