require "../src/spectre"

struct Person
  include JSON::Serializable
  getter name : String
  getter age : Int32
end

app = Spectre.new
app.get("/") { |req, res| res.send "Hello, World!" }
app.get("/users/:id") { |req, res| res.json({id: req.params["id"], name: "user#{req.params["id"]}"}) }
app.post("/people") do |req, res|
  p = req.json(Person)
  res.json({name: p.name, age: p.age + 1})
end
app.listen ENV.fetch("PORT", "3000").to_i
