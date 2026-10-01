/** Underlining where tasks were said in a transcript. */

export type TaskMark = { description: string; quote: string | null };

// Compare words ignoring case and punctuation. Marks (\p{M}) are kept so
// Hindi/Gujarati vowel signs still count.
const norm = (w: string) => w.toLowerCase().replace(/[^\p{L}\p{M}\p{N}]/gu, "");

/** A quote's words. The task AI sometimes keeps the transcript's "Name:" in front; drop it. */
function quoteTokens(quote: string | null): string[] {
  return (quote ?? "")
    .replace(/^\s*[^\s:]{1,30}:\s+/u, "")
    .split(/\s+/)
    .map(norm)
    .filter(Boolean);
}

/** How many quote words match in a row from transcript word `i` on, and where the match ends. */
function matchAt(tokens: string[], q: string[], i: number): { k: number; end: number } {
  // Skip words with no letters (punctuation-only) inside the match.
  let j = i;
  let k = 0;
  while (j < tokens.length && k < q.length) {
    if (!tokens[j]) j++;
    else if (tokens[j] === q[k]) {
      j++;
      k++;
    } else break;
  }
  return { k, end: j };
}

/** For each word, the task it was said for (its quote found in the transcript). */
export function taskOfWords(words: string[], tasks: TaskMark[]): (string | null)[] {
  const out: (string | null)[] = words.map(() => null);
  const tokens = words.map(norm);
  for (const t of tasks) {
    const q = quoteTokens(t.quote);
    if (q.length === 0) continue;
    for (let i = 0; i < tokens.length; i++) {
      const { k, end } = matchAt(tokens, q, i);
      if (k === q.length) {
        for (let x = i; x < end; x++) out[x] = t.description;
        break;
      }
    }
  }
  return out;
}

/**
 * When a task's quote starts (s) in these timed words, or null if it isn't
 * there. The task AI sometimes rewords the end of a quote, so failing an exact
 * match, the place where most of its opening words (3 or more) match wins.
 */
export function quoteStart(words: { w: string; s: number }[], quote: string | null): number | null {
  const q = quoteTokens(quote);
  if (q.length === 0) return null;
  const tokens = words.map((w) => norm(w.w));
  let best = -1;
  let bestK = Math.min(3, q.length) - 1;
  for (let i = 0; i < tokens.length; i++) {
    if (!tokens[i]) continue;
    const { k } = matchAt(tokens, q, i);
    if (k === q.length) return words[i].s;
    if (k > bestK) {
      best = i;
      bestK = k;
    }
  }
  return best < 0 ? null : words[best].s;
}
