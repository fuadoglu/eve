import { handleReservationPatch } from "@/modules/reservations/reservation-at10-http.ts";
import { patchReservation } from "@/modules/reservations/supabase-reservation-at10-api.ts";

export async function PATCH(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> {
  const { id } = await context.params;
  return handleReservationPatch(request, id, patchReservation);
}
