import { handleReservationTransition } from "@/modules/reservations/reservation-at10-http.ts";
import { transitionReservation } from "@/modules/reservations/supabase-reservation-at10-api.ts";

export async function POST(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> {
  const { id } = await context.params;
  return handleReservationTransition(request, id, transitionReservation);
}
