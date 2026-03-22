import React, { useEffect, useMemo, useState } from "react";

const DEFAULT_SERVICE_A_URL = "http://localhost:8080";
const DEFAULT_SERVICE_B_URL = "http://localhost:8080";

function toUrl(val, fallback) {
  if (!val) return fallback;
  return val;
}

export default function App() {
  const serviceAUrl = useMemo(
    () => toUrl(import.meta.env.VITE_SERVICE_A_URL, DEFAULT_SERVICE_A_URL),
    []
  );
  const serviceBUrl = useMemo(
    () => toUrl(import.meta.env.VITE_SERVICE_B_URL, DEFAULT_SERVICE_B_URL),
    []
  );

  const [serviceAStatus, setServiceAStatus] = useState("unknown");
  const [serviceBStatus, setServiceBStatus] = useState("unknown");
  const [lastUpdate, setLastUpdate] = useState(null);

  useEffect(() => {
    let cancelled = false;

    async function check() {
      try {
        const resA = await fetch(serviceAUrl + "/healthz");
        if (!resA.ok) throw new Error("service-a not ok");
        if (!cancelled) setServiceAStatus("ok");
      } catch (e) {
        if (!cancelled) setServiceAStatus("error");
      }

      try {
        const resB = await fetch(serviceBUrl + "/healthz");
        if (!resB.ok) throw new Error("service-b not ok");
        if (!cancelled) setServiceBStatus("ok");
      } catch (e) {
        if (!cancelled) setServiceBStatus("error");
      }

      if (!cancelled) setLastUpdate(new Date().toISOString());
    }

    check();
    const t = setInterval(check, 5000);

    return () => {
      cancelled = true;
      clearInterval(t);
    };
  }, [serviceAUrl, serviceBUrl]);

  return (
    <div style={{ fontFamily: "system-ui", padding: 24 }}>
      <h1>Take-home: Observability Smoke UI</h1>
      <p>
        This page periodically calls <code>/healthz</code> on both backend
        services.
      </p>
      <div style={{ marginTop: 16 }}>
        <div>
          <b>service-a:</b> {serviceAStatus}
        </div>
        <div>
          <b>service-b:</b> {serviceBStatus}
        </div>
        <div style={{ marginTop: 8, color: "#555" }}>
          Last update: {lastUpdate || "n/a"}
        </div>
      </div>
    </div>
  );
}

