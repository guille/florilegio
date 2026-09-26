export type ToastOptions = {
  action?: { label: string; run: () => void };
  /** Runs when the toast goes away without its action being taken. */
  onexpire?: () => void;
  ms?: number;
};

export type Toast = { id: number; message: string } & ToastOptions;

let next = 0;

/** One toast at a time: news is only ever the latest. */
class Toasts {
  current = $state.raw<Toast | null>(null);
  #timer: ReturnType<typeof setTimeout> | undefined;
  #deadline = 0;
  #remaining = 0;
  #held = false;

  show(message: string, options: ToastOptions = {}) {
    this.#expire();
    this.current = { id: ++next, message, ...options };
    this.#remaining = options.ms ?? (options.action ? 6000 : 4000);
    if (!this.#held) this.#start();
  }

  /** Stop the clock while the user is looking at or reaching for the toast. */
  hold(held: boolean) {
    if (held === this.#held) return;
    this.#held = held;
    if (!this.current) return;
    if (held) {
      clearTimeout(this.#timer);
      this.#remaining = Math.max(0, this.#deadline - Date.now());
    } else {
      this.#start();
    }
  }

  act() {
    const toast = this.current;
    clearTimeout(this.#timer);
    this.current = null;
    toast?.action?.run();
  }

  dismiss() {
    this.#expire();
  }

  #start() {
    this.#deadline = Date.now() + this.#remaining;
    this.#timer = setTimeout(() => this.#expire(), this.#remaining);
  }

  #expire() {
    const toast = this.current;
    clearTimeout(this.#timer);
    this.current = null;
    toast?.onexpire?.();
  }
}

export const toasts = new Toasts();
