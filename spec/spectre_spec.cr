require "./spec_helper"
require "file_utils"

struct SpecUser
  include JSON::Serializable
  getter name : String
  getter age : Int32
end

private def build_app
  app = Spectre.new
  app.get("/") { |req, res| res.send "root" }
  app.get("/users") { |req, res| res.json([1, 2]) }
  app.get("/users/new") { |req, res| res.send "new user form" }
  app.get("/users/:id") { |req, res| res.send "user #{req.params["id"]}" }
  app.post("/users/:id") { |req, res| res.send "posted #{req.params["id"]}" }
  app.get("/users/:id/posts/:post_id") { |req, res| res.json({u: req.params["id"], p: req.params["post_id"]}) }
  app.get("/files/*") { |req, res| res.send "file #{req.params["*"]}" }
  app.get("/search") { |req, res| res.send "q=#{req.query["q"]?} n=#{req.query["n"]?}" }
  app.post("/typed") { |req, res| u = req.json(SpecUser); res.status(201).json({hi: u.name, age: u.age}) }
  app.post("/untyped") { |req, res| res.send req.json["a"].as_i.to_s }
  app.post("/form") { |req, res| res.send req.form["x"] }
  app.get("/halt") { |req, res| Spectre.halt(418, "teapot") }
  app.get("/boom") { |req, res| raise "kaboom" }
  app.get("/int/:n") { |req, res| res.send (req.params.int("n") + 1).to_s }
  app.get("/cookie") { |req, res| res.cookie("sid", "abc"); res.send "ok" }
  app.get("/redirect") { |req, res| res.redirect "/", 301 }
  app
end

describe Spectre do
  app = build_app

  it "matches static routes" do
    r = app.request("GET", "/")
    r.status_code.should eq 200
    r.body.should eq "root"
    r.headers["Content-Type"].should eq "text/plain; charset=utf-8"
  end

  it "prefers static routes over params and falls back to params" do
    app.request("GET", "/users/new").body.should eq "new user form"
    app.request("GET", "/users/42").body.should eq "user 42"
  end

  it "ignores a trailing slash" do
    app.request("GET", "/users/").body.should eq "[1,2]"
    app.request("GET", "/users/7/").body.should eq "user 7"
  end

  it "captures multiple params" do
    r = app.request("GET", "/users/3/posts/9")
    r.headers["Content-Type"].should eq "application/json; charset=utf-8"
    r.body.should eq %({"u":"3","p":"9"})
  end

  it "decodes percent-encoded params" do
    app.request("GET", "/users/a%20b").body.should eq "user a b"
  end

  it "captures wildcard tails" do
    app.request("GET", "/files/css/site.css").body.should eq "file css/site.css"
    app.request("GET", "/files").body.should eq "file "
  end

  it "keeps method-specific routes apart" do
    app.request("POST", "/users/5").body.should eq "posted 5"
  end

  it "parses query strings" do
    app.request("GET", "/search?q=crystal&n=2").body.should eq "q=crystal n=2"
    app.request("GET", "/search").body.should eq "q= n="
  end

  it "answers 404 with Express's wording" do
    r = app.request("GET", "/missing")
    r.status_code.should eq 404
    r.body.should eq "Cannot GET /missing"
  end

  it "answers 405 with an Allow header" do
    r = app.request("DELETE", "/users/5")
    r.status_code.should eq 405
    r.headers["Allow"].should eq "GET, POST, HEAD, OPTIONS"
  end

  it "answers OPTIONS automatically" do
    r = app.request("OPTIONS", "/users")
    r.status_code.should eq 204
    r.headers["Allow"].should contain "GET"
  end

  it "answers HEAD from GET routes without a body" do
    r = app.request("HEAD", "/")
    r.status_code.should eq 200
    r.headers["Content-Length"].should eq "4"
    r.body.should eq ""
  end

  it "binds typed JSON bodies" do
    r = app.request("POST", "/typed", %({"name":"Ann","age":3}))
    r.status_code.should eq 201
    r.body.should eq %({"hi":"Ann","age":3})
  end

  it "answers 422 for missing fields and 400 for bad JSON" do
    app.request("POST", "/typed", %({"name":"Ann"})).status_code.should eq 422
    app.request("POST", "/typed", "{nope").status_code.should eq 400
    app.request("POST", "/untyped", "{nope").status_code.should eq 400
    app.request("POST", "/untyped", %({"a":5})).body.should eq "5"
  end

  it "parses form bodies" do
    app.request("POST", "/form", "x=hello+world").body.should eq "hello world"
  end

  it "turns HTTPError into a response" do
    r = app.request("GET", "/halt")
    r.status_code.should eq 418
    r.body.should eq "teapot"
  end

  it "hides internal errors behind a 500" do
    r = app.request("GET", "/boom")
    r.status_code.should eq 500
    r.body.should eq "Internal Server Error"
  end

  it "validates integer params" do
    app.request("GET", "/int/4").body.should eq "5"
    app.request("GET", "/int/x").status_code.should eq 400
  end

  it "sets cookies and redirects" do
    app.request("GET", "/cookie").headers["Set-Cookie"].should contain "sid=abc"
    r = app.request("GET", "/redirect")
    r.status_code.should eq 301
    r.headers["Location"].should eq "/"
  end

  it "rejects oversized bodies" do
    small = Spectre.new
    small.max_body = 8
    small.post("/") { |req, res| res.send req.body }
    small.request("POST", "/", "12345678").status_code.should eq 200
    small.request("POST", "/", "123456789").status_code.should eq 413
  end

  it "rejects duplicate routes" do
    dup = Spectre.new
    dup.get("/a") { |req, res| }
    dup.get("/a") { |req, res| }
    expect_raises(ArgumentError, /Duplicate/) { dup.build! }
  end
end

describe "middleware" do
  it "runs in registration order around the handler" do
    app = Spectre.new
    trace = [] of String
    app.use { |req, res, nxt| trace << "a-in"; nxt.call; trace << "a-out" }
    app.use { |req, res, nxt| trace << "b-in"; nxt.call; trace << "b-out" }
    app.get("/") { |req, res| trace << "handler"; res.send "ok" }
    app.request("GET", "/").body.should eq "ok"
    trace.should eq ["a-in", "b-in", "handler", "b-out", "a-out"]
  end

  it "applies only to routes registered after it" do
    app = Spectre.new
    app.get("/before") { |req, res| res.send req.locals["tag"]? || "none" }
    app.use { |req, res, nxt| req.locals["tag"] = "set"; nxt.call }
    app.get("/after") { |req, res| res.send req.locals["tag"]? || "none" }
    app.request("GET", "/before").body.should eq "none"
    app.request("GET", "/after").body.should eq "set"
  end

  it "can stop the chain" do
    app = Spectre.new
    app.use { |req, res, nxt| res.status(401).send "no" }
    app.get("/") { |req, res| res.send "secret" }
    r = app.request("GET", "/")
    r.status_code.should eq 401
    r.body.should eq "no"
  end

  it "supports prefix-scoped and route-level middleware" do
    app = Spectre.new
    app.use("/admin") { |req, res, nxt| res.header("X-Admin", "1"); nxt.call }
    only = Spectre.layer { |req, res, nxt| res.header("X-Only", "1"); nxt.call }
    app.get("/admin/panel") { |req, res| res.send "panel" }
    app.get("/public") { |req, res| res.send "public" }
    app.get("/special", only) { |req, res| res.send "special" }
    app.request("GET", "/admin/panel").headers["X-Admin"].should eq "1"
    app.request("GET", "/public").headers["X-Admin"]?.should be_nil
    app.request("GET", "/special").headers["X-Only"].should eq "1"
  end

  it "runs global middleware for 404s" do
    app = Spectre.new
    app.use { |req, res, nxt| res.header("X-Seen", "1"); nxt.call }
    app.request("GET", "/nothing").headers["X-Seen"].should eq "1"
  end

  it "supports groups and mounted routers" do
    app = Spectre.new
    app.group "/api" do |api|
      api.use { |req, res, nxt| res.header("X-Api", "1"); nxt.call }
      api.get("/ping") { |req, res| res.send "pong" }
      api.get("/items/:id") { |req, res| res.send "item #{req.params["id"]}" }
    end
    v2 = Spectre::Router.new
    v2.get("/ping") { |req, res| res.send "pong2" }
    app.use "/v2", v2

    r = app.request("GET", "/api/ping")
    r.body.should eq "pong"
    r.headers["X-Api"].should eq "1"
    app.request("GET", "/api/items/8").body.should eq "item 8"
    app.request("GET", "/v2/ping").body.should eq "pong2"
  end

  it "answers CORS preflight" do
    app = Spectre.new
    app.use Spectre::Middleware.cors(origin: "https://example.com")
    app.get("/x") { |req, res| res.send "x" }
    h = HTTP::Headers{"Origin" => "https://example.com", "Access-Control-Request-Method" => "GET"}
    r = app.request("OPTIONS", "/x", headers: h)
    r.status_code.should eq 204
    r.headers["Access-Control-Allow-Origin"].should eq "https://example.com"
    r.headers["Access-Control-Allow-Methods"].should contain "GET"
    app.request("GET", "/x").headers["Access-Control-Allow-Origin"].should eq "https://example.com"
  end
end

describe "custom handlers" do
  it "uses custom not_found and error handlers" do
    app = Spectre.new
    app.get("/boom") { |req, res| raise "x" }
    app.get("/teapot") { |req, res| Spectre.halt(418, "short and stout") }
    app.not_found { |req, res| res.json({error: "nope", path: req.path}) }
    app.error do |ex, req, res|
      status = ex.is_a?(Spectre::HTTPError) ? ex.status : 500
      res.status(status).json({error: ex.message})
    end
    r = app.request("GET", "/zzz")
    r.status_code.should eq 404
    r.body.should eq %({"error":"nope","path":"/zzz"})
    app.request("GET", "/teapot").body.should eq %({"error":"short and stout"})
    app.request("GET", "/boom").status_code.should eq 500
  end
end

describe "static files" do
  dir = File.join(Dir.tempdir, "spectre_spec_#{Process.pid}")
  Dir.mkdir_p(File.join(dir, "pub", "sub"))
  File.write(File.join(dir, "pub", "a.txt"), "hello")
  File.write(File.join(dir, "pub", "sub", "index.html"), "<p>idx</p>")
  File.write(File.join(dir, "pub", ".hidden"), "secret")
  File.write(File.join(dir, "outside.txt"), "outside")
  File.symlink(File.join(dir, "outside.txt"), File.join(dir, "pub", "link.txt"))

  app = Spectre.new
  app.static "/s", File.join(dir, "pub"), max_age: 60
  app.get("/s/dyn") { |req, res| res.send "dynamic" }

  Spec.after_suite { FileUtils.rm_rf(dir) }

  it "serves files with type, ETag and cache headers" do
    r = app.request("GET", "/s/a.txt")
    r.status_code.should eq 200
    r.body.should eq "hello"
    r.headers["Content-Type"].should eq "text/plain"
    r.headers["Cache-Control"].should eq "public, max-age=60"
    r.headers["ETag"].should_not be_nil
  end

  it "answers 304 for a matching ETag" do
    etag = app.request("GET", "/s/a.txt").headers["ETag"]
    r = app.request("GET", "/s/a.txt", headers: HTTP::Headers{"If-None-Match" => etag})
    r.status_code.should eq 304
    r.body.should eq ""
  end

  it "serves directory indexes" do
    app.request("GET", "/s/sub/").body.should eq "<p>idx</p>"
  end

  it "does not serve dotfiles, traversal, or symlinks that escape" do
    app.request("GET", "/s/.hidden").status_code.should eq 404
    app.request("GET", "/s/../outside.txt").status_code.should eq 404
    app.request("GET", "/s/%2e%2e/outside.txt").status_code.should eq 404
    app.request("GET", "/s/link.txt").status_code.should eq 404
  end

  it "lets explicit routes win and falls through when no file exists" do
    app.request("GET", "/s/dyn").body.should eq "dynamic"
    app.request("GET", "/s/nothing.txt").status_code.should eq 404
  end
end
