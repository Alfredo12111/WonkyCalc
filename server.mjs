import http from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { calculate, health, ROOT, validateRequest } from "./runtime.mjs";

const port = Number(process.env.PORT || 3210);
let running = 0;
const files = {
  "/": "index.html",
  "/app.js": "app.js",
  "/style.css": "style.css",
  "/favicon.svg": "favicon.svg",
};
const mime = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
};
const server = http.createServer(async (req, res) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader(
    "Content-Security-Policy",
    "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'",
  );
  const reply = (code, data) => {
    res.writeHead(code, { "Content-Type": "application/json" });
    res.end(JSON.stringify(data));
  };
  if (![`127.0.0.1:${port}`, `localhost:${port}`].includes(req.headers.host))
    return reply(403, { error: "Local requests only." });
  const url = new URL(req.url, `http://127.0.0.1:${port}`);
  if (req.method === "GET" && url.pathname === "/api/health")
    return reply(200, { languages: await health() });
  if (req.method === "POST" && url.pathname === "/api/calculate") {
    if (
      req.headers.origin &&
      ![`http://127.0.0.1:${port}`, `http://localhost:${port}`].includes(
        req.headers.origin,
      )
    )
      return reply(403, { error: "Local requests only." });
    if (!req.headers["content-type"]?.startsWith("application/json"))
      return reply(415, { error: "Send application/json." });
    if (running >= 3)
      return reply(429, {
        error: "Three calculations are already running. Try again shortly.",
      });
    let body = "",
      oversized = false;
    for await (const chunk of req) {
      body += chunk;
      if (body.length > 16384) {
        oversized = true;
        break;
      }
    }
    if (oversized) return reply(413, { error: "Request is too large." });
    let input;
    try {
      input = validateRequest(JSON.parse(body));
    } catch (e) {
      return reply(400, { error: e.message });
    }
    const controller = new AbortController();
    res.on("close", () => {
      if (!res.writableEnded) controller.abort();
    });
    running++;
    res.writeHead(200, {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "X-Accel-Buffering": "no",
    });
    const emit = (event) => {
      if (!res.destroyed) res.write(JSON.stringify(event) + "\n");
    };
    try {
      const result = await calculate(input, emit, controller.signal);
      emit({ type: "result", ...result });
    } catch (error) {
      emit({ type: "error", message: error.message, stage: error.stage });
    } finally {
      running--;
      res.end();
    }
    return;
  }
  if (req.method === "GET" && files[url.pathname]) {
    try {
      const file = files[url.pathname];
      res.writeHead(200, { "Content-Type": mime[path.extname(file)] });
      res.end(await readFile(path.join(ROOT, "public", file)));
    } catch {
      res.end("Unable to load WonkyCalc.");
    }
    return;
  }
  reply(404, { error: "Not found." });
});
server.listen(port, "127.0.0.1", () =>
  console.log(`WonkyCalc is ready: http://127.0.0.1:${port}`),
);
server.on("error", (e) => {
  console.error(e.message);
  process.exitCode = 1;
});
