module Spectre
  enum Verb
    GET
    POST
    PUT
    PATCH
    DELETE
    HEAD
    OPTIONS

    def self.from_method(method : String) : Verb?
      case method
      when "GET"     then GET
      when "POST"    then POST
      when "PUT"     then PUT
      when "PATCH"   then PATCH
      when "DELETE"  then DELETE
      when "HEAD"    then HEAD
      when "OPTIONS" then OPTIONS
      end
    end
  end

  class Route
    getter pattern : String
    getter param_names : Array(String)
    getter chain : Array(Layer)

    def initialize(@pattern : String, @param_names : Array(String), @chain : Array(Layer))
    end
  end

  # One path segment in the dynamic-route trie.
  class Node
    getter keys = [] of String
    getter nodes = [] of Node
    property param_child : Node?
    @routes = StaticArray(Route?, 7).new(nil)
    @wild = StaticArray(Route?, 7).new(nil)

    def route(verb : Verb) : Route?
      @routes[verb.value]
    end

    def set_route(verb : Verb, route : Route) : Nil
      @routes[verb.value] = route
    end

    def wild(verb : Verb) : Route?
      @wild[verb.value]
    end

    def set_wild(verb : Verb, route : Route) : Nil
      @wild[verb.value] = route
    end

    def child(segment : String) : Node
      if i = @keys.index(segment)
        @nodes[i]
      else
        node = Node.new
        @keys << segment
        @nodes << node
        node
      end
    end
  end

  # Two lookup structures, both read-only once the server is running:
  #
  # * one Hash per HTTP method for routes without parameters, so `/users` is
  #   a single hash lookup on the request path with no allocation;
  # * a segment trie for `:param` and `*` routes. Static segments are compared
  #   with `memcmp` straight against the request path, so only the captured
  #   parameter values are allocated.
  #
  # Priority: exact static routes, then static segments, then `:param`, then `*`.
  class RouteTable
    NO_VALUES = [] of String

    @static : Array(Hash(String, Route))
    @root = Node.new
    @dynamic = false

    def initialize
      @static = Array(Hash(String, Route)).new(7) { Hash(String, Route).new }
    end

    def add(verb : Verb, pattern : String, chain : Array(Layer)) : Nil
      unless pattern.includes?(':') || pattern.includes?('*')
        table = @static[verb.value]
        raise ArgumentError.new("Duplicate route: #{verb} #{pattern}") if table.has_key?(pattern)
        table[pattern] = Route.new(pattern, NO_VALUES, chain)
        return
      end

      names = [] of String
      node = @root
      segments = pattern.split('/', remove_empty: true)
      segments.each_with_index do |segment, i|
        case segment[0]
        when ':'
          raise ArgumentError.new("Empty parameter name in #{pattern}") if segment.size == 1
          names << segment[1..]
          child = node.param_child
          unless child
            child = Node.new
            node.param_child = child
          end
          node = child
        when '*'
          raise ArgumentError.new("'*' must be the last segment in #{pattern}") unless i == segments.size - 1
          raise ArgumentError.new("Duplicate route: #{verb} #{pattern}") if node.wild(verb)
          names << "*"
          node.set_wild(verb, Route.new(pattern, names, chain))
          @dynamic = true
          return
        else
          node = node.child(segment)
        end
      end

      raise ArgumentError.new("Duplicate route: #{verb} #{pattern}") if node.route(verb)
      node.set_route(verb, Route.new(pattern, names, chain))
      @dynamic = true
    end

    # Returns the route and the captured parameter values, or nil.
    def find(verb : Verb, path : String) : {Route, Array(String)}?
      table = @static.unsafe_fetch(verb.value)
      if route = table[path]?
        return {route, NO_VALUES}
      end

      # Non-strict routing: "/users/" is "/users".
      size = path.bytesize
      if size > 1 && path.to_unsafe[size - 1] == '/'.ord
        path = path.byte_slice(0, size - 1)
        if route = table[path]?
          return {route, NO_VALUES}
        end
      end

      return nil unless @dynamic
      values = [] of String
      if route = walk(@root, path, 1, verb, values)
        {route, values}
      end
    end

    # Every method that has a route for `path`, for 405 and OPTIONS answers.
    def allowed(path : String) : Array(Verb)
      list = [] of Verb
      Verb.each { |verb| list << verb if find(verb, path) }
      list << Verb::HEAD if list.includes?(Verb::GET) && !list.includes?(Verb::HEAD)
      list << Verb::OPTIONS unless list.empty? || list.includes?(Verb::OPTIONS)
      list
    end

    private def walk(node : Node, path : String, pos : Int32, verb : Verb, values : Array(String)) : Route?
      size = path.bytesize

      if pos >= size
        if route = node.route(verb)
          return route
        end
        if route = node.wild(verb)
          values << ""
          return route
        end
        return nil
      end

      ptr = path.to_unsafe
      seg_end = pos
      while seg_end < size && ptr[seg_end] != '/'.ord
        seg_end += 1
      end
      len = seg_end - pos
      next_pos = seg_end < size ? seg_end + 1 : size

      if len > 0
        keys = node.keys
        i = 0
        while i < keys.size
          key = keys.unsafe_fetch(i)
          if key.bytesize == len && (ptr + pos).memcmp(key.to_unsafe, len) == 0
            if route = walk(node.nodes.unsafe_fetch(i), path, next_pos, verb, values)
              return route
            end
            break
          end
          i += 1
        end

        if child = node.param_child
          raw = String.new(ptr + pos, len)
          values << (raw.includes?('%') ? URI.decode(raw) : raw)
          if route = walk(child, path, next_pos, verb, values)
            return route
          end
          values.pop
        end
      end

      if route = node.wild(verb)
        values << path.byte_slice(pos, size - pos)
        return route
      end
      nil
    end
  end
end
