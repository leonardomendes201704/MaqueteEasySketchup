require 'json'

result_path = File.join(ENV['TEMP'] || Dir.pwd, 'planforge_builder_startup_probe.json')
payload = {
  :status => 'startup-entered',
  :time => Time.now.strftime('%Y-%m-%d %H:%M:%S')
}

File.open(result_path, 'w') do |file|
  file.write(JSON.pretty_generate(payload))
end

UI.start_timer(1.0, false) { Sketchup.quit }
