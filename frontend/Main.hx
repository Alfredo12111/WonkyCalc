import js.Browser;
import haxe.Json;

using StringTools;

/** The browser application is authored in Haxe. app.js is compiler output. */
class Main {
	static var languages:Array<Dynamic> = [];
	static var history:Array<Dynamic> = [];
	static var mode = "DEG";
	static var busy = false;
	static var lastRaw = "0";
	static var memory:Null<String> = null;
	static var justCalculated = false;
	static var scalarAnswer = true;
	static var copyValue = "0";
	static var expected = 12;
	static var completed = new Map<String, Bool>();
	static var receipt:Dynamic;
	static var timer:Int;

	static function q(s:String):Dynamic
		return Browser.document.querySelector(s);

	static function all(s:String):Array<Dynamic>
		return [for (e in Browser.document.querySelectorAll(s)) e];

	static function esc(v:Dynamic):String
		return StringTools.htmlEscape(Std.string(v), true).replace("'", "&#39;");

	static function text(id:String, s:Dynamic)
		q(id).textContent = Std.string(s);

	static function seconds(ms:Float):String
		return Std.string(Math.round(ms / 10) / 100) + " s";

	static function toast(s:String) {
		text("#toast", s);
		q("#toast").hidden = false;
		Browser.window.clearTimeout(timer);
		timer = Browser.window.setTimeout(() -> q("#toast").hidden = true, 3200);
	}

	static function save() {
		try
			Browser.window.localStorage.setItem("wonkycalc-v1", Json.stringify({
				history: history,
				memory: memory,
				mode: mode,
				lastRaw: lastRaw
			}))
		catch (_:Dynamic) {}
	}

	static function setMode(v:String) {
		mode = v;
		for (k in ["DEG", "RAD"]) {
			var b = q("#" + k.toLowerCase());
			b.classList.toggle("active", k == mode);
			b.setAttribute("aria-pressed", Std.string(k == mode));
		}
		save();
	}

	static function renderLanguages() {
		var badges = [
			"rebol" => "Re",
			"raku" => "Ra",
			"prolog" => "Pr",
			"mercury" => "Me",
			"tcl" => "Tc",
			"eiffel" => "Ei",
			"j" => "J",
			"bqn" => "Bq",
			"factor" => "Fa",
			"rexx" => "Rx",
			"red" => "Rd",
			"icon" => "Ic"
		];
		q("#language-list").innerHTML = [
			for (l in languages)
				'<div class="language" data-id="${esc(l.id)}"><button class="language-header" aria-label="${esc(l.name)}: ${esc(l.role)}"><span class="language-icon">${badges[l.id]}</span><span class="language-text"><span class="language-name">${esc(l.name)}<span class="language-role">${esc(l.role)}</span></span><span class="language-description">${esc(l.description)}</span></span><span class="language-time">—</span><span class="language-state">·</span></button><details hidden><summary>Inspect output</summary><pre></pre></details></div>'
		].join("");
		for (b in all(".language-header"))
			b.addEventListener("click", function(_:Dynamic) {
				var d = b.nextElementSibling;
				if (!d.hidden)
					d.open = !d.open;
			});
	}

	static function resetTrace() {
		completed = new Map();
		renderLanguages();
		expected = 12;
		text("#trace-count", '0 / $expected');
		q("#trace-progress").style.width = "0%";
		text("#trace-label", "Taking the scenic route…");
		text("#trace-note", "Actual worker invocations. No imaginary progress bars.");
		q("#operation-graph").innerHTML = "";
		q("#handoff-list").innerHTML = "";
		q("#receipt").hidden = true;
		q("#homework-results").hidden = true;
		q("#explanation-panel").hidden = true;
		q("#build-status").hidden = true;
	}

	static function stage(e:Dynamic) {
		var row = q('.language[data-id="${e.id}"]');
		if (row == null)
			return;
		for (s in ["running", "complete", "error"])
			row.classList.remove(s);
		row.classList.add(e.status);
		row.querySelector(".language-state").textContent = e.status == "running" ? "" : e.status == "complete" ? "✓" : "!";
		if (e.ms != null)
			row.querySelector(".language-time")
				.textContent = (e.calls > 1 ? e.calls + "× · " : "") + (e.ms >= 1000 ? seconds(e.ms) : Math.round(e.ms) + " ms");
		if (e.output != null || e.message != null) {
			var d = row.querySelector("details");
			d.hidden = false;
			d.querySelector("pre").textContent = e.output != null ? e.output : e.message;
		}
		if (e.status == "complete")
			completed[e.id] = true;
		var count = [for (k in completed.keys()) k].length;
		text("#trace-count", '$count / $expected');
		q("#trace-progress").style.width = (100 * count / expected) + "%";
		if (e.status == "running")
			text("#trace-label", e.id + " · " + (e.label == null ? "working" : e.label));
	}

	static function answer(s:String, error = false) {
		text("#answer", s);
		q("#answer").classList.toggle("long", s.length > 15);
		q("#answer").classList.toggle("error", error);
	}

	static function insert(s:String, kind = "value") {
		if (busy)
			return;
		var input = q("#expression");
		if (justCalculated) {
			input.value = kind == "operator" || s == "!" || s == "%" || s == "^2" ? "ans" : "";
			justCalculated = false;
		}
		var start:Int = input.selectionStart, end:Int = input.selectionEnd;
		if (kind == "function" && start != end)
			input.setRangeText(s + input.value.substring(start, end) + ")", start, end, "end");
		else
			input.setRangeText(s, start, end, "end");
		input.focus();
		text("#input-hint", "Ready for an unnecessarily long journey");
	}

	static function clear() {
		if (busy)
			return;
		q("#expression").value = "";
		justCalculated = false;
		answer("0");
		text("#input-hint", "Enter an expression or use the keys below");
		q("#expression").focus();
	}

	static function backspace() {
		if (busy)
			return;
		var i = q("#expression");
		var a:Int = i.selectionStart, b:Int = i.selectionEnd;
		i.setRangeText("", a == b ? Std.int(Math.max(0, a - 1)) : a, b, "end");
		justCalculated = false;
		i.focus();
	}

	static function setBusy(v:Bool) {
		busy = v;
		q("#expression").readOnly = v;
		for (b in all(".key-area button,.angle-control button,.example-list button,.history-entry,#precision"))
			b.disabled = v;
		text("#calculate", v ? "…" : "=");
		text("#expression-label", v ? "THE COMMITTEE IS ON IT" : "YOUR EXPRESSION");
	}

	static function renderFunctions(category:String) {
		var buttons:Array<Array<String>> = switch (category) {
			case "trig": [
					["sin", "sin("],
					["cos", "cos("],
					["tan", "tan("],
					["asin", "asin("],
					["acos", "acos("],
					["atan", "atan("],
					["sinh", "sinh("],
					["cosh", "cosh("],
					["tanh", "tanh("],
					["atan2", "atan2("],
					["→ deg", "deg("],
					["→ rad", "rad("]
				];
			case "stats": [
					["mean", "mean("],
					["median", "median("],
					["σ", "stdev("],
					["variance", "variance("],
					["Σ", "sum("],
					["hypot", "hypot("],
					["min", "min("],
					["max", "max("],
					["abs", "abs("],
					["round", "round("],
					["floor", "floor("],
					["ceil", "ceil("]
				];
			case "arrays": [
					["[ ]", "[", "value"],
					["]", "]", "value"],
					["dot", "dot("],
					["A × B", "matmul("],
					["det", "det("],
					["Aᵀ", "transpose("],
					["norm", "norm("],
					["metres", " m", "value"],
					["seconds", " s", "value"],
					["kg", " kg", "value"],
					["cm", " cm", "value"],
					["km", " km", "value"]
				];
			default: [
					["x²", "^2", "operator"],
					["xʸ", "^", "operator"],
					["√", "sqrt("],
					["∛", "cbrt("],
					["1/x", "recip("],
					["x!", "!", "operator"],
					["ln", "ln("],
					["log₁₀", "log("],
					["log₂", "log2("],
					["eˣ", "exp("],
					["nCr", "ncr("],
					["nPr", "npr("]
				];
		};
		q("#function-keys").setAttribute("aria-labelledby", "tab-" + category);
		q("#function-keys").innerHTML = [
			for (b in buttons)
				'<button data-insert="${esc(b[1])}" data-kind="${b.length > 2 ? b[2] : "function"}" title="${esc(b[1])}" aria-label="${esc(b[0])}">${esc(b[0])}</button>'
		].join("");
	}

	static function renderHistory() {
		q("#history-list").innerHTML = history.length == 0 ? '<p class="history-empty">Your next questionable journey starts above.</p>' : [
			for (i in 0...Std.int(Math.min(5, history.length)))
				'<button class="history-entry" data-history="$i"><span>${esc(history[i].expression)} <small>${esc(history[i].mode)}</small></span><strong>= ${esc(history[i].result)}</strong></button>'
		].join("");
	}

	static function renderMemory() {
		q("#memory-indicator").hidden = memory == null;
		q("#memory-indicator").title = memory == null ? "Memory is empty" : "Stored: " + memory;
	}

	static function renderHomework(h:Dynamic) {
		q("#homework-results").hidden = false;
		var rows = '<div><b>J / BQN</b><code>${esc(h.j)}</code></div>';
		for (name in ["factor", "rexx"]) {
			var v:Dynamic = Reflect.field(h, name);
			rows += '<div><b>${name == "factor" ? "Factor" : "Rexx · 50 digits"}</b><code class="${v.status == "ok" ? "" : "unsupported"}">${v.status == "ok" ? esc(v.result) : "Not supported: " + esc(v.result)}</code></div>';
		}
		q("#homework-values").innerHTML = rows;
		text("#decimal-difference",
			h.rexx.status == "ok" ? "Rexx − J: " + h.rexx.delta +
				". More digits do not imply an exact answer." : "Unsupported checks are reported explicitly. The primary result still comes from J / BQN.");
	}

	static function renderReceipt(e:Dynamic) {
		receipt = e;
		q("#receipt").hidden = false;
		var r = e.receipt;
		q("#receipt-grid")
			.innerHTML = '<div><strong>${r.languages.length}</strong><span>languages ran</span></div><div><strong>${r.processes}</strong><span>worker launches</span></div><div><strong>${r.payloadBytes}</strong><span>payload bytes</span></div><div><strong>${seconds(e.ms)}</strong><span>door to door</span></div>';
		text("#receipt-timing",
			r.numericMs
			+ " ms in J/BQN evaluation · "
			+ r.overheadMs
			+ " ms startup, I/O and checks"
			+ (r.buildMs > 0 ? " · " + r.buildMs + " ms rebuilding" : ""));
		text("#explanation", e.explanation);
		q("#explanation-panel").hidden = false;
		renderHomework(e.homework);
	}

	static function calculate(?expression:String, memoryOperation = false) {
		if (busy)
			return;
		if (expression == null)
			expression = q("#expression").value;
		if (expression.trim() == "") {
			toast("Give the committee something to do.");
			return;
		}
		var source = expression, finished = false;
		resetTrace();
		setBusy(true);
		answer("…");
		text("#input-hint", "Rebuilding three workers, then taking every detour…");
		text("#calculation-time", "Rebuild and calculation in progress…");
		function fail(error:Dynamic) {
			answer("Something doesn’t add up", true);
			var message = error.message != null ? Std.string(error.message) : Std.string(error);
			text("#input-hint", message);
			q("#input-hint").title = message;
			text("#trace-label", "Calculation stopped");
			text("#trace-note", message);
			text("#calculation-time", "Expression needs attention.");
			justCalculated = false;
			setBusy(false);
		}
		function handle(e:Dynamic) {
			switch (e.type) {
				case "route":
					expected = e.expected;
				case "stage":
					stage(e);
				case "build":
					q("#build-status").hidden = false;
					text("#build-status", e.message + (e.ms != null ? " " + seconds(e.ms) : ""));
					text("#trace-label", e.status == "running" ? "Rebuilding three workers…" : "Starting twelve workers…");
				case "node":
					var row = Browser.document.createElement("div");
					row.className = "graph-node";
					var refs:Array<Dynamic> = e.inputs;
					row.innerHTML = '<span class="node-number">#${esc(e.id)}</span><div><b>${esc(e.kind == "N" ? "literal" : e.op)}</b><small>${refs.length > 0 ? refs.map(v -> "#" + v).join(" + ") + " → #" + e.id : "from Raku"} · ${esc(e.handoff)}</small></div><code>${esc(e.value)}</code>';
					q("#operation-graph").appendChild(row);
				case "handoff":
					var row = Browser.document.createElement("li");
					var parents:Array<Dynamic> = e.parents;
					row.innerHTML = '<b>${esc(e.key)} · ${esc(e.name)}</b> ${esc(e.label)}<small>${parents.length > 0 ? esc(parents.join(", ")) + " → " : ""}${esc(e.key)} · ${e.ms} ms · ${e.bytes} B</small>';
					q("#handoff-list").appendChild(row);
				case "error":
					throw new haxe.Exception(e.message);
				case "result":
					finished = true;
					scalarAnswer = e.shape.length == 0 && e.unit == "";
					if (scalarAnswer)
						lastRaw = e.raw;
					copyValue = e.raw + (e.unit != "" ? " " + e.unit : "");
					answer(e.result);
					justCalculated = scalarAnswer;
					text("#trace-label", e.receipt.languages.length + " languages. One answer.");
					text("#trace-note", "Finished in " + seconds(e.ms) + ". Open any language to inspect its latest output.");
					text("#calculation-time", e.receipt.processes + " processes · " + seconds(e.ms));
					text("#input-hint",
						mode
						+ " · "
						+ q("#precision").value
						+ " significant digits"
						+ (!scalarAnswer ? " · Ans retains the last dimensionless scalar" : " · Enter to recalculate"));
					history.unshift({
						expression: e.expression,
						result: e.result,
						raw: e.raw,
						unit: e.unit,
						mode: e.mode,
						ms: e.ms,
						scalar: scalarAnswer
					});
					history = history.slice(0, 30);
					if (memoryOperation) {
						memory = e.raw;
						q("#expression").value = source;
						toast("Memory updated through the committee.");
					}
					renderReceipt(e);
					save();
					renderHistory();
					renderMemory();
			}
		}
		var request = {
			expression: source,
			mode: mode,
			precision: Std.parseInt(q("#precision").value),
			ans: lastRaw
		};
		var fetch:js.lib.Promise<Dynamic> = cast Browser.window.fetch("/api/calculate",
			{method: "POST", headers: {"Content-Type": "application/json"}, body: Json.stringify(request)});
		fetch.then(function(response:Dynamic) {
			if (!response.ok)
				return response.json().then(function(d:Dynamic) {
					throw new haxe.Exception(d.error);
				});
			var reader:Dynamic = response.body.getReader(), decoder = new js.html.TextDecoder(), pending = "";
			function pump():Dynamic
				return reader.read().then(function(chunk:Dynamic):Dynamic {
					if (chunk.done) {
						pending += decoder.decode();
						if (pending.trim() != "")
							handle(Json.parse(pending));
						if (!finished)
							throw new haxe.Exception("The connection ended before the calculation finished.");
						setBusy(false);
						q("#expression").focus();
						return null;
					}
					pending += decoder.decode(chunk.value, {stream: true});
					var split = pending.indexOf("\n");
					while (split >= 0) {
						var line = pending.substr(0, split);
						pending = pending.substr(split + 1);
						if (line != "")
							handle(Json.parse(line));
						split = pending.indexOf("\n");
					}
					return pump();
				});
			return pump();
		}).catchError(fail);
	}

	static function main() {
		try {
			var saved:Dynamic = Json.parse(Browser.window.localStorage.getItem("wonkycalc-v1"));
			if (saved != null) {
				if (Std.isOfType(saved.history, Array))
					history = (cast saved.history : Array<Dynamic>).filter(h -> Std.isOfType(h.expression, String) && Std.isOfType(h.result, String))
						.slice(0, 30);
				if (saved.mode == "RAD")
					mode = "RAD";
				if (Std.isOfType(saved.lastRaw, String) && Math.isFinite(Std.parseFloat(saved.lastRaw)))
					lastRaw = saved.lastRaw;
				if (Std.isOfType(saved.memory, String) && Math.isFinite(Std.parseFloat(saved.memory)))
					memory = saved.memory;
			}
		} catch (_:Dynamic) {}
		var keys = [
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
			["=", "calculate", "equal"]
		];
		q("#main-keys").innerHTML = [
			for (k in keys)
				'<button class="${k.length > 2 ? k[2] : "number"}" data-key="${k[1]}" aria-label="${k[1] == "calculate" ? "Calculate" : k[1] == "backspace" ? "Backspace" : k[1] == "clear" ? "Clear all" : k[0]}"${k[1] == "calculate" ? ' id="calculate"' : ""}>${k[0]}</button>'
		].join("");
		Browser.document.addEventListener("click", function(event:Dynamic) {
			var target:Dynamic = event.target,
				b:Dynamic = target.closest("[data-insert]");
			if (b != null)
				insert(b.dataset.insert, b.dataset.kind);
			b = target.closest("[data-key]");
			if (b != null)
				switch (b.dataset.key) {
					case "clear":
						clear();
					case "backspace":
						backspace();
					case "calculate":
						calculate();
					default:
						insert(b.dataset.key, b.classList.contains("operator") ? "operator" : "value");
				}
			b = target.closest("[data-tab]");
			if (b != null) {
				for (t in all("[data-tab]")) {
					t.classList.toggle("active", t == b);
					t.setAttribute("aria-selected", Std.string(t == b));
				}
				renderFunctions(b.dataset.tab);
			}
			b = target.closest("[data-example]");
			if (b != null && !busy) {
				if (b.dataset.mode != null)
					setMode(b.dataset.mode);
				q("#expression").value = b.dataset.example;
				justCalculated = false;
				calculate();
			}
			b = target.closest("[data-history]");
			if (b != null && !busy) {
				var h = history[Std.parseInt(b.dataset.history)];
				resetTrace();
				q("#expression").value = h.expression;
				setMode(h.mode);
				answer(h.result);
				scalarAnswer = h.scalar != false;
				copyValue = h.raw + (h.unit != null && h.unit != "" ? " " + h.unit : "");
				if (scalarAnswer)
					lastRaw = h.raw;
				justCalculated = false;
				text("#input-hint", "Restored from history. Press Enter to run again.");
			}
			b = target.closest("[data-memory]");
			if (b != null && !busy) {
				switch (b.dataset.memory) {
					case "clear":
						memory = null;
						toast("Memory cleared.");
					case "recall":
						if (memory == null)
							toast("Memory is empty. Use MS to store a scalar answer.");
						else
							insert('($memory)');
					case "store":
						if (scalarAnswer) {
							memory = lastRaw;
							toast("Full-precision scalar stored.");
						} else
							toast("Memory holds dimensionless scalar answers.");
					case "add", "subtract":
						if (!scalarAnswer)
							toast("Memory holds dimensionless scalar answers.");
						else
							calculate('(${memory == null ? "0" : memory})${b.dataset.memory == "add" ? "+" : "-"}($lastRaw)', true);
				}
				renderMemory();
				save();
			}
		});
		q("#expression").addEventListener("input", function(_:Dynamic) {
			justCalculated = false;
			text("#input-hint", "Ready for an unnecessarily long journey");
		});
		Browser.document.addEventListener("keydown", function(e:Dynamic) {
			if (q("#guide").open)
				return;
			if (e.key == "Enter" && (e.target == q("#expression") || e.target == Browser.document.body)) {
				e.preventDefault();
				calculate();
			}
			if (e.key == "Escape") {
				e.preventDefault();
				clear();
			}
		});
		q("#deg").onclick = (_:Dynamic) -> setMode("DEG");
		q("#rad").onclick = (_:Dynamic) -> setMode("RAD");
		q("#clear-history").onclick = function(_:Dynamic) {
			history = [];
			save();
			renderHistory();
		};
		q("#help-open").onclick = (_:Dynamic) -> q("#guide").showModal();
		q("#copy").onclick = function(_:Dynamic) {
			var nav:Dynamic = Browser.navigator;
			var p:js.lib.Promise<Dynamic> = nav.clipboard.writeText(copyValue);
			p.then((_:Dynamic) -> toast("Full-precision answer copied.")).catchError((_:Dynamic) -> toast("Select the answer to copy it."));
		};
		q("#download-receipt").onclick = function(_:Dynamic) {
			if (receipt == null)
				return;
			var blob = new js.html.Blob([Json.stringify(receipt, null, "  ")], {type: "application/json"});
			var url = js.html.URL.createObjectURL(blob);
			var a = Browser.document.createAnchorElement();
			a.href = url;
			a.download = "wonkycalc-receipt.json";
			a.click();
			Browser.window.setTimeout(() -> js.html.URL.revokeObjectURL(url), 1000);
		};
		renderFunctions("scientific");
		renderHistory();
		renderMemory();
		setMode(mode);
		var fetch:js.lib.Promise<Dynamic> = cast Browser.window.fetch("/api/health");
		fetch.then((r:Dynamic) -> r.json()).then(function(data:Dynamic) {
			languages = cast data.languages;
			renderLanguages();
			var count = languages.filter(l -> l.available).length;
			text("#runtime-status", '$count/12 engines + Haxe UI');
			q("#runtime-status").classList.toggle("offline", count != 12);
			if (count != 12)
				text("#trace-note", "Some runtimes need setup. Run npm run setup, then restart WonkyCalc.");
		}).catchError(function(_:Dynamic) {
			text("#runtime-status", "Backend offline");
			q("#runtime-status").classList.add("offline");
		});
	}
}
