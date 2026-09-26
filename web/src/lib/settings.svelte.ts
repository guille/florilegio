export type Theme = "system" | "light" | "dark";

const KEYS = { baseUrl: "base_url", token: "bearer_token", theme: "theme_mode" } as const;

function load(key: string): string {
  try {
    return localStorage.getItem(key) ?? "";
  } catch {
    return "";
  }
}

function store(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {}
}

/** Browsers offer nothing better than localStorage for the token. */
class Settings {
  baseUrl = $state(load(KEYS.baseUrl));
  token = $state(load(KEYS.token));
  theme = $state<Theme>((load(KEYS.theme) as Theme) || "system");

  get configured() {
    return this.baseUrl !== "" && this.token !== "";
  }

  saveConnection(baseUrl: string, token: string) {
    this.baseUrl = baseUrl.trim();
    this.token = token.trim();
    store(KEYS.baseUrl, this.baseUrl);
    store(KEYS.token, this.token);
  }

  setTheme(theme: Theme) {
    this.theme = theme;
    store(KEYS.theme, theme);
  }
}

export const settings = new Settings();
