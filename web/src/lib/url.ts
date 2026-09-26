/** First http(s) URL in `text`, which may be a bare URL or prose around one. */
export function extractUrl(text: string): string | null {
  const match = /https?:\/\/[^\s<>")\]]+/i.exec(text);
  if (!match) return null;
  // Trailing punctuation is almost always the sentence's, not the URL's.
  const url = match[0].replace(/[.,:;!?]+$/, "");
  return url || null;
}

/** What someone typed as a URL: a link anywhere in the text, or failing that
 *  a bare domain such as `example.com`. */
export function parseUrlInput(text: string): string | null {
  const url = extractUrl(text);
  if (url) return url;
  const bare = text.trim();
  if (!/^[^\s/:]+\.[a-z]{2,}([/?#]\S*)?$/i.test(bare)) return null;
  return URL.canParse(`https://${bare}`) ? `https://${bare}` : null;
}

export function hostOf(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

export function timeAgo(iso: string, now = Date.now()): string {
  const minutes = Math.floor((now - Date.parse(iso)) / 60_000);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  if (days > 365) return `${Math.floor(days / 365)}y ago`;
  if (days > 30) return `${Math.floor(days / 30)}mo ago`;
  if (days > 0) return `${days}d ago`;
  if (hours > 0) return `${hours}h ago`;
  if (minutes > 0) return `${minutes}m ago`;
  return "just now";
}

const dateFormat = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });

export function formatDate(iso: string): string {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? iso : dateFormat.format(t);
}

export const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

/** `text` split around case-insensitive occurrences of `query`. */
export function highlight(text: string, query: string): { text: string; hit: boolean }[] {
  const q = query.trim();
  if (!q) return [{ text, hit: false }];
  // Matching the original text, not a lowercased copy: lowercasing can change
  // a string's length (İ → i̇), which would shift every offset after it.
  return text
    .split(new RegExp(`(${RegExp.escape(q)})`, "i"))
    .map((part, i) => ({ text: part, hit: i % 2 === 1 }))
    .filter((p) => p.text);
}
