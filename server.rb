# encoding: UTF-8
require 'webrick'
require 'json'
require_relative 'build_index'

PORT = 8080
TRAVEL_DIR = LOCAL_TRAVEL_DIR


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
    updated_state = build_pwa!
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
      next if f.include?("state.json") || f.include?("index.html") || f.include?(".git")
      last_snapshot[f] = File.mtime(f) rescue nil if File.file?(f)
    end
  end

  loop do
    sleep 10
    current_snapshot = {}
    scan_dirs.each do |dir|
      Dir.glob(File.join(dir, "**", "*")).each do |f|
        next if f.include?("state.json") || f.include?("index.html") || f.include?(".git")
        current_snapshot[f] = File.mtime(f) rescue nil if File.file?(f)
      end
    end

    if current_snapshot != last_snapshot
      puts "\n[OneDrive Watcher] Detected changes in files. Re-syncing automatically..."
      begin
        build_pwa!
        last_snapshot = current_snapshot
        puts "[OneDrive Watcher] Auto-sync complete at #{Time.now.strftime('%H:%M:%S')}."
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
