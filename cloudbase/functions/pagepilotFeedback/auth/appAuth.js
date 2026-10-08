class AppAuthError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "AppAuthError";
    this.code = code;
  }
}

export function assertAppAuthenticated(event = {}, context = {}) {
  const clientContext = context.clientContext ?? {};
  const appInstanceId =
    event.appInstanceId ??
    clientContext.appInstanceId ??
    context.appInstanceId;
  const appSignature =
    event.appSignature ??
    clientContext.appSignature ??
    context.appSignature;

  if (!isNonEmptyString(appInstanceId) || !isNonEmptyString(appSignature)) {
    throw new AppAuthError(
      "APP_AUTH_REQUIRED",
      "Generation calls require app-level authentication."
    );
  }

  return {
    appInstanceId,
    accountless: true
  };
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}
