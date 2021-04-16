Gem::Specification.new do |s|
  
  s.name = "mjai"
  s.version = "0.0.7"
  s.authors = ["Hiroshi Ichikawa"]
  s.email = ["gimite+github@gmail.com"]
  s.summary = "Game server for Japanese Mahjong AI."
  s.description = "Game server for Japanese Mahjong AI."
  s.homepage = "https://github.com/gimite/mjai"
  s.license = "New BSD"
  s.rubygems_version = "1.2.0"
  
  s.files = Dir["bin/*"] + Dir["lib/**/*"] + Dir["share/**/*"]
  s.require_paths = ["lib"]
  s.executables = Dir["bin/*"].map(){ |pt| File.basename(pt) }
  s.extra_rdoc_files = []
  s.rdoc_options = []

  s.add_dependency("json", ["2.5.1"])
  s.add_dependency("nokogiri", ["1.11.3"])
  s.add_dependency("bundler", ["2.1.4"])
  s.add_dependency("sass", ["3.1.0"])
  
end
