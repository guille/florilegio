# Florilegio

A simple, single-user read-it-later tool in the vein of Pocket or Raindrop.io

<p align="center">
  <img src="showcase.webp" width="300" alt="App screenshot" />
</p>

The codebase is structured as a monorepo, containing:
- client: Flutter app targetting web and Android that acts as a front-end
- ff-extension: Firefox extension to save the open tab to Florilegio.
- support: script to convert Raindrop.io exports into Florilegio's JSONs.
- worker: Hono back-end.

The project's tools, dependencies and tasks are managed with mise. Run `mise install` to get started.

The stack is meant to be sustainable for a single-user and comfortably fits my use case within provider's free tiers.

## Design

**Tech stack**

- Backend:
	- Hono + Cloudflare Workers
	- sqlite + Cloudflare D1
	- Vitest
- Client:
	- Flutter + Kotlin

**Auth and security**

A static Bearer token is stored in a Worker secret env var.

The clients need to be configured on first use to point to the right Worker URL and set the right token.

The tokens must match the format defined in RFC 6750. A simple way to ensure that is to generate them like:
```sh
openssl rand -base64 32
```

The token is stored securely in Android and not-so-securely-but-standard in the browser.
