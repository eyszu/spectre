require "http/server"

# Baseline: Crystal's HTTP::Server with no framework, hello world only.
server = HTTP::Server.new do |ctx|
  ctx.response.content_type = "text/plain; charset=utf-8"
  ctx.response.content_length = 13
  ctx.response.print "Hello, World!"
end
server.bind_tcp "0.0.0.0", ENV.fetch("PORT", "3000").to_i
server.listen
