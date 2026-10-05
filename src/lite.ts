import { useEffect, useState } from "react";
import { api, type EngineStatus, type Hardware } from "./api";

/**
 * Keep the interface cheap to draw.
 * - "lite": on computers without an NVIDIA GPU (or set to / running on the
 *   CPU), the window is usually drawn by the CPU or a weak integrated GPU, where
 *   the drifting background and blurred cards cost ~1.3 cores while idle. Lite
 *   keeps the same colours without motion or blur.
 * - "paused": animations stop while the window is hidden or minimised.
 */
export function setLite(on: boolean) {
  document.documentElement.classList.toggle("lite", on);
}

let watching = false;
export function pauseWhenHidden() {
  if (watching) return;
  watching = true;
  const update = () => document.documentElement.classList.toggle("paused", document.hidden);
  document.addEventListener("visibilitychange", update);
  update();
}

// The hardware doesn't change while Voice Desk runs: ask once per window.
let hardware: Promise<Hardware | null> | null = null;
export function hardwareOnce(): Promise<Hardware | null> {
  hardware ??= api.hardwareInfo().catch(() => null);
  return hardware;
}

/**
 * Turn lite on when the Processor setting is CPU only, or (Windows/Linux) the
 * computer has no NVIDIA GPU or the speech engine ended up on the CPU anyway.
 */
export function useLite(device: string | undefined, engine: EngineStatus | null) {
  const [hw, setHw] = useState<Hardware | null>(null);
  useEffect(() => {
    pauseWhenHidden();
    hardwareOnce().then(setHw);
  }, []);
  const engineOnCpu = engine?.state === "ready" && engine.device === "cpu";
  const noGpu = hw != null && hw.gpus.length === 0;
  // Macs never have an NVIDIA GPU and speech always runs on their CPU, but their
  // own graphics draw the interface easily: only "CPU only" turns lite on there.
  const mac = navigator.userAgent.includes("Mac");
  const on = device === "cpu" || (!mac && (noGpu || engineOnCpu));
  useEffect(() => {
    if (device !== undefined || hw) setLite(on);
  }, [on, device, hw]);
}
