Gem::Specification.new do |s|
  s.name = "btcwhalewatch"
  s.version = "0.0.1"
  s.summary = "btcwhalewatch"
  s.authors = [ "Jeremy Deininger" ]
  s.email = [ "jeremydeininger@gmail.com" ]
  s.executables = []
  s.bindir = "bin"
  s.files = Dir.glob("lib/**/*.rb") + \
    Dir.glob("test/**/*.rb")
  s.add_runtime_dependency("websocket-protocol")
  s.add_runtime_dependency("celluloid-io")
  s.add_runtime_dependency("reel")
  s.add_runtime_dependency("cinch")
  s.add_runtime_dependency("cinch-identify")

  s.add_development_dependency("pry")
  s.add_development_dependency("rspec")
end
