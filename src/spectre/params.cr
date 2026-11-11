module Spectre
  # Route parameters (`/users/:id`). The names belong to the route and are
  # shared by every request; only the values array is allocated per request.
  struct Params
    include Enumerable({String, String})

    EMPTY = Params.new([] of String, [] of String)

    def initialize(@names : Array(String), @values : Array(String))
    end

    def []?(name : String) : String?
      i = 0
      count = @values.size
      while i < count
        return @values.unsafe_fetch(i) if @names.unsafe_fetch(i) == name
        i += 1
      end
      nil
    end

    def [](name : String) : String
      self[name]? || raise KeyError.new("Missing route parameter: #{name}")
    end

    # Returns the parameter as an integer, or answers 400 if it is not one.
    def int(name : String) : Int64
      self[name].to_i64? || raise HTTPError.new(400, "Route parameter '#{name}' must be an integer")
    end

    def size : Int32
      @values.size
    end

    def each(& : {String, String} ->) : Nil
      @values.each_with_index { |value, i| yield({@names[i], value}) }
    end
  end
end
