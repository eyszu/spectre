<img width="1254" height="1254" alt="Speeding Lavender Ghost" src="https://github.com/user-attachments/assets/2b3c04bb-968b-478b-a48b-fb1038804fb3" />
# Spectre

An extremely fast, Express.js-style web microframework for Crystal. Routes, middleware, route params,
typed JSON bodies, groups, static files, and `(req, res)` handlers, on top of
Crystal's own `HTTP::Server`.

```crystal
require "spectre"

app = Spectre.new
app.use Spectre::Middleware.logger

app.get "/hello/:name" do |req, res|
  res.json({message: "Hello, #{req.params["name"]}!"})
end

app.listen 3000
```

## Install

Add to `shard.yml`:

```yaml
dependencies:
  spectre:
    github: eyszu/spectre
```
install via shards:

```bash
shards install
```

Requires Crystal 1.10 or newer (developed on 1.11.2). No other dependencies.

## Guide

### Routes

```crystal
app.get    "/users"     { ... }
app.post   "/users"     { ... }
app.put    "/users/:id" { ... }
app.patch  "/users/:id" { ... }
app.delete "/users/:id" { ... }
app.all    "/ping"      { ... }    # every method
```

Write handlers as blocks. Use `do |req, res| ... end`, or parentheses with braces:
`app.get("/") { |req, res| res.send "hi" }`.

Patterns support `:param` segments and a trailing `*` wildcard:

```crystal
app.get "/users/:id/posts/:post_id" do |req, res|
  req.params["id"]          # String
  req.params.int("id")      # Int64, answers 400 if not an integer
end

app.get "/files/*" do |req, res|
  req.params["*"]           # "css/site.css" for /files/css/site.css
end
```

Matching rules:

- Exact static routes win, then static segments, then `:param`, then `*`. So `/users/new` beats `/users/:id`, whatever the registration order.
- A trailing slash is ignored: `/users/` is `/users`.
- Percent-encoded params are decoded.
- Unknown path: `404 Cannot GET /path`. Known path, wrong method: `405` with an `Allow` header.
- `HEAD` is served from `GET` routes (body omitted). `OPTIONS` is answered automatically with `Allow`.
- Registering the same method and pattern twice raises `ArgumentError`.

### Request

| | |
|---|---|
| `req.method`, `req.path`, `req.query_string` | `path` has no query string |
| `req.params` | route params |
| `req.query["page"]?` | parsed on first use |
| `req.header("Authorization")`, `req.headers`, `req.cookies` | |
| `req.body` | text, answers 413 above `app.max_body` (default 1 MB) |
| `req.json` | `JSON::Any`, answers 400 on bad JSON |
| `req.json(User)` | typed, answers 400 on bad JSON and 422 on missing or mistyped fields |
| `req.form` | `application/x-www-form-urlencoded` |
| `req.ip` | peer address |
| `req.locals` | `Hash(String, String)` shared with middleware |
| `req.raw` | the underlying `HTTP::Request` |

For typed per-request data, reopen the class, as you would set `req.user` in Express:

```crystal
class Spectre::Request
  property user : User?
end
```

### Response

All of `status`, `header`, `type`, `cookie` return `res`, so they chain.

```crystal
res.send "text"                          # text/plain
res.html "<h1>Hi</h1>"
res.json({ok: true})                     # NamedTuple, Hash, Array, JSON::Serializable...
res.status(201).json(user)
res.redirect "/login"                    # 302; redirect "/x", 301
res.send_status 204
res.cookie "sid", "abc", max_age: 1.day
res.header "X-Thing", "1"
```

Each response can be sent once. A second `send` raises.

### Middleware

```crystal
app.use do |req, res, nxt|        # `next` is a Crystal keyword, so call it `nxt`
  started = Time.monotonic
  nxt.call
  puts "#{req.path} took #{Time.monotonic - started}"
end

app.use "/admin", auth            # only for paths under /admin
app.get "/me", auth do |req, res| # only for this route
  ...
end
```

`auth` is a `Spectre::Layer`. Build one from a block with `Spectre.layer`:

```crystal
auth = Spectre.layer do |req, res, nxt|
  if req.header("Authorization") == "Bearer secret"
    nxt.call
  else
    res.status(401).json({error: "Unauthorized"})
  end
end
```

Inside blocks, use `next` to leave early, not `return`.

As in Express, order matters: a middleware applies to the routes registered **after** it.
Global middleware also runs for 404, 405 and OPTIONS answers.

Built in:

- `Spectre::Middleware.logger` logs `GET /path 200 0.12ms` through `Log` (source `spectre`).
- `Spectre::Middleware.cors(origin: "*", methods: ..., headers: ..., max_age: 600)` adds CORS headers and answers preflight requests.
- `Spectre::Middleware.static(dir, prefix:, max_age:)`, see below.

### Groups and routers

```crystal
app.group "/api/v1" do |api|
  api.use Spectre::Middleware.cors
  api.get("/users") { |req, res| ... }
end

users = Spectre::Router.new
users.get("/") { |req, res| ... }
users.get("/:id") { |req, res| ... }
app.use "/users", users            # same as app.mount "/users", users
```

### Static files

```crystal
app.static "/assets", "./public", max_age: 3600
```

Serves GET and HEAD with `Content-Type`, `ETag`, `Last-Modified` and `304` support, and `index.html` for
directories. It never serves dotfiles, paths that escape the directory, or symlinks that point outside it.
Explicit routes win over static files, and a missing file falls through to a normal 404.

### Errors

```crystal
app.get "/users/:id" do |req, res|
  user = find(req.params.int("id")) || Spectre.halt(404, "User not found")
  res.json(user)
end

app.error do |ex, req, res|
  status = ex.is_a?(Spectre::HTTPError) ? ex.status : 500
  res.status(status).json({error: status == 500 ? "Internal Server Error" : ex.message})
end

app.not_found { |req, res| res.json({error: "no such route"}) }
```

Without `app.error`, `HTTPError` becomes its status with the message as text, and anything else becomes a
logged `500 Internal Server Error` that does not leak the exception message.

### Running

```crystal
app.listen 3000                       # 0.0.0.0:3000, Ctrl-C and SIGTERM stop it cleanly
app.listen 3000, "127.0.0.1", reuse_port: true
```

`app.call(ctx)` is a plain `HTTP::Server::Context ->` handler, so you can mount Spectre in your own
`HTTP::Server`, add TLS with `bind_tls`, or wrap it in other `HTTP::Handler`s.

### Testing

`app.request` runs a request through the whole stack in memory, with no socket:

```crystal
r = app.request("POST", "/api/users", %({"name":"Ann","age":30}),
  HTTP::Headers{"Authorization" => "Bearer secret"})
r.status_code # => 201
r.body        # => {"id":1,...}
```

Run the specs with `crystal spec`.

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

## Benchmark: vs Go

`bench/run.sh` builds a Spectre server and an equivalent Go `net/http` server (Go 1.22 `ServeMux`
patterns, `encoding/json`), pins each server to one CPU and `wrk` to another, and measures three routes.
Release build, 32 connections, 8 seconds per route, two full runs:

| Route | Spectre req/s | Go net/http req/s |
|---|---|---|
| `GET /` (text) | 138,000 – 159,000 | 65,000 – 67,000 |
| `GET /users/:id` (path param, JSON out) | 117,000 – 118,000 | 50,000 – 54,000 |
| `POST /people` (typed JSON in and out) | 77,000 – 96,000 | 45,000 – 46,000 |

Plain `HTTP::Server` returning the same text as `GET /` did 131,000 – 135,000 req/s in the same setup,
so the router and middleware add no cost that shows up above run-to-run noise.

How to read this: it is one core, on a shared 2-vCPU cloud VM (Xeon 2.1 GHz), Crystal 1.11.2, Go 1.24.7,
with `wrk` on the same machine. Numbers move 10 to 20% between runs, which is why ranges are given.
Multi-core scaling, TLS, keep-alive churn, large bodies and real handlers that hit a database were not
measured. In real applications the database and your own code usually matter far more than the framework.
Run `bench/run.sh` on your own hardware before drawing conclusions. It needs `wrk`, `taskset` and Go.

## Benchmark: vs Grip Etc.
- [benchmark](https://github.com/eyszu/crystal-web-framework-benchmark)

## Differences from Express

- `next` is spelled `nxt`, because `next` is a Crystal keyword.
- Handlers are statically typed. `req.json(User)` gives you a `User`, and mistakes are caught at compile time.
- Exact static routes beat `:param` routes regardless of registration order.
- Routes always beat `app.static`, and static files only run for paths no route matched.
- Not included: sessions, template engines, multipart uploads, WebSocket routing, response compression, HTTP/2.

## Layout

```
src/spectre.cr            entry point
src/spectre/app.cr        App: dispatch, errors, listen, request helper
src/spectre/router.cr     Router DSL: verbs, use, group, mount
src/spectre/route_table.cr  static hash + segment trie
src/spectre/request.cr, response.cr, params.cr, types.cr
src/spectre/middleware.cr, static.cr
examples/app.cr           typed JSON, auth, groups, static files
spec/                     crystal spec
bench/                    Spectre vs Go net/http
```
## Real-world App example
- [Radiance](https://github.com/eyszu/radiance)
- [Omu](https://github.com/eyszu/Omu)


---

MIT licensed.
