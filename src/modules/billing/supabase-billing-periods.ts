import "server-only";

import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { getSupabaseSecretKey } from "../../lib/env/supabase-server.ts";
import type { BillingPeriodPlan } from "./billing-periods.ts";

export type AppliedBillingOrderPeriod = {
  id: string;
  order_line_id: string;
  property_id: string;
  plan: BillingPeriodPlan;
  starts_at: string;
  ends_at: string;
  anchor_day: number;
  anchor_month: number;
};

export type AppliedBillingOrder = {
  replay: boolean;
  order_id: string;
  period: AppliedBillingOrderPeriod;
};

type ApiClient = {
  schema(name: "api"): {
    rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }>;
  };
};

export class BillingOrderApplicationError extends Error {
  readonly code: "not_found" | "not_applicable" | "unavailable";

  constructor(code: BillingOrderApplicationError["code"]) {
    super(code);
    this.name = "BillingOrderApplicationError";
    this.code = code;
  }
}

/** Apply a provider-verified order transactionally; the caller cannot supply time or anchors. */
export async function applyVerifiedBillingOrder(orderId: string): Promise<AppliedBillingOrder> {
  if (!isUuid(orderId)) throw new BillingOrderApplicationError("not_found");
  let result: { data: unknown; error: { code?: string } | null };
  try {
    result = await getApiClient().schema("api").rpc("apply_verified_billing_order_for_server", {
      p_order_id: orderId,
    });
  } catch {
    throw new BillingOrderApplicationError("unavailable");
  }
  if (result.error) {
    if (result.error.code === "P0002") throw new BillingOrderApplicationError("not_found");
    if (["42501", "22023", "55000", "23505", "23P01"].includes(result.error.code ?? "")) {
      throw new BillingOrderApplicationError("not_applicable");
    }
    throw new BillingOrderApplicationError("unavailable");
  }
  if (!isAppliedBillingOrder(result.data) || result.data.order_id !== orderId) {
    throw new BillingOrderApplicationError("unavailable");
  }
  return result.data;
}

function getApiClient(): ApiClient {
  const { url } = getSupabasePublicConfig();
  return createClient(url, getSupabaseSecretKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }) as unknown as ApiClient;
}

function isAppliedBillingOrder(value: unknown): value is AppliedBillingOrder {
  if (!isRecord(value) || typeof value.replay !== "boolean" || typeof value.order_id !== "string"
      || !isRecord(value.period)) return false;
  const period = value.period;
  return typeof period.id === "string" && typeof period.order_line_id === "string"
    && typeof period.property_id === "string" && (period.plan === "monthly" || period.plan === "yearly")
    && typeof period.starts_at === "string" && Number.isFinite(Date.parse(period.starts_at))
    && typeof period.ends_at === "string" && Number.isFinite(Date.parse(period.ends_at))
    && Number.isInteger(period.anchor_day) && Number(period.anchor_day) >= 1 && Number(period.anchor_day) <= 31
    && Number.isInteger(period.anchor_month) && Number(period.anchor_month) >= 1 && Number(period.anchor_month) <= 12;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
