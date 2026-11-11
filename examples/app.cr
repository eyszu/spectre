require "../src/spectre"

# Typed request bodies: the JSON mapping is generated at compile time.
struct NewUser
  include JSON::Serializable
  getter name : String
  getter age : Int32
end

struct User
  include JSON::Serializable
  getter id : Int64
  getter name : String
  getter age : Int32

  def initialize(@id, @name, @age)
  end
end

USERS = {} of Int64 => User
NEXT_ID = Atomic(Int64).new(1_i64)

app = Spectre.new
app.use Spectre::Middleware.logger
app.static "/assets", File.join(__DIR__, "public")

app.get "/" do |req, res|
  res.send "Hello from Spectre"
end

app.get "/hello/:name" do |req, res|
  greeting = req.query["greeting"]? || "Hello"
  res.json({message: "#{greeting}, #{req.params["name"]}!"})
end

auth = Spectre.layer do |req, res, nxt|
  if req.header("Authorization") == "Bearer secret"
    nxt.call
  else
    res.status(401).json({error: "Unauthorized"})
  end
end

app.group "/api" do |api|
  api.use Spectre::Middleware.cors

  api.get "/users" do |req, res|
    res.json(USERS.values)
  end

  api.get "/users/:id" do |req, res|
    user = USERS[req.params.int("id")]? || Spectre.halt(404, "User not found")
    res.json(user)
  end

  api.post "/users", auth do |req, res|
    input = req.json(NewUser)
    id = NEXT_ID.add(1)
    user = User.new(id, input.name, input.age)
    USERS[id] = user
    res.status(201).json(user)
  end
end

app.error do |ex, req, res|
  status = ex.is_a?(Spectre::HTTPError) ? ex.status : 500
  res.status(status).json({error: status == 500 ? "Internal Server Error" : ex.message})
end

app.listen ENV.fetch("PORT", "3000").to_i
