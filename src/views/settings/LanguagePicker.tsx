import { openUrl } from "@tauri-apps/plugin-opener";
import type { Settings } from "../../api";
import { Check, External } from "../../icons";
import { gb, INDIC_MODEL_GB } from "../../models";
import type { SetSetting } from "./common";

const INDIC_MODEL_URL = "https://huggingface.co/ai4bharat/indic-conformer-600m-multilingual";
const HF_TOKENS_URL = "https://huggingface.co/settings/tokens";

const LANGS: { code: string; label: string; native: string }[] = [
  { code: "en", label: "English", native: "English" },
  { code: "hi", label: "Hindi", native: "हिन्दी" },
  { code: "gu", label: "Gujarati", native: "ગુજરાતી" },
];

/** Which languages you speak, and how Hindi/Gujarati are written. */
export default function LanguagePicker({ s, set }: { s: Settings; set: SetSetting }) {
  const chosen = s.languages.length ? s.languages : [s.language || "en"];
  const toggle = (code: string) => {
    const next = chosen.includes(code) ? chosen.filter((c) => c !== code) : [...chosen, code];
    if (next.length) set("languages", LANGS.map((l) => l.code).filter((c) => next.includes(c)));
  };
  const hi = chosen.includes("hi");
  const gu = chosen.includes("gu");
  return (
    <div className="field full">
      <span className="field-label">Languages you speak</span>
      <div className="row wrap">
        {LANGS.map((l) => (
          <button
            key={l.code}
            type="button"
            className={`lang-chip ${chosen.includes(l.code) ? "on" : ""}`}
            aria-pressed={chosen.includes(l.code)}
            onClick={() => toggle(l.code)}
          >
            {chosen.includes(l.code) && <Check size={14} />} {l.native}
            {l.native !== l.label && <span className="small faint">{l.label}</span>}
          </button>
        ))}
      </div>
      <span className="field-hint">Each phrase is recognised in whichever of these you speak — mix them freely.</span>

      {hi && gu && (
        <div className="lang-sub">
          <span className="field-label">Hindi or Gujarati — which do you speak more?</span>
          <span className="field-hint">
            Written as spoken, Hindi and Gujarati are told apart by sound, and this one wins when it&apos;s unclear.
            Translated speech is always treated as this one.
          </span>
          <div className="segmented">
            {(["gu", "hi"] as const).map((code) => (
              <button
                key={code}
                type="button"
                className={s.prefer_indic === code ? "on" : ""}
                onClick={() => set("prefer_indic", code)}
              >
                {code === "gu" ? "ગુજરાતી Gujarati" : "हिन्दी Hindi"}
              </button>
            ))}
          </div>
        </div>
      )}

      {(hi || gu) && (
        <div className="lang-sub">
          <span className="field-label">How to write Hindi &amp; Gujarati</span>
          <select value={s.translate} onChange={(e) => set("translate", e.target.value as Settings["translate"])}>
            <option value="none">As spoken — in हिन्दी / ગુજરાતી script</option>
            {gu && <option value="gujarati">Translate Gujarati to English, keep Hindi</option>}
            <option value="all">Translate both to English</option>
          </select>
          <span className="field-hint">
            As spoken uses AI4Bharat IndicConformer, a model made for Indian languages (a {gb(INDIC_MODEL_GB)} download on
            first use, kept as 1.0 GB, with your Hugging Face token after accepting its terms on huggingface.co). Translating uses Whisper.
          </span>
        </div>
      )}
    </div>
  );
}

/** The token the Hindi/Gujarati model needs to download (shown when either is chosen). */
export function HfToken({ s, set }: { s: Settings; set: SetSetting }) {
  return (
    <div className="field full" id="set-hf">
      <span className="field-label">Hugging Face token (for Hindi/Gujarati)</span>
      <span className="field-hint">
        The Hindi/Gujarati model is free but needs its terms accepted once, then a token with <b>Read</b> access.
      </span>
      <div className="row wrap">
        <button type="button" onClick={() => openUrl(INDIC_MODEL_URL)}>
          <External size={14} /> 1. Accept terms
        </button>
        <button type="button" onClick={() => openUrl(HF_TOKENS_URL)}>
          <External size={14} /> 2. Create a Read token
        </button>
        <input className="grow" type="password" value={s.hf_token} onChange={(e) => set("hf_token", e.target.value)} placeholder="hf_…" />
      </div>
    </div>
  );
}
