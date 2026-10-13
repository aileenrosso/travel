# encoding: UTF-8
require 'webrick'
require 'json'
require_relative 'build_index'

PORT = 8080
TRAVEL_DIR = LOCAL_TRAVEL_DIR


def auto_push_to_github!
  Dir.chdir(TRAVEL_DIR) do
    status = `git status --porcelain state.json index.html 2>/dev/null`.strip
    unless status.empty?
      puts "[GitHub Auto-Push] Pushing updated state.json & index.html to GitHub Pages..."
      system("git add state.json index.html && git commit -m 'Auto-sync OneDrive updates' && git push origin main")
    end
  end
rescue => e
  puts "[GitHub Auto-Push] Warning: #{e.message}"
end

class SyncServlet < WEBrick::HTTPServlet::AbstractServlet
  def do_OPTIONS(req, res)
    res['Access-Control-Allow-Origin'] = '*'
    res['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    res['Access-Control-Allow-Headers'] = '*'
    res.status = 200
  end

  def do_GET(req, res)
    handle_sync(req, res)
  end

  def do_POST(req, res)
    handle_sync(req, res)
  end

  private

  def handle_sync(req, res)
    puts "\n[API /api/sync] Triggered sync request from client..."
    load File.join(TRAVEL_DIR, "build_index.rb")
    updated_state = build_pwa!
    Thread.new { auto_push_to_github! }
    res['Access-Control-Allow-Origin'] = '*'
    res['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    res['Access-Control-Allow-Headers'] = '*'
    res['Content-Type'] = 'application/json; charset=utf-8'
    res.body = JSON.generate(updated_state)
    res.status = 200
  end
end

server = WEBrick::HTTPServer.new(
  Port: PORT,
  DocumentRoot: TRAVEL_DIR,
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)

server.mount('/api/sync', SyncServlet)

# Background file watcher for OneDrive updates
Thread.new do
  last_snapshot = {}
  scan_dirs = [TRAVEL_DIR, ONEDRIVE_DIR].uniq.select { |d| Dir.exist?(d) }

  # Initial snapshot
  scan_dirs.each do |dir|
    Dir.glob(File.join(dir, "**", "*")).each do |f|
      next if f.include?("state.json") || f.include?("index.html") || f.include?(".git") || f.include?("server.log")
      last_snapshot[f] = File.mtime(f) rescue nil if File.file?(f)
    end
  end

  loop do
    sleep 10
    current_snapshot = {}
    scan_dirs.each do |dir|
      Dir.glob(File.join(dir, "**", "*")).each do |f|
        next if f.include?("state.json") || f.include?("index.html") || f.include?(".git") || f.include?("server.log")
        current_snapshot[f] = File.mtime(f) rescue nil if File.file?(f)
      end
    end

    if current_snapshot != last_snapshot
      puts "\n[OneDrive Watcher] Detected changes in files. Re-syncing automatically..."
      begin
        load File.join(TRAVEL_DIR, "build_index.rb")
        build_pwa!
        auto_push_to_github!
        last_snapshot = current_snapshot
        puts "[OneDrive Watcher] Auto-sync & GitHub push complete at #{Time.now.strftime('%H:%M:%S')}."
      rescue => e
        puts "[OneDrive Watcher] Error during auto-sync: #{e.message}"
      end
    end
  end
end

trap('INT') { server.shutdown }
trap('TERM') { server.shutdown }

puts "=" * 60
puts " Travel Planner Local Sync Server & OneDrive Watcher Running"
puts " URL: http://localhost:#{PORT}"
puts " API Endpoint: http://localhost:#{PORT}/api/sync"
puts " OneDrive Watcher: Monitoring #{ONEDRIVE_DIR}"
puts "=" * 60

server.start
