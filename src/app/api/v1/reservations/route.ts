import { handleReservationCreate } from "@/modules/reservations/reservation-handlers.ts";
import { createReservation } from "@/modules/reservations/supabase-reservation-api.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  return handleReservationCreate(request, createReservation);
}
