import { handleReservationMove } from "@/modules/reservations/reservation-move-handlers.ts";
import { moveReservation } from "@/modules/reservations/supabase-reservation-api.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
): Promise<Response> {
  const { id } = await context.params;
  return handleReservationMove(request, id, moveReservation);
}
