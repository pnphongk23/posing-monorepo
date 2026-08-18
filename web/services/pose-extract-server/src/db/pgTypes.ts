export function pgTimestamp(value: Date | string | null | undefined): string | null {
  if (value == null) {
    return null;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  return value;
}

export function pgIntId(value: string | number | bigint): number {
  return Number(value);
}
