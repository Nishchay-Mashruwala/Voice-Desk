import { useEffect, useRef, useState } from "react";
import { api, formatDate, formatDuration, type SearchHit } from "../api";
import { Search as SearchIcon } from "../icons";

const GROUPS: { kind: SearchHit["kind"]; label: string }[] = [
  { kind: "meeting", label: "Meetings" },
  { kind: "recording", label: "Recordings" },
  { kind: "task", label: "Tasks" },
];

/** Search everything said and every task. Click a result to hear it. */
export default function SearchView({ onOpen }: { onOpen: (hit: SearchHit) => void }) {
  const [query, setQuery] = useState(() => {
    try {
      return sessionStorage.getItem("search") ?? "";
    } catch {
      return "";
    }
  });
  const [hits, setHits] = useState<SearchHit[] | null>(null);
  const seq = useRef(0);

  useEffect(() => {
    try {
      sessionStorage.setItem("search", query);
    } catch {
      /* fine */
    }
    const q = query.trim();
    if (!q) {
      setHits(null);
      return;
    }
    const n = ++seq.current;
    const t = setTimeout(() => api.search(q).then((h) => n === seq.current && setHits(h)), 150);
    return () => clearTimeout(t);
  }, [query]);

  return (
    <section className="page">
      <header className="page-header">
        <h1>Search</h1>
        <p>Everything said in your recordings and meetings, and every task.</p>
      </header>
      <div className="search-box card">
        <SearchIcon size={18} />
        <input
          autoFocus
          className="grow"
          value={query}
          placeholder="Search words, names, tasks…"
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === "Escape" && setQuery("")}
        />
      </div>
      {hits && hits.length === 0 && <div className="empty">Nothing found for “{query.trim()}”.</div>}
      {hits &&
        GROUPS.map(({ kind, label }) => {
          const group = hits.filter((h) => h.kind === kind);
          if (group.length === 0) return null;
          return (
            <div key={kind}>
              <h3>
                {label} <span className="faint">· {group.length}</span>
              </h3>
              <ul className="list">
                {group.map((h, i) => (
                  <li key={i}>
                    <button className="card search-hit" onClick={() => onOpen(h)}>
                      <div className="row small muted">
                        <span className="grow search-title">{h.title}</span>
                        {h.at_s != null && <span>{formatDuration(h.at_s)}</span>}
                        <span>{formatDate(h.created_at)}</span>
                      </div>
                      <div className="search-snippet">
                        {[...h.snippet].slice(0, h.match_start).join("")}
                        <mark>{[...h.snippet].slice(h.match_start, h.match_end).join("")}</mark>
                        {[...h.snippet].slice(h.match_end).join("")}
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          );
        })}
    </section>
  );
}
