<img width="300" height="300" alt="Purple Shadow Spirit" src="https://github.com/user-attachments/assets/7310c357-edce-4a26-b08e-bd38f2c14833" />

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

## For full user guide, see [Docs.md](https://github.com/eyszu/spectre/blob/main/Docs.md)

## Benchmark: vs Other Crystal Framework.
- [benchmark1](https://github.com/eyszu/crystal-web-framework-benchmark)
- [benchmark2](https://github.com/eyszu/crystal-web-framework-benchmark-2)


## Real-world App example
- [Radiance](https://github.com/eyszu/radiance)
- [Omu](https://github.com/eyszu/Omu)
- [Shonin](https://github.com/eyszu/shonin)


---

MIT licensed.
