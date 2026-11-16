const $ = (selector) => document.querySelector(selector);
const input = $("#expression");
const answer = $("#answer");
const languages = [
  {
    id: "rebol",
    name: "Rebol",
    badge: "Re",
    role: "Normalize",
    description: "A clean start for your expression.",
  },
  {
    id: "raku",
    name: "Raku",
    badge: "Ra",
    role: "Parse",
    description: "Makes sense of symbols and syntax.",
  },
  {
    id: "prolog",
    name: "Prolog",
    badge: "Pr",
    role: "Validate",
    description: "Checks that the logic checks out.",
  },
  {
    id: "tcl",
    name: "Tcl",
    badge: "Tc",
    role: "Plan",
    description: "Puts every operation in its place.",
  },
  {
    id: "j",
    name: "J",
    badge: "J",
    role: "Calculate",
    description: "Does the actual number crunching.",
  },
  {
    id: "red",
    name: "Red",
    badge: "Rd",
    role: "Format",
    description: "Puts the finishing digits on it.",
  },
];
let mode = "DEG",
  busy = false,
  lastRaw = "0",
  memory = null,
  justCalculated = false;
let history = [],
  total = 0,
  toastTimer,
  healthy = false;
try {
  const saved = JSON.parse(localStorage.getItem("wonkycalc-v1") || "{}");
  history = Array.isArray(saved.history)
    ? saved.history
        .filter(
          (h) =>
            typeof h.expression === "string" &&
            typeof h.result === "string" &&
            typeof h.raw === "string" &&
            Number.isFinite(Number(h.raw)),
        )
        .slice(0, 30)
    : [];
  memory =
    typeof saved.memory === "string" && Number.isFinite(Number(saved.memory))
      ? saved.memory
      : null;
  mode = saved.mode === "RAD" ? "RAD" : "DEG";
  lastRaw =
    typeof saved.lastRaw === "string" && Number.isFinite(Number(saved.lastRaw))
      ? saved.lastRaw
      : "0";
} catch {}
const save = () => {
  try {
    localStorage.setItem(
      "wonkycalc-v1",
      JSON.stringify({ history, memory, mode, lastRaw }),
    );
  } catch {}
};
const escape = (value) =>
  String(value).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
function toast(text) {
  const el = $("#toast");
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 3000);
}
function setMode(value) {
  mode = value;
  for (const kind of ["DEG", "RAD"]) {
    const button = $(`#${kind.toLowerCase()}`);
    button.classList.toggle("active", kind === mode);
    button.setAttribute("aria-pressed", String(kind === mode));
  }
  save();
}
function renderLanguages() {
  $("#language-list").innerHTML = languages
    .map(
      (l) =>
        `<div class="language" data-id="${l.id}"><button class="language-header" aria-label="${l.name}: ${l.role}. ${l.description}" title="Details appear after this stage runs"><span class="language-icon">${l.badge}</span><span class="language-text"><span class="language-name">${l.name}<span class="language-role">${l.role}</span></span><span class="language-description">${l.description}</span></span><span class="language-time">—</span><span class="language-state">·</span></button><details hidden><summary>View output</summary><pre></pre></details></div>`,
    )
    .join("");
  document.querySelectorAll(".language-header").forEach((button) =>
    button.addEventListener("click", () => {
      const detail = button.nextElementSibling;
      if (!detail.hidden) detail.open = !detail.open;
    }),
  );
}
function resetTrace() {
  total = 0;
  renderLanguages();
  $("#trace-count").textContent = "0 / 6";
  $("#trace-progress").style.width = "0%";
  $("#trace-label").textContent = "Taking the scenic route…";
  $("#trace-note").textContent =
    "Starting six real language runtimes. Timings include startup.";
}
function updateStage(event) {
  const row = $(`.language[data-id="${event.id}"]`);
  row.classList.remove("running", "complete", "error");
  row.classList.add(event.status);
  row.querySelector(".language-state").textContent =
    event.status === "running" ? "" : event.status === "complete" ? "✓" : "!";
  if (event.ms !== undefined)
    row.querySelector(".language-time").textContent =
      event.ms >= 1000
        ? `${(event.ms / 1000).toFixed(2)} s`
        : `${Math.round(event.ms)} ms`;
  if (event.output || event.message) {
    const details = row.querySelector("details");
    details.hidden = false;
    details.querySelector("pre").textContent = event.output || event.message;
  }
  if (event.status === "complete") {
    total++;
    $("#trace-count").textContent = `${total} / 6`;
    $("#trace-progress").style.width = `${(total / 6) * 100}%`;
  }
  if (event.status === "running") {
    const language = languages.find((l) => l.id === event.id);
    $("#trace-label").textContent =
      `${language.name} · ${language.role.toLowerCase()}`;
  }
}
function showAnswer(result, error = false) {
  answer.textContent = result;
  answer.classList.toggle("long", result.length > 15);
  answer.classList.toggle("error", error);
}
function insert(text, type = "value") {
  if (busy) return;
  if (justCalculated) {
    if (type === "operator" || text === "!" || text === "%" || text === "^2")
      input.value = "ans";
    else input.value = "";
    justCalculated = false;
  }
  const start = input.selectionStart ?? input.value.length,
    end = input.selectionEnd ?? start;
  if (type === "function" && start !== end) {
    const selected = input.value.slice(start, end);
    input.setRangeText(`${text}${selected})`, start, end, "end");
  } else input.setRangeText(text, start, end, "end");
  input.focus();
  $("#input-hint").textContent = "Ready to send through all six languages";
  $("#trace-note").textContent =
    "Expression updated. Press = to run all six languages.";
}
const categories = {
  scientific: [
    ["x²", "^2", "operator"],
    ["xʸ", "^", "operator"],
    ["√", "sqrt(", "function"],
    ["∛", "cbrt(", "function"],
    ["1/x", "recip(", "function"],
    ["x!", "!", "operator"],
    ["ln", "ln(", "function"],
    ["log₁₀", "log(", "function"],
    ["log₂", "log2(", "function"],
    ["eˣ", "exp(", "function"],
    ["nCr", "ncr(", "function"],
    ["nPr", "npr(", "function"],
  ],
  trig: [
    ["sin", "sin(", "function"],
    ["cos", "cos(", "function"],
    ["tan", "tan(", "function"],
    ["asin", "asin(", "function"],
    ["acos", "acos(", "function"],
    ["atan", "atan(", "function"],
    ["sinh", "sinh(", "function"],
    ["cosh", "cosh(", "function"],
    ["tanh", "tanh(", "function"],
    ["atan2", "atan2(", "function"],
    ["→ deg", "deg(", "function"],
    ["→ rad", "rad(", "function"],
  ],
  stats: [
    ["mean", "mean(", "function"],
    ["median", "median(", "function"],
    ["σ", "stdev(", "function"],
    ["variance", "variance(", "function"],
    ["Σ", "sum(", "function"],
    ["hypot", "hypot(", "function"],
    ["min", "min(", "function"],
    ["max", "max(", "function"],
    ["abs", "abs(", "function"],
    ["round", "round(", "function"],
    ["floor", "floor(", "function"],
    ["ceil", "ceil(", "function"],
  ],
};
function renderFunctions(category) {
  $("#function-keys").setAttribute("aria-labelledby", `tab-${category}`);
  $("#function-keys").innerHTML = categories[category]
    .map(
      ([label, text, type]) =>
        `<button data-insert="${escape(text)}" data-kind="${type}" title="${escape(text)}" aria-label="${escape(text)}">${label}</button>`,
    )
    .join("");
}
const keys = [
  ["AC", "clear", "clear"],
  ["(", "(", "utility"],
  [")", ")", "utility"],
  ["⌫", "backspace", "utility"],
  ["÷", "/", "operator"],
  ["7", "7"],
  ["8", "8"],
  ["9", "9"],
  ["π", "pi", "utility"],
  ["×", "*", "operator"],
  ["4", "4"],
  ["5", "5"],
  ["6", "6"],
  ["e", "e", "utility"],
  ["−", "-", "operator"],
  ["1", "1"],
  ["2", "2"],
  ["3", "3"],
  ["%", "%", "utility"],
  ["+", "+", "operator"],
  ["0", "0"],
  [".", "."],
  [",", ",", "utility"],
  ["Ans", "ans", "utility"],
  ["=", "calculate", "equal"],
];
$("#main-keys").innerHTML = keys
  .map(
    ([label, value, kind = "number"]) =>
      `<button class="${kind}" data-key="${value}" aria-label="${value === "backspace" ? "Backspace" : value === "clear" ? "Clear all" : value === "calculate" ? "Calculate" : value === "ans" ? "Previous answer" : label}"${value === "calculate" ? ' id="calculate"' : ""}>${label}</button>`,
  )
  .join("");
function clear() {
  if (busy) return;
  input.value = "";
  justCalculated = false;
  showAnswer("0");
  $("#input-hint").textContent = "Enter an expression or use the keys below";
  input.focus();
}
function backspace() {
  if (busy) return;
  const start = input.selectionStart ?? input.value.length,
    end = input.selectionEnd ?? start;
  input.setRangeText(
    "",
    start === end ? Math.max(0, start - 1) : start,
    end,
    "end",
  );
  justCalculated = false;
  input.focus();
}
function setBusy(value) {
  busy = value;
  input.readOnly = value;
  document
    .querySelectorAll(
      ".key-area button,.angle-control button,.example-list button,.history-entry,#precision",
    )
    .forEach((b) => (b.disabled = value));
  $("#calculate").textContent = value ? "…" : "=";
  $("#expression-label").textContent = value
    ? "SIX LANGUAGES ARE ON IT"
    : "YOUR EXPRESSION";
}
async function calculate(expression = input.value, memoryOperation = false) {
  if (busy) return;
  if (!expression.trim()) {
    input.focus();
    toast("Give the six languages something to do.");
    return;
  }
  resetTrace();
  setBusy(true);
  showAnswer("…");
  $("#input-hint").textContent = "Working through the language pipeline…";
  let completed = false;
  try {
    const response = await fetch("/api/calculate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        expression,
        mode,
        precision: Number($("#precision").value),
        ans: lastRaw,
      }),
    });
    if (!response.ok) {
      const data = await response.json();
      throw new Error(data.error || "The calculation could not start.");
    }
    const reader = response.body.getReader(),
      decoder = new TextDecoder();
    let pending = "";
    function handle(event) {
      if (event.type === "stage") updateStage(event);
      if (event.type === "error") throw new Error(event.message);
      if (event.type === "result") {
        completed = true;
        lastRaw = event.raw;
        showAnswer(event.result);
        justCalculated = true;
        $("#trace-label").textContent = "Six languages. One answer.";
        $("#trace-note").textContent =
          `Finished in ${(event.ms / 1000).toFixed(2)} s. Open a language row to inspect its output.`;
        $("#calculation-time").textContent =
          `6 languages · ${(event.ms / 1000).toFixed(2)} s`;
        $("#input-hint").textContent =
          `${mode} · ${$("#precision").value} significant digits · Enter to recalculate`;
        history.unshift({
          expression: event.expression,
          result: event.result,
          raw: event.raw,
          mode: event.mode,
          ms: event.ms,
        });
        history = history.slice(0, 30);
        if (memoryOperation) {
          memory = event.raw;
          input.value = expression;
          toast("Memory updated through all six languages.");
        }
        save();
        renderHistory();
        renderMemory();
      }
    }
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      pending += decoder.decode(value, { stream: true });
      let split;
      while ((split = pending.indexOf("\n")) >= 0) {
        const line = pending.slice(0, split);
        pending = pending.slice(split + 1);
        if (line) handle(JSON.parse(line));
      }
    }
    pending += decoder.decode();
    if (pending.trim()) handle(JSON.parse(pending));
    if (!completed)
      throw new Error(
        "The connection ended before all six languages finished.",
      );
  } catch (error) {
    showAnswer("Something doesn’t add up", true);
    $("#input-hint").textContent = error.message;
    $("#input-hint").title = error.message;
    $("#trace-label").textContent = "Calculation stopped";
    $("#trace-note").textContent = error.message;
    $("#calculation-time").textContent = "Expression needs attention.";
    justCalculated = false;
    document.querySelectorAll(".language.running").forEach((row) => {
      row.classList.remove("running");
      row.classList.add("error");
      row.querySelector(".language-state").textContent = "!";
    });
  } finally {
    setBusy(false);
    input.focus();
  }
}
function renderHistory() {
  $("#history-list").innerHTML = history.length
    ? history
        .slice(0, 5)
        .map(
          (h, i) =>
            `<button class="history-entry" data-history="${i}" title="Restore this expression (${escape(h.mode)})"><span>${escape(h.expression)} <small>${escape(h.mode)}</small></span><strong>= ${escape(h.result)}</strong></button>`,
        )
        .join("")
    : '<p class="history-empty">Your next questionable journey starts above.</p>';
}
function renderMemory() {
  $("#memory-indicator").hidden = memory === null;
  $("#memory-indicator").title =
    memory === null ? "Memory is empty" : `Stored: ${memory}`;
}
document.addEventListener("click", (event) => {
  const insertButton = event.target.closest("[data-insert]");
  if (insertButton)
    insert(insertButton.dataset.insert, insertButton.dataset.kind);
  const key = event.target.closest("[data-key]");
  if (key) {
    const value = key.dataset.key;
    if (value === "clear") clear();
    else if (value === "backspace") backspace();
    else if (value === "calculate") calculate();
    else
      insert(value, key.classList.contains("operator") ? "operator" : "value");
  }
  const tab = event.target.closest("[data-tab]");
  if (tab) {
    document.querySelectorAll("[data-tab]").forEach((t) => {
      t.classList.toggle("active", t === tab);
      t.setAttribute("aria-selected", String(t === tab));
    });
    renderFunctions(tab.dataset.tab);
  }
  const example = event.target.closest("[data-example]");
  if (example && !busy) {
    if (example.dataset.mode) setMode(example.dataset.mode);
    input.value = example.dataset.example;
    justCalculated = false;
    calculate();
  }
  const past = event.target.closest("[data-history]");
  if (past && !busy) {
    const item = history[Number(past.dataset.history)];
    input.value = item.expression;
    lastRaw = item.raw;
    setMode(item.mode);
    showAnswer(item.result);
    justCalculated = false;
    $("#input-hint").textContent =
      "Restored from history. Press Enter to run again.";
    input.focus();
  }
  const memoryButton = event.target.closest("[data-memory]");
  if (memoryButton && !busy) {
    switch (memoryButton.dataset.memory) {
      case "clear":
        memory = null;
        toast("Memory cleared.");
        break;
      case "recall":
        if (memory === null)
          toast("Memory is empty. Use MS to store an answer.");
        else insert(`(${memory})`);
        break;
      case "store":
        memory = lastRaw;
        toast("Full-precision answer stored.");
        break;
      case "add":
        calculate(`(${memory ?? "0"})+(${lastRaw})`, true);
        break;
      case "subtract":
        calculate(`(${memory ?? "0"})-(${lastRaw})`, true);
        break;
    }
    renderMemory();
    save();
  }
});
input.addEventListener("input", () => {
  justCalculated = false;
  $("#input-hint").textContent = "Ready to send through all six languages";
});
document.addEventListener("keydown", (event) => {
  if ($("#guide").open) return;
  if (
    event.key === "Enter" &&
    (event.target === input || event.target === document.body)
  ) {
    event.preventDefault();
    calculate();
  }
  if (event.key === "Escape") {
    event.preventDefault();
    clear();
  }
});
$("#deg").addEventListener("click", () => setMode("DEG"));
$("#rad").addEventListener("click", () => setMode("RAD"));
$("#clear-history").addEventListener("click", () => {
  history = [];
  save();
  renderHistory();
});
$("#copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(lastRaw);
    toast("Full-precision answer copied.");
  } catch {
    toast("Clipboard unavailable. You can select the answer to copy it.");
  }
});
$("#help-open").addEventListener("click", () => $("#guide").showModal());
$("#guide").addEventListener("click", (event) => {
  if (event.target === $("#guide")) {
    const r = $("#guide").getBoundingClientRect();
    if (
      event.clientX < r.left ||
      event.clientX > r.right ||
      event.clientY < r.top ||
      event.clientY > r.bottom
    )
      $("#guide").close();
  }
});
renderLanguages();
renderFunctions("scientific");
renderHistory();
renderMemory();
setMode(mode);
fetch("/api/health")
  .then((r) => r.json())
  .then((data) => {
    const count = data.languages.filter((l) => l.available).length;
    healthy = count === 6;
    const status = $("#runtime-status");
    status.replaceChildren(
      Object.assign(document.createElement("i"), {}),
      document.createTextNode(`${count}/6 engines online`),
    );
    status.classList.toggle("offline", !healthy);
    if (!healthy) {
      $("#trace-note").textContent =
        "Some runtimes are missing. Run npm run setup in the project folder, then restart WonkyCalc.";
    }
  })
  .catch(() => {
    const status = $("#runtime-status");
    status.textContent = "Backend offline";
    status.classList.add("offline");
    $("#trace-note").textContent =
      "Start the local calculator with npm start, then reload this page.";
  });
