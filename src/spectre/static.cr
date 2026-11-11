module Spectre
  module Middleware
    # Serves files from `dir` for GET and HEAD requests under `prefix`, with
    # ETag and 304 support. Falls through to the next layer when no file
    # matches. Dotfiles and anything outside `dir` (including via symlinks)
    # are never served.
    def self.static(dir : String, prefix : String = "/", max_age : Int32? = nil, index : String = "index.html") : Layer
      root = File.realpath(dir)
      root_slash = root.ends_with?('/') ? root : root + "/"
      prefix = Spectre.normalize_path(prefix)
      prefix = "" if prefix == "/"
      prefix_slash = prefix + "/"
      cache = max_age ? "public, max-age=#{max_age}" : nil

      Spectre.layer do |req, res, nxt|
        path = req.path
        served = false
        if (req.method == "GET" || req.method == "HEAD") &&
           (prefix.empty? || path == prefix || path.starts_with?(prefix_slash))
          served = Static.serve(req, res, path.byte_slice(prefix.bytesize), root, root_slash, index, cache)
        end
        nxt.call unless served
      end
    end
  end

  module Static
    def self.serve(req : Request, res : Response, relative : String, root : String,
                   root_slash : String, index : String, cache : String?) : Bool
      relative = URI.decode(relative) if relative.includes?('%')
      return false if relative.includes?('\0') || relative.includes?("/.")

      real = File.realpath(File.join(root, relative))
      if File.directory?(real)
        real = File.realpath(File.join(real, index))
      end
      return false unless real == root || real.starts_with?(root_slash)

      info = File.info?(real)
      return false unless info && info.file?

      etag = %(W/"#{info.size.to_s(16)}-#{info.modification_time.to_unix.to_s(16)}")
      res.header("ETag", etag)
      res.header("Last-Modified", HTTP.format_time(info.modification_time))
      res.header("Cache-Control", cache) if cache

      if req.header("If-None-Match") == etag
        res.send_status(304)
      else
        File.open(real) do |file|
          res.send_io(file, info.size, MIME.from_filename?(real) || "application/octet-stream")
        end
      end
      true
    rescue File::Error
      false
    end
  end
end
