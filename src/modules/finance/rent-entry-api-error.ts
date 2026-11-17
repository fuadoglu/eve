export class RentEntryApiError extends Error {
  constructor(readonly code: string) { super(code); }
}
