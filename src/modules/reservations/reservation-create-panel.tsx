"use client";

import { useState } from "react";
import { ReservationDetail } from "./reservation-detail.tsx";
import { ReservationForm } from "./reservation-form.tsx";
import type { ReservationDto, ReservationProvider, ReservationPropertyContext } from "./reservation-contract.ts";

export function ReservationCreatePanel({
  property,
  defaultCustodian,
}: {
  property: ReservationPropertyContext;
  defaultCustodian: "owner" | "manager";
}) {
  const [created, setCreated] = useState<ReservationDto | null>(null);
  const provider: ReservationProvider = {
    async createReservation(input, idempotencyKey) {
      const response = await fetch("/api/v1/reservations", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": idempotencyKey,
          "X-Eve-Same-Origin": "1",
        },
        credentials: "same-origin",
        cache: "no-store",
        body: JSON.stringify(input),
      });
      let body: unknown;
      try { body = await response.json(); } catch { throw new Error("provider_unavailable"); }
      if (!response.ok) throw body;
      return body as Awaited<ReturnType<ReservationProvider["createReservation"]>>;
    },
  };
  if (created) return <ReservationDetail reservation={created} propertyName={property.name} />;
  return <ReservationForm property={property} defaultCustodian={defaultCustodian} contacts={[]} provider={provider} onCreated={setCreated} />;
}
