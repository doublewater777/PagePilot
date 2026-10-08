import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import { assertAppAuthenticated } from "./auth/appAuth.js";

const MAX_MESSAGE_LENGTH = 2000;
const MAX_DIAGNOSTIC_LENGTH = 160;
const EXPECTED_APP_SIGNATURE = "pagepilot-app-signature-v1";
const RATE_LIMIT_COLLECTION = "pagepilotFeedbackRateLimits";
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_INSTANCE_PER_WINDOW = 5;
const MAX_GLOBAL_PER_WINDOW = 120;

export async function main(event = {}, context = {}, options = {}) {
  const body = parseRequestBody(event);
  const auth = assertAppAuthenticated(authEvent(event, body), context);

  if (!matchesExpectedSignature(
    body?.appSignature ?? event.appSignature ?? context.appSignature,
    options.expectedAppSignature ?? EXPECTED_APP_SIGNATURE
  )) {
    return errorResponse("APP_AUTH_INVALID", "Invalid app authentication.");
  }

  const rawMessage = typeof body?.message === "string" ? body.message : "";
  const message = rawMessage.trim();

  if (message.length === 0) {
    return errorResponse("MESSAGE_REQUIRED", "Feedback message is required.");
  }

  if (Array.from(rawMessage).length > MAX_MESSAGE_LENGTH) {
    return errorResponse("MESSAGE_TOO_LONG", "Feedback message is too long.");
  }

  const now = options.now?.() ?? new Date();
  const consumeRateLimit = options.consumeRateLimit ?? consumeFeedbackRateLimit;

  let allowed;
  try {
    allowed = await consumeRateLimit({
      appInstanceId: auth.appInstanceId,
      now
    });
  } catch {
    // Fail closed: if the limiter is unavailable, do not expose an unbounded write path.
    return errorResponse("RATE_LIMIT_UNAVAILABLE", "Feedback rate limit is unavailable.");
  }

  if (!allowed) {
    return errorResponse("RATE_LIMITED", "Too many feedback submissions.");
  }

  const feedbackId = (options.randomUUID ?? randomUUID)();
  const record = {
    feedbackId,
    message,
    appVersion: normalizeDiagnostic(body?.appVersion),
    osVersion: normalizeDiagnostic(body?.osVersion),
    submittedAt: now.toISOString()
  };

  try {
    const writeFeedback = options.writeFeedback ?? writeFeedbackToCloudDatabase;
    await writeFeedback(record);

    let notificationDelivered = false;
    try {
      const notify = options.sendNotification ?? sendFeishuFeedbackNotification;
      notificationDelivered = await notify({ record }) === true;
    } catch (notifyError) {
      console.error("Feishu notification error:", notifyError);
    }

    return {
      ok: true,
      feedbackId,
      notificationDelivered
    };
  } catch {
    return errorResponse("STORE_FAILED", "Feedback could not be stored.");
  }
}

function matchesExpectedSignature(received, expected) {
  if (typeof received !== "string" || typeof expected !== "string") {
    return false;
  }

  const receivedBuffer = Buffer.from(received);
  const expectedBuffer = Buffer.from(expected);
  return receivedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(receivedBuffer, expectedBuffer);
}

async function consumeFeedbackRateLimit({ appInstanceId, now }) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const app = cloudbase.init({});
  const db = app.database();
  await ensureCollection(db, RATE_LIMIT_COLLECTION);

  const windowStart = Math.floor(now.getTime() / RATE_LIMIT_WINDOW_MS) * RATE_LIMIT_WINDOW_MS;
  const expiresAt = new Date(windowStart + (2 * RATE_LIMIT_WINDOW_MS)).toISOString();
  const instanceHash = createHash("sha256")
    .update(`${windowStart}:${String(appInstanceId)}`)
    .digest("hex");
  const globalDocumentId = `global-${windowStart}`;
  const instanceDocumentId = `instance-${windowStart}-${instanceHash}`;

  let allowed = false;
  const result = await db.runTransaction(async transaction => {
    const globalRef = transaction.collection(RATE_LIMIT_COLLECTION).doc(globalDocumentId);
    const instanceRef = transaction.collection(RATE_LIMIT_COLLECTION).doc(instanceDocumentId);

    const globalResult = await safeGetDoc(globalRef);
    const instanceResult = await safeGetDoc(instanceRef);
    const globalCount = documentCount(globalResult);
    const instanceCount = documentCount(instanceResult);

    if (globalCount >= MAX_GLOBAL_PER_WINDOW ||
        instanceCount >= MAX_PER_INSTANCE_PER_WINDOW) {
      allowed = false;
      return { allowed: false };
    }

    await globalRef.set({
      scope: "global",
      count: globalCount + 1,
      windowStart,
      expiresAt
    });
    await instanceRef.set({
      scope: "instance",
      count: instanceCount + 1,
      windowStart,
      expiresAt
    });

    allowed = true;
    return { allowed: true };
  });

  return allowed || result?.result?.allowed === true || result?.allowed === true;
}

async function safeGetDoc(docRef) {
  try {
    return await docRef.get();
  } catch (error) {
    if (error?.code === "DATABASE_TRANSACTION_DOC_NOT_EXIST" ||
        error?.message?.includes("not exist") ||
        error?.message?.includes("NOT_FOUND")) {
      return null;
    }
    throw error;
  }
}

function documentCount(result) {
  const data = typeof result?.data === "function" ? result.data() : result?.data;
  if (Array.isArray(data)) {
    return Number(data[0]?.count ?? 0);
  }
  return Number(data?.count ?? 0);
}

async function writeFeedbackToCloudDatabase(record) {
  const { default: cloudbase } = await import("@cloudbase/node-sdk");
  const app = cloudbase.init({});
  const db = app.database();
  const collectionName = "pagepilotUserFeedback";
  await ensureCollection(db, collectionName);
  await db.collection(collectionName).add(record);
}

async function ensureCollection(db, collectionName) {
  try {
    await db.collection(collectionName).limit(1).get();
  } catch (error) {
    if (error?.code !== "DATABASE_COLLECTION_NOT_EXIST") {
      throw error;
    }

    try {
      await db.createCollection(collectionName);
    } catch (createError) {
      if (createError?.code !== "DATABASE_COLLECTION_ALREADY_EXIST") {
        throw createError;
      }
    }
  }
}

function normalizeDiagnostic(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, MAX_DIAGNOSTIC_LENGTH);
}

function errorResponse(code, message) {
  return {
    ok: false,
    error: {
      code,
      message
    }
  };
}

function parseRequestBody(event) {
  if (typeof event.body === "string") {
    try {
      return JSON.parse(event.body);
    } catch {
      return event.body;
    }
  }

  return event.body ?? event;
}

function authEvent(event, body) {
  if (body !== null && typeof body === "object" && !Array.isArray(body)) {
    return { ...event, ...body };
  }

  return event;
}

async function sendFeishuFeedbackNotification(options = {}) {
  const appId = options.feishuAppId ?? process.env.FEISHU_APP_ID;
  const appSecret = options.feishuAppSecret ?? process.env.FEISHU_APP_SECRET;
  const chatId = options.feishuChatId ?? process.env.FEISHU_CHAT_ID;
  const webhookUrl = options.feishuWebhookUrl ?? process.env.FEISHU_WEBHOOK_URL;
  const record = options.record;
  if (!record) return;

  const card = {
    header: {
      title: {
        tag: "plain_text",
        content: "收到新的 PagePilot 用户反馈"
      },
      template: "blue"
    },
    elements: [
      {
        tag: "div",
        text: {
          tag: "lark_md",
          content: `**反馈内容：**\n${record.message}`
        }
      },
      {
        tag: "hr"
      },
      {
        tag: "div",
        fields: [
          {
            is_short: true,
            text: {
              tag: "lark_md",
              content: `**App 版本：**\n${record.appVersion || "未知"}`
            }
          },
          {
            is_short: true,
            text: {
              tag: "lark_md",
              content: `**系统版本：**\n${record.osVersion || "未知"}`
            }
          },
          {
            is_short: true,
            text: {
              tag: "lark_md",
              content: `**提交时间：**\n${record.submittedAt}`
            }
          },
          {
            is_short: true,
            text: {
              tag: "lark_md",
              content: `**反馈 ID：**\n${record.feedbackId}`
            }
          }
        ]
      }
    ]
  };

  if (webhookUrl) {
    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        msg_type: "interactive",
        card
      })
    });
    const result = await response.json();
    if (!response.ok || (result.code ?? result.StatusCode) !== 0) {
      throw new Error("Feishu webhook notification failed.");
    }
    console.info("Feishu feedback delivered:", record.feedbackId);
    return true;
  }

  if (appId && appSecret && chatId) {
    const tokenRes = await fetch("https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ app_id: appId, app_secret: appSecret })
    });
    const tokenData = await tokenRes.json().catch(() => null);
    if (!tokenRes.ok || !tokenData?.tenant_access_token) {
      throw new Error("Feishu token request failed.");
    }

    const messageRes = await fetch("https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${tokenData.tenant_access_token}`
      },
      body: JSON.stringify({
        receive_id: chatId,
        msg_type: "interactive",
        content: JSON.stringify(card)
      })
    });
    const messageData = await messageRes.json();
    if (!messageRes.ok || messageData.code !== 0) {
      throw new Error(`Feishu notification failed (code ${messageData.code}).`);
    }
    console.info("Feishu feedback delivered:", record.feedbackId, messageData.data?.message_id);
    return true;
  }
}
