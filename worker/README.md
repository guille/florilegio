# worker

Contains the back-end for Florilegio. This is a simple Hono API that runs on the free tier of Cloudflare Workers.

It also contains the sqlite schema, which is deployed to D1.

## Developing

Running the tests:

```sh
mise run test
```

Starting up the app locally:

```sh
cp .env.sample .dev.vars
mise run apply-schema:local
mise run dev
```

## Deploying

```sh
mise run apply-schema:remote
wrangler secret put API_TOKEN
mise run deploy
```
