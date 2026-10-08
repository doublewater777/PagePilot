import assert from "node:assert/strict";
import test from "node:test";
import { main } from "../functions/pagepilotFeedback/entry.js";

const event = {
  appInstanceId: "test-instance",
  appSignature: "pagepilot-app-signature-v1",
  message: "  Reader suggestion  ",
  appVersion: "1.0.22",
  osVersion: "iOS 26"
};

function options(overrides = {}) {
  return {
    consumeRateLimit: async () => true,
    writeFeedback: async () => {},
    sendNotification: async () => {},
    ...overrides
  };
}

test("stores and notifies PagePilot feedback with trimmed content", async () => {
  let stored;
  let notified;
  const result = await main(event, {}, options({
    writeFeedback: async record => { stored = record; },
    sendNotification: async ({ record }) => { notified = record; return true; }
  }));
  assert.equal(result.ok, true);
  assert.equal(result.notificationDelivered, true);
  assert.equal(stored.message, "Reader suggestion");
  assert.equal(stored.appVersion, "1.0.22");
  assert.equal(stored.appInstanceId, undefined);
  assert.deepEqual(notified, stored);
});

test("notification failure does not discard stored feedback", async () => {
  const result = await main(event, {}, options({
    sendNotification: async () => { throw new Error("Feishu unavailable"); }
  }));
  assert.equal(result.ok, true);
  assert.equal(result.notificationDelivered, false);
});

test("rejects BeforeShow credentials", async () => {
  const result = await main({...event, appSignature: "beforeshow-app-signature-v1"}, {}, options());
  assert.equal(result.error.code, "APP_AUTH_INVALID");
});

test("rejects blank and over-limit messages without writing", async () => {
  const noWrite = options({writeFeedback: async () => assert.fail("must not write")});
  assert.equal((await main({...event, message: " \n "}, {}, noWrite)).error.code, "MESSAGE_REQUIRED");
  assert.equal((await main({...event, message: "😀".repeat(2001)}, {}, noWrite)).error.code, "MESSAGE_TOO_LONG");
  assert.equal((await main({...event, message: "😀".repeat(2000)}, {}, options())).ok, true);
});

test("reports rate limit and database failure", async () => {
  assert.equal((await main(event, {}, options({consumeRateLimit: async () => false}))).error.code, "RATE_LIMITED");
  assert.equal((await main(event, {}, options({writeFeedback: async () => {throw new Error("offline");}}))).error.code, "STORE_FAILED");
});
