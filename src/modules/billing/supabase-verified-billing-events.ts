import "server-only";

import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { getSupabaseSecretKey } from "../../lib/env/supabase-server.ts";
import {
  parseNormalizedVerifiedBillingEvent,
  parseVerifiedBillingEventResult,
  type NormalizedVerifiedBillingEvent,
  type VerifiedBillingEventResult,
} from "./verified-billing-event.ts";

type ApiClient = {
  schema(name: "api"): {
    rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }>;
  };
};

export class VerifiedBillingEventError extends Error {
  readonly code: "invalid_event" | "not_found" | "not_applicable" | "unavailable";
  constructor(code: VerifiedBillingEventError["code"]) {
    super(code);
    this.name = "VerifiedBillingEventError";
    this.code = code;
  }
}

/** Server-only persistence boundary for an event already verified by a trusted Eve-side adapter. */
export async function reconcileVerifiedBillingEvent(input: NormalizedVerifiedBillingEvent): Promise<VerifiedBillingEventResult> {
  const event = parseNormalizedVerifiedBillingEvent(input);
  if (!event) throw new VerifiedBillingEventError("invalid_event");
  let result: { data: unknown; error: { code?: string } | null };
  try {
    result = await getApiClient().schema("api").rpc("reconcile_verified_billing_event_for_server", {
      p_order_id: event.order_id,
      p_event_key: event.event_key,
      p_provider_transaction_id: event.provider_transaction_id,
      p_amount_minor: event.amount_minor,
      p_currency: event.currency,
    });
  } catch {
    throw new VerifiedBillingEventError("unavailable");
  }
  if (result.error) {
    if (result.error.code === "P0002") throw new VerifiedBillingEventError("not_found");
    if (["22023", "23505", "42501", "55000", "23503"].includes(result.error.code ?? "")) {
      throw new VerifiedBillingEventError("not_applicable");
    }
    throw new VerifiedBillingEventError("unavailable");
  }
  const parsed = parseVerifiedBillingEventResult(result.data);
  if (!parsed || parsed.order_id !== event.order_id) throw new VerifiedBillingEventError("unavailable");
  return parsed;
}

function getApiClient(): ApiClient {
  const { url } = getSupabasePublicConfig();
  return createClient(url, getSupabaseSecretKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }) as unknown as ApiClient;
}
