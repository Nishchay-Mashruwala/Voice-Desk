import { useEffect, useRef, useState } from "react";
import { api, formatDate } from "../../api";
import { confirmDialog } from "../../confirm";
import { Check, Mic, Stop } from "../../icons";
import { toast } from "../../toast";

const ENROLL_TEXT =
  "The quick brown fox jumps over the lazy dog. I'm teaching Voice Desk what my voice sounds like, " +
  "so that only I can give it commands. Tomorrow I will send the report, review the design, and call the team at three.";

/** Train (or forget) your voice: read a short passage aloud. */
export default function VoiceEnrollment({ onChange }: { onChange: () => void }) {
  const [profile, setProfile] = useState<{ exists: boolean; created_at: string | null }>({ exists: false, created_at: null });
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [level, setLevel] = useState(0);
  const [busy, setBusy] = useState(false);
  const started = useRef(0);

  const refresh = () =>
    api
      .voiceProfileInfo()
      .then(setProfile)
      .catch(() => {});
  useEffect(() => {
    refresh();
    return () => {
      api.enrollStop(false).catch(() => {});
    };
  }, []);

  useEffect(() => {
    if (!recording) return;
    const t = setInterval(async () => {
      const s = (Date.now() - started.current) / 1000;
      setSeconds(s);
      setLevel((await api.audioLevels()).enroll ?? 0);
      if (s >= 25) finish();
    }, 100);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recording]);

  const start = async () => {
    try {
      await api.enrollStart();
      started.current = Date.now();
      setSeconds(0);
      setRecording(true);
    } catch (e) {
      toast(String(e));
    }
  };

  const finish = async () => {
    setRecording(false);
    setBusy(true);
    try {
      const r = await api.enrollStop(true);
      if (r) toast(`Voice saved (${r.seconds.toFixed(0)}s of speech). Commands now only work in your voice.`);
      refresh();
      onChange();
    } catch (e) {
      toast(String(e));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    const ok = await confirmDialog({
      title: "Forget your voice?",
      message: "Voice Desk deletes what it learned about your voice. Until you train it again, anyone's voice can give commands.",
      confirmLabel: "Forget",
    });
    if (!ok) return;
    try {
      await api.deleteVoiceProfile();
      toast("Your voice was forgotten");
    } catch (e) {
      toast(`Couldn't forget your voice: ${e}`);
    }
    refresh();
    onChange();
  };

  return (
    <div className="full" id="set-voice">
      {recording ? (
        <>
          <p className="small muted" style={{ marginBottom: 8 }}>
            Read this aloud in your normal voice:
          </p>
          <div className="enroll-text">{ENROLL_TEXT}</div>
          <div className="row" style={{ marginTop: 12 }}>
            <div className="progress-track grow">
              <div className="progress-fill" style={{ width: `${Math.min(100, Math.sqrt(level) * 250)}%`, transition: "width 0.1s linear" }} />
            </div>
            <span className="small muted" style={{ minWidth: 40 }}>
              {seconds.toFixed(0)}s
            </span>
            <button className="primary" onClick={finish} disabled={seconds < 8}>
              <Stop size={12} /> {seconds < 8 ? "Keep reading…" : "Done"}
            </button>
          </div>
        </>
      ) : (
        <div className="row wrap">
          {profile.exists ? (
            <span className="badge ok">
              <Check size={12} /> Voice saved {profile.created_at ? formatDate(profile.created_at) : ""}
            </span>
          ) : (
            <span className="badge warn">Not trained yet</span>
          )}
          <span className="grow" />
          {profile.exists && (
            <button className="ghost danger" onClick={remove}>
              Forget my voice
            </button>
          )}
          <button className="primary" onClick={start} disabled={busy}>
            {busy ? <span className="spinner" /> : <Mic size={15} />} {profile.exists ? "Re-train" : "Train my voice"}
          </button>
        </div>
      )}
    </div>
  );
}
