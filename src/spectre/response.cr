module Spectre
  class Response
    getter raw : HTTP::Server::Response
    getter? sent : Bool = false
    # Set for HEAD requests: headers are sent, the body is not.
    property? head_only : Bool = false

    def initialize(@raw : HTTP::Server::Response)
    end

    def status(code : Int32) : self
      @raw.status_code = code
      self
    end

    def status(status : HTTP::Status) : self
      @raw.status = status
      self
    end

    def status_code : Int32
      @raw.status_code
    end

    def header(name : String, value : String) : self
      @raw.headers[name] = value
      self
    end

    def type(content_type : String) : self
      header("Content-Type", content_type)
    end

    def cookies : HTTP::Cookies
      @raw.cookies
    end

    def cookie(name : String, value : String, path : String = "/", max_age : Time::Span? = nil,
               http_only : Bool = true, secure : Bool = false,
               samesite : HTTP::Cookie::SameSite? = HTTP::Cookie::SameSite::Lax) : self
      @raw.cookies << HTTP::Cookie.new(name, value, path: path, max_age: max_age,
        http_only: http_only, secure: secure, samesite: samesite)
      self
    end

    # Sends text. Content-Type defaults to `text/plain`.
    def send(body : String) : Nil
      send(body.to_slice, "text/plain; charset=utf-8")
    end

    def send(body : Bytes, content_type : String = "application/octet-stream") : Nil
      commit!
      @raw.headers["Content-Type"] = content_type unless @raw.headers.has_key?("Content-Type")
      @raw.content_length = body.size
      @raw.write(body) unless @head_only
    end

    def html(body : String) : Nil
      send(body.to_slice, "text/html; charset=utf-8")
    end

    # Serializes any JSON-serializable value (NamedTuple, Hash, Array,
    # `JSON::Serializable` types, ...) and sends it.
    def json(value) : Nil
      send(value.to_json.to_slice, "application/json; charset=utf-8")
    end

    # Sends a status with no body.
    def send_status(code : Int32) : Nil
      status(code)
      commit!
      @raw.content_length = 0
    end

    def redirect(location : String, code : Int32 = 302) : Nil
      status(code)
      header("Location", location)
      send_status(code)
    end

    # Streams `size` bytes from `io` with a Content-Length header.
    def send_io(io : IO, size : Int, content_type : String) : Nil
      commit!
      @raw.headers["Content-Type"] = content_type unless @raw.headers.has_key?("Content-Type")
      @raw.content_length = size
      IO.copy(io, @raw, size) unless @head_only
    end

    private def commit! : Nil
      raise "Response already sent" if @sent
      @sent = true
    end
  end
end
