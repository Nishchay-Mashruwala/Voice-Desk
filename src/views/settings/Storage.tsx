import { useEffect, useState } from "react";
import { api, type DataPaths, type ModelInfo, type Usage } from "../../api";
import { confirmDialog } from "../../confirm";
import { Folder, Trash } from "../../icons";
import { gb } from "../../models";
import { toast } from "../../toast";

/** Live RAM / GPU memory Voice Desk is using, refreshed every 2 s while the window is visible. */
export function MemoryNow() {
  const [u, setU] = useState<Usage | null>(null);
  useEffect(() => {
    let alive = true;
    const tick = () => {
      // Minimised or hidden: nobody is looking, so don't keep asking.
      if (document.hidden) return;
      api
        .resourceUsage()
        .then((x) => alive && setU(x))
        .catch(() => {});
    };
    tick();
    const t = setInterval(tick, 2000);
    document.addEventListener("visibilitychange", tick);
    return () => {
      alive = false;
      clearInterval(t);
      document.removeEventListener("visibilitychange", tick);
    };
  }, []);
  if (!u) return null;
  return (
    <div className="full usage">
      <span className="field-label">In use right now</span>
      <div className="usage-row">
        <span>App {gb(u.app_gb)}</span>
        <span>Speech engine {u.speech_gb > 0.01 ? gb(u.speech_gb) : "asleep"}</span>
        <span>Task AI {u.task_ai_gb > 0.01 ? gb(u.task_ai_gb) : "not loaded"}</span>
        {u.gpu_used_gb != null && u.gpu_total_gb != null && (
          <span title="Windows doesn't report GPU memory per app, so this includes other apps">
            GPU memory {gb(u.gpu_used_gb)} of {gb(u.gpu_total_gb)}
          </span>
        )}
      </div>
    </div>
  );
}

/**
 * Downloaded models with their size; ones the current settings don't use can
 * be deleted. The list comes from Settings (fetched once, shared with the model pickers).
 */
export function DownloadedModels({ models, onChanged }: { models: ModelInfo[] | null; onChanged: () => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  const remove = async (m: ModelInfo) => {
    const ok = await confirmDialog({
      title: `Delete ${m.name}?`,
      message: `Frees ${gb(m.size_gb)}. If a later setting needs it, it downloads again by itself.`,
    });
    if (!ok) return;
    setBusy(m.id);
    try {
      await api.deleteModel(m.id);
      toast(`Deleted — ${gb(m.size_gb)} freed`);
      onChanged();
    } catch (e) {
      toast(`Couldn't delete it: ${e}`);
    } finally {
      setBusy(null);
    }
  };
  if (!models || models.length === 0) return null;
  const total = models.reduce((n, m) => n + m.size_gb, 0);
  const unused = models.filter((m) => !m.in_use).reduce((n, m) => n + m.size_gb, 0);
  return (
    <div className="full">
      <span className="field-label">
        Downloaded models · {gb(total)}
        {unused > 0.05 && ` (${gb(unused)} not used by your settings)`}
      </span>
      <div className="model-list">
        {models.map((m) => (
          <div key={m.id} className="model-row">
            <span className="grow">{m.name}</span>
            <span className="small muted">{gb(m.size_gb)}</span>
            {m.in_use ? (
              <span className="badge ok">In use</span>
            ) : (
              <button className="ghost danger" disabled={busy !== null} onClick={() => remove(m)}>
                {busy === m.id ? <span className="spinner dark" /> : <Trash size={14} />} Delete
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

/** Where Voice Desk keeps things, each with a button to open the folder. */
export function DataFolders() {
  const [paths, setPaths] = useState<DataPaths | null>(null);
  useEffect(() => {
    api.dataPaths().then(setPaths).catch(() => {});
  }, []);
  if (!paths) return null;
  return (
    <div className="full">
      {(
        [
          ["Your data", paths.app_data, "Database, recordings, voice profile"],
          ["Recordings", paths.recordings, ""],
          ["Speech models", paths.speech_models, ""],
          ["Task AI models", paths.llm_models, ""],
        ] as const
      ).map(([label, p, hint]) => (
        <div key={label} className="path-row">
          <span className="field-label" title={hint}>
            {label}
          </span>
          <span className="path" title={p}>
            {p}
          </span>
          <button className="ghost" onClick={() => api.openFolder(p).catch((e) => toast(String(e)))}>
            <Folder size={15} /> Open
          </button>
        </div>
      ))}
    </div>
  );
}
