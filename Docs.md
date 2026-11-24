# Spectre Documentation

Spectre is an Express.js-style web microframework for [Crystal](https://crystal-lang.org), built directly on Crystal's standard `HTTP::Server`. It gives you routes, route params, middleware, typed JSON bodies, groups/routers, static files and `(req, res)` handlers with no dependencies beyond the standard library.

- **Version:** 0.1.0
- **Requires:** Crystal >= 1.10.0
- **License:** MIT

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Installation](#installation)
3. [User Guide](#user-guide)
   - [Creating an app](#creating-an-app)
   - [Routing](#routing)
   - [Request](#request)
   - [Response](#response)
   - [Middleware](#middleware)
   - [Groups and routers](#groups-and-routers)
   - [Static files](#static-files)
   - [Error handling](#error-handling)
   - [Running the server](#running-the-server)
   - [Testing](#testing)
4. [Limitations](#limitations)
5. [Production Deployment with Nginx (recommended)](#production-deployment-with-nginx-recommended)
6. [Project Layout](#project-layout)
7. [Benchmarks](#benchmarks)

---

## Quick Start

```crystal
require "spectre"

app = Spectre.new
app.use Spectre::Middleware.logger

app.get "/hello/:name" do |req, res|
  res.json({message: "Hello, #{req.params["name"]}!"})
end

app.listen 3000
```

```bash
crystal run app.cr
curl http://localhost:3000/hello/world
# {"message":"Hello, world!"}
```

---

## Installation

Add Spectre to your `shard.yml`:

```yaml
dependencies:
  spectre:
    github: eyszu/spectre
```

Then install:

```bash
shards install
```

For performance testing or production, always compile with `--release`:

```bash
crystal build --release --no-debug -o bin/server src/app.cr
```
## Real-world App example
- [Radiance](https://github.com/eyszu/radiance)
- [Omu](https://github.com/eyszu/Omu)
- [Shonin](https://github.com/eyszu/shonin)

---

## User Guide

### Creating an app

`Spectre.new` returns an `App`, the equivalent of `express()`:

```crystal
app = Spectre.new
```

Everything below (`get`, `use`, `group`, ...) is called on `app`.

### Routing

Register a handler per HTTP method. Handlers receive `req` and `res`.

```crystal
app.get    "/users"     { |req, res| ... }
app.post   "/users"     { |req, res| ... }
app.put    "/users/:id" { |req, res| ... }
app.patch  "/users/:id" { |req, res| ... }
app.delete "/users/:id" { |req, res| ... }
app.all    "/ping"      { |req, res| ... }   # every method
```

Use `do |req, res| ... end` blocks, or parentheses with braces: `app.get("/") { |req, res| res.send "hi" }`.

**Route parameters and wildcards**

```crystal
app.get "/users/:id/posts/:post_id" do |req, res|
  req.params["id"]          # String
  req.params.int("id")      # Int64; responds 400 if not an integer
end

app.get "/files/*" do |req, res|
  req.params["*"]           # "css/site.css" for /files/css/site.css
end
```

**Matching rules**

| Rule | Behaviour |
|---|---|
| Priority | Exact static route, then static segment, then `:param`, then `*`. `/users/new` always beats `/users/:id`, regardless of registration order. |
| Trailing slash | Ignored. `/users/` is the same as `/users`. |
| Encoding | Percent-encoded params are decoded (`/users/a%20b` gives `"a b"`). |
| Unknown path | `404 Cannot GET /path` |
| Wrong method | `405 Method Not Allowed` with an `Allow` header |
| `HEAD` | Served from the matching `GET` route, body omitted |
| `OPTIONS` | Answered automatically (`204` with `Allow`) |
| Duplicates | Registering the same method and pattern twice raises `ArgumentError` |

### Request

| Accessor | Description |
|---|---|
| `req.method`, `req.path`, `req.query_string` | `path` never includes the query string |
| `req.params` | Route params (`req.params["id"]`, `req.params.int("id")`) |
| `req.query["page"]?` | Query params, parsed lazily on first use |
| `req.header("Authorization")`, `req.headers`, `req.cookies` | Headers and cookies |
| `req.body` | Body as text. Responds `413` above `app.max_body` (default 1 MB) |
| `req.json` | Untyped `JSON::Any`. Responds `400` on invalid JSON |
| `req.json(User)` | Typed. `400` on invalid JSON, `422` on missing or mistyped fields |
| `req.form` | `application/x-www-form-urlencoded` body |
| `req.ip` | Peer socket address |
| `req.locals` | `Hash(String, String)` for passing data between middleware and handlers |
| `req.raw` | The underlying `HTTP::Request` |

**Typed JSON bodies**

```crystal
struct NewUser
  include JSON::Serializable
  getter name : String
  getter age : Int32
end

app.post "/users" do |req, res|
  input = req.json(NewUser)          # a real NewUser, checked at compile time
  res.status(201).json({name: input.name})
end
```

**Typed per-request data.** Reopen the class, like setting `req.user` in Express:

```crystal
class Spectre::Request
  property user : User?
end
```

### Response

`status`, `header`, `type` and `cookie` return `res`, so they chain.

```crystal
res.send "text"                          # text/plain
res.html "<h1>Hi</h1>"
res.json({ok: true})                     # NamedTuple, Hash, Array, JSON::Serializable...
res.status(201).json(user)
res.redirect "/login"                    # 302; res.redirect "/x", 301
res.send_status 204
res.cookie "sid", "abc", max_age: 1.day
res.header "X-Thing", "1"
```

A response can be sent **once**. Calling `send`/`json`/etc. a second time raises.

Cookies default to `HttpOnly` and `SameSite=Lax`. Pass `secure: true` when serving over HTTPS (see the [Nginx section](#production-deployment-with-nginx-recommended)).

### Middleware

A middleware is a `Spectre::Layer`: a block taking `req`, `res` and `nxt`. (`next` is a Crystal keyword, so it is spelled `nxt`.)

```crystal
app.use do |req, res, nxt|
  started = Time.monotonic
  nxt.call
  puts "#{req.path} took #{Time.monotonic - started}"
end

app.use "/admin", auth             # only for paths under /admin
app.get "/me", auth do |req, res|  # only for this route
  ...
end
```

Build a reusable layer with `Spectre.layer`:

```crystal
auth = Spectre.layer do |req, res, nxt|
  if req.header("Authorization") == "Bearer secret"
    nxt.call
  else
    res.status(401).json({error: "Unauthorized"})
  end
end
```

Notes:

- **Order matters.** A middleware applies only to routes registered **after** it.
- Global middleware also runs for 404, 405 and OPTIONS answers.
- Inside blocks, use `next` to leave early, not `return`.
- If you don't call `nxt.call`, the chain stops. Make sure you send a response in that case.

**Built-in middleware**

| Middleware | Purpose |
|---|---|
| `Spectre::Middleware.logger` | Logs `GET /path 200 0.12ms` through Crystal's `Log` (source `spectre`) |
| `Spectre::Middleware.cors(origin: "*", methods: ..., headers: ..., max_age: 600)` | Adds CORS headers and answers preflight requests |
| `Spectre::Middleware.static(dir, prefix:, max_age:)` | Static file serving (see below) |

### Groups and routers

```crystal
app.group "/api/v1" do |api|
  api.use Spectre::Middleware.cors
  api.get("/users") { |req, res| ... }
end

# Or build a standalone router and mount it:
users = Spectre::Router.new
users.get("/")     { |req, res| ... }
users.get("/:id")  { |req, res| ... }
app.use "/users", users            # same as app.mount "/users", users
```

### Static files

```crystal
app.static "/assets", "./public", max_age: 3600
```

- Serves `GET` and `HEAD` with `Content-Type`, `ETag`, `Last-Modified` and `304 Not Modified` support.
- Serves `index.html` for directories.
- **Never** serves dotfiles (e.g. `.env`), paths that escape the directory, or symlinks pointing outside it.
- Explicit routes win over static files. A missing file falls through to a normal 404.

### Error handling

```crystal
app.get "/users/:id" do |req, res|
  user = find(req.params.int("id")) || Spectre.halt(404, "User not found")
  res.json(user)
end

# Custom error handler (HTTPError and any exception from handlers/middleware)
app.error do |ex, req, res|
  status = ex.is_a?(Spectre::HTTPError) ? ex.status : 500
  res.status(status).json({error: status == 500 ? "Internal Server Error" : ex.message})
end

# Custom 404
app.not_found { |req, res| res.json({error: "no such route"}) }
```

Without `app.error`: an `HTTPError` becomes its status with the message as text; any other exception is logged and answered with a generic `500 Internal Server Error` (the exception message is never leaked to the client).

### Running the server

```crystal
app.listen 3000                                    # 0.0.0.0:3000
app.listen 3000, "127.0.0.1", reuse_port: true     # bind to loopback only
```

`listen` builds the route table, binds a plain TCP socket, and stops cleanly on Ctrl-C / `SIGTERM`.

`app.call(ctx)` is a normal `HTTP::Server::Context ->` handler, so you can also wrap Spectre in your own `HTTP::Server` and other `HTTP::Handler`s.

Set the body limit with `app.max_body = 5_000_000` (bytes).

### Testing

`app.request` runs a request through the full stack in memory, with no socket:

```crystal
r = app.request("POST", "/api/users", %({"name":"Ann","age":30}),
  HTTP::Headers{"Authorization" => "Bearer secret"})
r.status_code # => 201
r.body        # => {"id":1,...}
```

Run the project's own specs with `crystal spec`.

---

## Limitations

Spectre is a **microframework**: it deliberately stays small. Please read this section before deploying.

### Protocol and transport

| Limitation | Details |
|---|---|
| **No HTTP/2** | `app.listen` serves **HTTP/1.1 only**. There is no HTTP/2 (or HTTP/3) support, so no multiplexing, header compression or server push. |
| **No TLS / HTTPS in `listen`** | `app.listen` binds a plain, unencrypted TCP socket (`http://`). There is no certificate configuration, no `https://` listener, and no HTTP-to-HTTPS redirect, HSTS or ALPN. |
| **No WebSocket routing** | There is no WebSocket route DSL. |

Because `app.call(ctx)` is a standard handler, it is technically possible to wire Spectre into your own `HTTP::Server` with `bind_tls`. That path is **not provided, documented or tested by Spectre**, and it still does not give you HTTP/2. **We recommend putting Nginx in front instead** (see below).

### Features not included

- Sessions
- Template engines
- Multipart / file uploads (`req.form` handles only `application/x-www-form-urlencoded`)
- Response compression (gzip/brotli)
- Built-in authentication, rate limiting, CSRF protection or security headers (helmet-style)

### Behavioural limits to be aware of

- **Request bodies are buffered in memory.** `req.body` / `req.json` read the whole body into a `String`, capped at `max_body` (default 1 MB, `413` above it). Not suitable for large uploads.
- **Responses are sent in one piece.** `send`, `json`, `html` and `send_io` set `Content-Length` and write once; there is no streaming/chunked or Server-Sent-Events helper, and a response can be sent only once.
- **`req.locals` is `Hash(String, String)`.** For richer typed data, reopen `Spectre::Request` and add properties.
- **Routes are fixed once the server starts.** The route table is built when `listen` (or the first request) runs. Add routes and middleware before that.
- **Wildcards are trailing only.** `*` is supported only as the last segment (`/files/*`). There are no regex routes or optional params.
- **Middleware is order-sensitive.** It only applies to routes registered after it.
- **Multi-core is unproven.** The framework doesn't mutate state while serving, and a short `-Dpreview_mt` test ran clean, but multi-core throughput was not benchmarked. Guard your own shared state (e.g. `Atomic`, `Mutex`).
- **No built-in timeouts or connection limits** beyond what `HTTP::Server` provides. Enforce them at the reverse proxy.
- **Static files are for convenience, not for heavy traffic.** Each request resolves the real path and reads from disk with no in-memory cache; let Nginx serve large assets in production.
- **`req.ip` is the direct peer address.** Behind a proxy that is the proxy's IP, not the client's (see below).
- **Young project (0.1.0).** The API may change. The published benchmarks are single-core, on a shared VM, and do not cover TLS, keep-alive churn, large bodies or real database work.


---

## Production Deployment with Nginx (recommended)

Since Spectre does not speak TLS or HTTP/2, **run it behind Nginx**. Nginx terminates TLS, speaks HTTP/2 (and HTTP/3) to browsers, handles compression, static files, request limits and rate limiting, and forwards plain HTTP/1.1 to Spectre on localhost.

```
Browser ──HTTPS / HTTP/2──▶ Nginx ──HTTP/1.1──▶ Spectre (127.0.0.1:3000)
```

### 1. Bind Spectre to loopback only

```crystal
app.listen ENV.fetch("PORT", "3000").to_i, "127.0.0.1"
```

This ensures the app is only reachable through Nginx, never directly from the internet.

### 2. Nginx configuration

`/etc/nginx/sites-available/spectre-app`:

```nginx
upstream spectre_app {
    server 127.0.0.1:3000;
    keepalive 64;                       # reuse connections to Spectre
}

# Redirect all HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;                           # HTTP/2 (nginx >= 1.25.1)
    server_name example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Compression (Spectre does not compress)
    gzip on;
    gzip_types text/plain text/css application/json application/javascript image/svg+xml;

    # Match Spectre's app.max_body (1 MB default)
    client_max_body_size 1m;

    # Optional: let Nginx serve static assets directly
    location /assets/ {
        alias /var/www/example/public/;
        expires 1h;
        access_log off;
    }

    location / {
        proxy_pass http://spectre_app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";                 # required for upstream keepalive
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
    }
}
```

On nginx older than 1.25.1, use `listen 443 ssl http2;` instead of the separate `http2 on;` line.

Enable and reload:

```bash
sudo ln -s /etc/nginx/sites-available/spectre-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Get a free certificate with Certbot:

```bash
sudo certbot --nginx -d example.com
```

### 3. Handle proxy details in your app

**Client IP.** `req.ip` returns Nginx's address (`127.0.0.1`). Read the forwarded header instead, and only trust it because Spectre is bound to loopback:

```crystal
app.use do |req, res, nxt|
  req.locals["client_ip"] =
    req.header("X-Real-IP") || req.ip || "unknown"
  nxt.call
end
```

**Secure cookies.** Spectre sees plain HTTP, so set `secure: true` yourself:

```crystal
res.cookie "sid", token, secure: true, max_age: 7.days
```

**Scheme detection.** Check `req.header("X-Forwarded-Proto")` when you need to know whether the original request was HTTPS.

### 4. Run Spectre as a service

`/etc/systemd/system/spectre-app.service`:

```ini
[Unit]
Description=Spectre app
After=network.target

[Service]
User=www-data
WorkingDirectory=/opt/spectre-app
Environment=PORT=3000
ExecStart=/opt/spectre-app/bin/server
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now spectre-app
```

### What Nginx gives you

| Need | Handled by |
|---|---|
| HTTPS / TLS 1.2 and 1.3 | Nginx |
| HTTP/2 (and HTTP/3 if built with it) | Nginx |
| HTTP-to-HTTPS redirect, HSTS | Nginx |
| Gzip / Brotli compression | Nginx |
| Large static assets and caching | Nginx |
| Rate limiting (`limit_req`), connection limits, timeouts | Nginx |
| Load balancing across several Spectre processes | Nginx `upstream` |
| Routes, middleware, JSON, business logic | Spectre |

To scale across cores, run several Spectre processes on different ports (or use `reuse_port: true`) and list them in the Nginx `upstream` block.

---

## Project Layout

```
src/spectre.cr              entry point
src/spectre/app.cr          App: dispatch, errors, listen, request helper
src/spectre/router.cr       Router DSL: verbs, use, group, mount
src/spectre/route_table.cr  static hash + segment trie
src/spectre/request.cr      Request
src/spectre/response.cr     Response
src/spectre/params.cr       Route params
src/spectre/types.cr        Handler / Layer / Next types
src/spectre/middleware.cr   logger, cors
src/spectre/static.cr       static file serving
src/spectre/errors.cr       HTTPError, halt
examples/app.cr             typed JSON, auth, groups, static files
spec/                       crystal spec
bench/                      Spectre vs Go net/http
```

---

## Benchmarks

Single core, release build, 32 connections, 8 s per route, two runs (shared 2-vCPU VM, Crystal 1.11.2, Go 1.24.7):

| Route | Spectre req/s | Go net/http req/s |
|---|---|---|
| `GET /` (text) | 138,000 – 159,000 | 65,000 – 67,000 |
| `GET /users/:id` (path param, JSON out) | 117,000 – 118,000 | 50,000 – 54,000 |
| `POST /people` (typed JSON in and out) | 77,000 – 96,000 | 45,000 – 46,000 |

Results vary 10 to 20% between runs. TLS, keep-alive churn, large bodies, multi-core scaling and database-backed handlers were **not** measured. Run `bench/run.sh` (needs `wrk`, `taskset`, Go) on your own hardware before drawing conclusions.

## Benchmark: vs Other Crystal framework.
- [benchmark1](https://github.com/eyszu/crystal-web-framework-benchmark)
- [benchmark2](https://github.com/eyszu/crystal-web-framework-benchmark-2)

## Where the speed comes from

- **The route table is built once.** Each route's middleware chain is composed at registration, so a
  request does no list building. `Next` is a struct, so calling the next layer allocates nothing.
- **Routes without params are a hash lookup** on the request path, one hash per HTTP method.
- **Routes with params use a segment trie** whose static segments are compared with `memcmp` against
  the request path in place. Only the captured param values are allocated.
- **No URI parsing unless you ask.** `req.path` is the raw resource when there is no `?`, and the query
  is parsed on first use of `req.query`.
- **Typed JSON is compiled.** `req.json(User)` uses `JSON::Serializable`, generated at compile time, and
  reads straight into your struct with no intermediate tree. In the earlier Crystal vs Go benchmark this was
  the kind of work Crystal did best.
- **Fibers.** Each connection is a fiber on Crystal's `HTTP::Server`, so there is no thread per connection.
- **Read-only after startup.** Nothing in the framework is mutated while serving. The example server was
  built with `-Dpreview_mt` and `CRYSTAL_WORKERS=2` and served a 5 second load with no errors, but multi-core
  throughput was not benchmarked. Your own shared state is yours to guard.
  
---

*Spectre is MIT licensed.*
