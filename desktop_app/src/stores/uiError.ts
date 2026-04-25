const CHINESE_CHAR_PATTERN = /[\u3400-\u9fff]/;

function extractErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.trim();
  }
  return String(error).trim();
}

export function normalizeUserFacingError(
  error: unknown,
  fallbackMessage: string
): string {
  const message = extractErrorMessage(error);
  if (!message) {
    return fallbackMessage;
  }
  return CHINESE_CHAR_PATTERN.test(message) ? message : fallbackMessage;
}
