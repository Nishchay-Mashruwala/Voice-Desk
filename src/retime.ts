import type { Word } from "./api";
import { norm } from "./taskMarks";

/**
 * Word timings for edited text. Words that didn't change keep their exact
 * times (matched in order, ignoring case and punctuation); new or changed
 * words share the time between their unchanged neighbours, or `start`/`end`.
 * Other fields of kept words (like `st`, what happened to them) are kept too.
 */
export function retimeWords(old: Word[], text: string, start: number, end: number): Word[] {
  const next = text.split(/\s+/).filter(Boolean);
  const a = old.map((w) => norm(w.w));
  const b = next.map(norm);
  // Longest common subsequence: which new words are old words.
  const lcs: number[][] = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--)
      lcs[i][j] = a[i] && a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
  const match: (number | null)[] = new Array(b.length).fill(null);
  for (let i = 0, j = 0; i < a.length && j < b.length; ) {
    if (a[i] && a[i] === b[j]) {
      match[j] = i;
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) i++;
    else j++;
  }

  const out: Word[] = [];
  for (let j = 0; j < next.length; ) {
    const i = match[j];
    if (i !== null) {
      out.push({ ...old[i], w: next[j] });
      j++;
      continue;
    }
    // A run of new words: spread them between the neighbouring kept words.
    let k = j;
    while (k < next.length && match[k] === null) k++;
    const from = out.length ? out[out.length - 1].e : start;
    const to = k < next.length ? old[match[k] as number].s : end;
    const step = Math.max(0, to - from) / (k - j);
    for (let x = j; x < k; x++) {
      const s = from + step * (x - j);
      out.push({ w: next[x], s: +s.toFixed(2), e: +(s + step).toFixed(2) });
    }
    j = k;
  }
  return out;
}
