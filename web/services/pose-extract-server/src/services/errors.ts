export class AppError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(message: string, statusCode: number, code: string) {
    super(message);
    this.name = this.constructor.name;
    this.statusCode = statusCode;
    this.code = code;
  }
}

export class InvalidImageError extends AppError {
  constructor(message = "Invalid image") {
    super(message, 400, "INVALID_IMAGE");
  }
}

export class ImageTooLargeError extends AppError {
  constructor(message = "Image too large") {
    super(message, 413, "IMAGE_TOO_LARGE");
  }
}

export class RateLimitedError extends AppError {
  constructor(message = "Too many requests") {
    super(message, 429, "RATE_LIMITED");
  }
}

export class AllKeysExhaustedError extends AppError {
  constructor(message = "All API keys exhausted") {
    super(message, 503, "ALL_KEYS_EXHAUSTED");
  }
}

export class GeminiError extends AppError {
  constructor(message = "Gemini API failed") {
    super(message, 500, "GEMINI_ERROR");
  }
}

export class GeminiQuotaExceededError extends AppError {
  constructor(message = "Gemini API quota exceeded") {
    super(message, 429, "GEMINI_QUOTA_EXCEEDED");
  }
}

export class ProviderError extends AppError {
  constructor(message = "Provider request failed") {
    super(message, 500, "PROVIDER_ERROR");
  }
}

export class ProviderQuotaExceededError extends AppError {
  constructor(message = "Provider quota exceeded") {
    super(message, 429, "PROVIDER_QUOTA_EXCEEDED");
  }
}

export class ProviderCredentialsExhaustedError extends AppError {
  constructor(message = "All provider credentials exhausted") {
    super(message, 503, "PROVIDER_CREDENTIALS_EXHAUSTED");
  }
}

export class ProviderAuthRequiredError extends AppError {
  constructor(message = "Provider authentication required") {
    super(message, 401, "PROVIDER_AUTH_REQUIRED");
  }
}

export class ProviderTimeoutError extends AppError {
  constructor(message = "Provider request timed out") {
    super(message, 504, "PROVIDER_TIMEOUT");
  }
}

export class ProviderCliFailedError extends AppError {
  constructor(message = "Provider CLI failed") {
    super(message, 500, "PROVIDER_CLI_FAILED");
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = "Unauthorized") {
    super(message, 401, "UNAUTHORIZED");
  }
}

export class ForbiddenError extends AppError {
  constructor(message = "Forbidden") {
    super(message, 403, "FORBIDDEN");
  }
}

export class InvalidMetadataError extends AppError {
  constructor(message = "Invalid metadata") {
    super(message, 400, "INVALID_METADATA");
  }
}

export class JobNotRetryableError extends AppError {
  constructor(message = "Job is not in failed state") {
    super(message, 409, "JOB_NOT_RETRYABLE");
  }
}

