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

# File uploads. Spectre has no multipart helper, so this uses Crystal's
# HTTP::FormData on `req.raw`. Parse before touching req.body/json/form,
# which would consume the stream.
UPLOAD_DIR = ENV.fetch("UPLOAD_DIR", File.join(Dir.tempdir, "spectre-uploads"))
MAX_UPLOAD = 5_i64 * 1024 * 1024
Dir.mkdir_p(UPLOAD_DIR)

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

app.get "/upload" do |req, res|
  res.html <<-HTML
    <h1>Upload a file</h1>
    <form action="/upload" method="post" enctype="multipart/form-data">
      <input type="file" name="file" required>
      <input type="text" name="note" placeholder="note (optional)">
      <button>Upload</button>
    </form>
    HTML
end

app.post "/upload" do |req, res|
  content_type = req.header("Content-Type") || ""
  Spectre.halt(415, "Expected multipart/form-data") unless content_type.starts_with?("multipart/form-data")

  saved = [] of NamedTuple(name: String, size: Int64)
  note = nil

  HTTP::FormData.parse(req.raw) do |part|
    case part.name
    when "note"
      note = part.body.gets_to_end
    when "file"
      # Drop any client-supplied path, then prefix a random id so names never collide.
      original = File.basename((part.filename || "").gsub('\\', '/'))
      next if original.empty?
      stored = "#{Random::Secure.hex(4)}-#{original.gsub(/[^\w.\-]/, "_")}"
      path = File.join(UPLOAD_DIR, stored)
      size = 0_i64
      File.open(path, "w") do |f|
        # Read one byte past the limit so oversize uploads are detected without buffering them.
        size = IO.copy(IO::Sized.new(part.body, MAX_UPLOAD + 1), f)
      end
      if size > MAX_UPLOAD
        File.delete(path)
        Spectre.halt(413, "File exceeds #{MAX_UPLOAD} bytes")
      end
      saved << {name: stored, size: size}
    end
  end

  Spectre.halt(400, "No file field named 'file'") if saved.empty?
  res.status(201).json({files: saved, note: note})
end

app.get "/uploads/:name" do |req, res|
  name = req.params["name"]
  path = File.join(UPLOAD_DIR, File.basename(name))
  Spectre.halt(404, "Not found") unless File.file?(path)
  File.open(path) do |file|
    res.send_io(file, file.size, MIME.from_filename?(path) || "application/octet-stream")
  end
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
