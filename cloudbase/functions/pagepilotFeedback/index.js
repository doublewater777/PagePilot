import http from "node:http";
import { main } from "./entry.js";

const PORT = process.env.PORT || 9000;

const server = http.createServer(async (req, res) => {
  res.setHeader("Content-Type", "application/json");

  if (req.method !== "POST") {
    res.statusCode = 405;
    res.end(JSON.stringify({
      ok: false,
      error: { code: "METHOD_NOT_ALLOWED", message: "Only POST is supported" }
    }));
    return;
  }

  let body = "";
  req.on("data", (chunk) => {
    body += chunk;
  });

  req.on("end", async () => {
    try {
      const event = body.length > 0 ? JSON.parse(body) : {};
      const result = await main(event, {}, {});
      res.statusCode = 200;
      res.end(JSON.stringify(result));
    } catch (error) {
      res.statusCode = 500;
      res.end(JSON.stringify({
        ok: false,
        error: { code: "INTERNAL_ERROR", message: error.message }
      }));
    }
  });
});

server.listen(PORT, () => {
  console.log(`pagepilotFeedback web server listening on port ${PORT}`);
});
