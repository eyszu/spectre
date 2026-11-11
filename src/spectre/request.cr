module Spectre
  class Request
    getter raw : HTTP::Request
    # The request path without the query string. No allocation when the URL has no query.
    getter path : String
    getter query_string : String
    property params : Params = Params::EMPTY
    @query : URI::Params?
    @body : String?
    @locals : Hash(String, String)?

    def initialize(@raw : HTTP::Request, @max_body : Int32 = 1_048_576)
      resource = @raw.resource
      if idx = resource.byte_index('?'.ord)
        @path = resource.byte_slice(0, idx)
        @query_string = resource.byte_slice(idx + 1)
      else
        @path = resource
        @query_string = ""
      end
    end

    def method : String
      @raw.method
    end

    def headers : HTTP::Headers
      @raw.headers
    end

    def header(name : String) : String?
      @raw.headers[name]?
    end

    def cookies : HTTP::Cookies
      @raw.cookies
    end

    # Parsed query string, on first use.
    def query : URI::Params
      @query ||= URI::Params.parse(@query_string)
    end

    def ip : String?
      @raw.remote_address.try { |addr| addr.as?(Socket::IPAddress).try(&.address) }
    end

    # Small string values shared between middleware and handlers. For typed
    # data, reopen the class: `class Spectre::Request; property user : User?; end`.
    def locals : Hash(String, String)
      @locals ||= {} of String => String
    end

    # The body as text. Answers 413 when it exceeds `App#max_body`.
    def body : String
      @body ||= read_body
    end

    # Parses the body as untyped JSON. Answers 400 on invalid JSON.
    def json : JSON::Any
      JSON.parse(body)
    rescue ex : JSON::ParseException
      raise HTTPError.new(400, "Invalid JSON: #{ex.message.to_s.lines.first? || ""}")
    end

    # Parses the body straight into `type` (anything `JSON::Serializable`).
    # The mapping is generated at compile time, with no intermediate tree.
    # Answers 400 on invalid JSON and 422 when fields are missing or mistyped.
    def json(type : T.class) : T forall T
      T.from_json(body)
    rescue ex : JSON::SerializableError
      raise HTTPError.new(422, "Invalid payload: #{ex.message.to_s.lines.first? || ""}")
    rescue ex : JSON::ParseException
      raise HTTPError.new(400, "Invalid JSON: #{ex.message.to_s.lines.first? || ""}")
    end

    # Parses an `application/x-www-form-urlencoded` body.
    def form : URI::Params
      URI::Params.parse(body)
    end

    private def read_body : String
      io = @raw.body
      return "" unless io
      if len = @raw.headers["Content-Length"]?.try(&.to_i64?)
        raise HTTPError.new(413) if len > @max_body
      end
      text = IO::Sized.new(io, @max_body.to_i64 + 1).gets_to_end
      raise HTTPError.new(413) if text.bytesize > @max_body
      text
    end
  end
end
