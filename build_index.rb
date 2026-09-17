# encoding: UTF-8
require 'json'
require 'date'

ONEDRIVE_DIR = "/Users/aileenrosso/Library/CloudStorage/OneDrive-Medholdings,Inc/Personal Documentos/Antigravity"
LOCAL_TRAVEL_DIR = File.expand_path(File.dirname(__FILE__))

def purge_past_events_and_files!(state_data, current_date = Date.today)
  puts "Checking for past events and files before #{current_date}..."
  
  dirs_to_check = [LOCAL_TRAVEL_DIR, ONEDRIVE_DIR].uniq.select { |d| Dir.exist?(d) }
  
  # 1. Look for known past event files (e.g. Sept 9)
  past_patterns = ["*Sept 9*", "*Sep 9*", "*09Sep*", "*Sept09*"]
  dirs_to_check.each do |dir|
    past_patterns.each do |pat|
      Dir.glob(File.join(dir, "**", pat)).each do |f|
        if File.file?(f) && !f.include?(".git")
          puts "[PURGE] Deleting past event file: #{f}"
          File.delete(f) rescue puts "Could not delete #{f}"
        end
      end
    end
  end

  # 2. Automatically remove past trips from state if end date has passed
  before_count = (state_data["trips"] || []).size
  state_data["trips"] = (state_data["trips"] || []).reject do |trip|
    end_d = Date.parse(trip["endDate"]) rescue nil
    is_past = end_d && end_d < current_date
    if is_past
      puts "[PURGE] Removing expired past trip from active state: #{trip['title']} (ended #{trip['endDate']})"
    end
    is_past
  end
  puts "Active & upcoming trips remaining: #{state_data['trips'].size} (purged #{before_count - state_data['trips'].size})"
end

def ingest_directory_updates(state_data)
  scan_dirs = [LOCAL_TRAVEL_DIR, ONEDRIVE_DIR].uniq.select { |d| Dir.exist?(d) }
  discovered_files = []

  scan_dirs.each do |dir|
    Dir.glob(File.join(dir, "**", "*.{pdf,PDF,json,JSON,txt,eml}")).each do |f|
      discovered_files << f unless f.include?("state.json") || f.include?("manifest.json")
    end
  end

  today = Date.today
  purge_past_events_and_files!(state_data, today)

  # Automatically evaluate and update trip status based on today's date
  (state_data["trips"] || []).each do |trip|
    begin
      start_d = Date.parse(trip["startDate"]) rescue nil
      end_d = Date.parse(trip["endDate"]) rescue nil

      if end_d && end_d < today
        trip["status"] = "past"
        trip["category"] = "past"
      elsif start_d && end_d && start_d <= today && end_d >= today
        trip["status"] = "active"
        trip["category"] = "active"
      elsif start_d && start_d > today
        trip["status"] = "upcoming"
        trip["category"] = "upcoming"
      end
    rescue => e
    end
  end

  # The earliest upcoming trip is the Active / Immediate hero
  active_trips = (state_data["trips"] || []).select { |t| t["status"] == "active" }
  if active_trips.empty?
    upcoming_trips = (state_data["trips"] || []).select { |t| t["status"] == "upcoming" }.sort_by { |t| t["startDate"] || "9999" }
    if upcoming_trips.any?
      upcoming_trips.first["status"] = "active"
      upcoming_trips.first["category"] = "active"
    end
  end

  state_data["version"] = "5.4"
  state_data["lastUpdated"] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
  state_data["discoveredFilesCount"] = discovered_files.size

  File.write(File.join(LOCAL_TRAVEL_DIR, "state.json"), JSON.pretty_generate(state_data), encoding: "UTF-8")
  puts "Ingestion complete: scanned #{discovered_files.size} document files across OneDrive and local Travel directory."
  state_data
end

def build_pwa!
  raw_json = File.read(File.join(LOCAL_TRAVEL_DIR, "state.json"), encoding: "UTF-8")
  state_data = JSON.parse(raw_json)
  state_data = ingest_directory_updates(state_data)

  html_content = <<-'HTML_HEADER'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
    <title>Travel Planner · Milton & Aileen</title>
    
    <!-- PWA Settings for iOS & Android -->
    <link rel="manifest" href="./manifest.json">
    <link rel="apple-touch-icon" href="./apple-touch-icon.png">
    <link rel="apple-touch-icon" sizes="180x180" href="./apple-touch-icon.png">
    <link rel="apple-touch-icon" sizes="192x192" href="./icon-192.png">
    <link rel="icon" type="image/png" sizes="192x192" href="./icon-192.png">
    <link rel="icon" type="image/png" sizes="512x512" href="./icon-512.png">
    <meta name="theme-color" content="#FAF7F2">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="Travel">
    <meta name="format-detection" content="telephone=no">
    
    <!-- Premium Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,600;0,700;1,400&family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    
    <style>
        :root {
            --bg-body: #FAF7F2;
            --bg-card: #FFFFFF;
            --border-subtle: #E8E2D8;
            --text-main: #1F1B18;
            --text-muted: #7E7266;
            --gold: #C9A84C;
            --gold-dark: #8F7226;
            --gold-light: rgba(201, 168, 76, 0.09);
            --gold-border: rgba(201, 168, 76, 0.35);
            --navy: #0F1D2E;
            --emerald: #059669;
            --transition: all 0.28s cubic-bezier(0.16, 1, 0.3, 1);
        }
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            -webkit-tap-highlight-color: transparent;
            -webkit-touch-callout: none;
        }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
            background-color: var(--bg-body);
            color: var(--text-main);
            line-height: 1.45;
            overflow-x: hidden;
            -webkit-font-smoothing: antialiased;
            overscroll-behavior-y: none;
        }
        body::after {
            content: '';
            position: fixed; inset: 0; z-index: 999; pointer-events: none;
            opacity: 0.018; mix-blend-mode: multiply;
            background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E");
            background-repeat: repeat;
        }
        .app-shell {
            display: flex;
            flex-direction: column;
            min-height: 100vh;
            position: relative;
            max-width: 720px;
            margin: 0 auto;
        }
        header {
            position: sticky;
            top: 0;
            background-color: rgba(250, 247, 242, 0.94);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border-bottom: 1px solid var(--border-subtle);
            min-height: calc(64px + env(safe-area-inset-top, 0px));
            padding-top: env(safe-area-inset-top, 0px);
            padding-left: calc(18px + env(safe-area-inset-left, 0px));
            padding-right: calc(18px + env(safe-area-inset-right, 0px));
            display: flex;
            align-items: center;
            justify-content: space-between;
            user-select: none;
            -webkit-user-select: none;
            z-index: 200;
        }
        .logo-text {
            font-family: 'Cormorant Garamond', serif;
            font-size: 1.55rem;
            font-weight: 700;
            color: var(--text-main);
            line-height: 1;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .header-actions {
            display: flex;
            align-items: center;
            gap: 6px;
        }
        .header-btn {
            background: var(--gold-light);
            border: 1px solid var(--gold-border);
            color: var(--gold-dark);
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.72rem;
            font-weight: 700;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 5px;
            transition: var(--transition);
            text-decoration: none;
        }
        .header-btn:active {
            transform: scale(0.96);
            background-color: rgba(201, 168, 76, 0.2);
        }

        /* Top Breadcrumb Bar */
        .breadcrumb-bar {
            display: none;
            align-items: center;
            justify-content: space-between;
            padding: 10px 18px;
            background: #FFFFFF;
            border-bottom: 1px solid var(--border-subtle);
            animation: fadeIn 0.2s ease;
        }
        .breadcrumb-bar.active { display: flex; }
        .back-btn {
            background: none;
            border: none;
            color: var(--gold-dark);
            font-size: 0.8rem;
            font-weight: 700;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            cursor: pointer;
        }
        .back-btn:active { opacity: 0.7; }
        .breadcrumb-title {
            font-size: 0.76rem;
            color: var(--text-muted);
            font-weight: 600;
            max-width: 220px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        /* Screens Container */
        .main-content {
            flex: 1;
            padding: 16px calc(18px + env(safe-area-inset-right, 0px)) calc(100px + env(safe-area-inset-bottom, 0px)) calc(18px + env(safe-area-inset-left, 0px));
            -webkit-overflow-scrolling: touch;
        }
        .screen {
            display: none;
            opacity: 0;
            transform: translateY(8px);
            transition: var(--transition);
        }
        .screen.active {
            display: block;
            opacity: 1;
            transform: translateY(0);
        }

        /* Section Titles */
        .dashboard-section-title {
            font-size: 0.72rem;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 0.1em;
            color: var(--text-muted);
            margin: 24px 0 12px 2px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        /* Timepage / Timeo Ultra Tactile Trip Cards */
        .trip-card-hero {
            position: relative;
            border-radius: 22px;
            overflow: hidden;
            margin-bottom: 22px;
            box-shadow: 0 14px 34px rgba(15, 29, 46, 0.18);
            background: #0F1D2E;
            cursor: pointer;
            transition: transform 0.22s ease, box-shadow 0.22s ease;
            border: 1px solid rgba(201, 168, 76, 0.4);
        }
        .trip-card-hero:active {
            transform: scale(0.985);
        }
        .trip-card-hero img {
            position: absolute;
            inset: 0;
            width: 100%;
            height: 100%;
            object-fit: cover;
            filter: brightness(0.55) contrast(1.1);
            transition: transform 0.4s ease;
        }
        .trip-card-hero-overlay {
            position: relative;
            z-index: 2;
            padding: 22px 20px;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
            min-height: 250px;
            color: #FFF;
        }

        .trip-card-grid {
            display: grid;
            grid-template-columns: 1fr;
            gap: 16px;
        }
        .trip-card-item {
            background: #FFFFFF;
            border: 1px solid var(--border-subtle);
            border-radius: 18px;
            overflow: hidden;
            box-shadow: 0 4px 18px rgba(31, 27, 24, 0.04);
            cursor: pointer;
            transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease;
            position: relative;
        }
        .trip-card-item:active {
            transform: scale(0.985);
            border-color: var(--gold);
        }
        .trip-card-cover-box {
            position: relative;
            height: 140px;
            width: 100%;
            overflow: hidden;
            background: #2A2421;
        }
        .trip-card-cover-box img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            filter: brightness(0.85);
            transition: transform 0.3s ease;
        }
        .trip-card-body {
            padding: 16px;
        }

        /* Badges & Status */
        .badge-status {
            font-size: 0.65rem;
            font-weight: 800;
            letter-spacing: 0.06em;
            text-transform: uppercase;
            padding: 4px 9px;
            border-radius: 20px;
            display: inline-flex;
            align-items: center;
            gap: 5px;
        }
        .badge-status.active {
            background: #C9A84C;
            color: #0F1D2E;
            box-shadow: 0 2px 8px rgba(201, 168, 76, 0.4);
        }
        .badge-status.upcoming {
            background: rgba(15, 29, 46, 0.85);
            color: #FFF;
            border: 1px solid rgba(255, 255, 255, 0.25);
            backdrop-filter: blur(8px);
        }
        .weather-pill {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            background: rgba(255, 255, 255, 0.2);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.3);
            color: #FFF;
            font-size: 0.7rem;
            font-weight: 700;
            padding: 4px 10px;
            border-radius: 16px;
        }
        .weather-pill-light {
            background: var(--gold-light);
            border: 1px solid var(--gold-border);
            color: var(--gold-dark);
            padding: 4px 10px;
            border-radius: 14px;
            font-size: 0.72rem;
            font-weight: 700;
            display: inline-flex;
            align-items: center;
            gap: 5px;
        }

        /* Trip Detail Tabs Navigation */
        .detail-sub-nav {
            display: flex;
            gap: 8px;
            overflow-x: auto;
            padding: 12px 0 16px 0;
            scrollbar-width: none;
            -webkit-overflow-scrolling: touch;
        }
        .detail-sub-nav::-webkit-scrollbar { display: none; }
        .sub-pill {
            flex: 0 0 auto;
            background: #FFFFFF;
            border: 1px solid var(--border-subtle);
            padding: 7px 14px;
            border-radius: 20px;
            font-size: 0.74rem;
            font-weight: 700;
            color: var(--text-muted);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            transition: var(--transition);
        }
        .sub-pill.active {
            background: var(--gold);
            color: #FFFFFF;
            border-color: var(--gold);
            box-shadow: 0 2px 8px rgba(201, 168, 76, 0.3);
        }

        /* Smart Packing Engine UI */
        .packing-config-card {
            background: #FFFFFF;
            border: 1px solid var(--border-subtle);
            border-radius: 18px;
            padding: 18px;
            margin-bottom: 18px;
            box-shadow: 0 4px 14px rgba(31, 27, 24, 0.03);
        }
        .segmented-control {
            display: flex;
            background: #F3EFEA;
            padding: 4px;
            border-radius: 12px;
            margin-bottom: 14px;
            gap: 4px;
        }
        .segment-btn {
            flex: 1;
            padding: 8px 10px;
            border: none;
            background: transparent;
            font-size: 0.72rem;
            font-weight: 700;
            color: var(--text-muted);
            border-radius: 9px;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            transition: var(--transition);
        }
        .segment-btn.active {
            background: #FFFFFF;
            color: var(--text-main);
            box-shadow: 0 2px 6px rgba(0, 0, 0, 0.06);
        }

        .switch-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 0;
            border-top: 1px solid var(--border-subtle);
            font-size: 0.8rem;
            font-weight: 600;
        }
        .switch-toggle {
            position: relative;
            display: inline-block;
            width: 44px;
            height: 24px;
        }
        .switch-toggle input { opacity: 0; width: 0; height: 0; }
        .slider {
            position: absolute; cursor: pointer; inset: 0;
            background-color: #D1D5DB;
            transition: .25s;
            border-radius: 24px;
        }
        .slider:before {
            position: absolute; content: "";
            height: 18px; width: 18px;
            left: 3px; bottom: 3px;
            background-color: white;
            transition: .25s;
            border-radius: 50%;
        }
        input:checked + .slider { background-color: var(--gold); }
        input:checked + .slider:before { transform: translateX(20px); }

        .packing-category-title {
            font-size: 0.72rem;
            font-weight: 800;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: var(--gold-dark);
            margin: 18px 0 8px 2px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }

        /* Checklists */
        .check-item-ios {
            display: flex;
            align-items: flex-start;
            gap: 12px;
            border-bottom: 1px solid rgba(232, 226, 216, 0.6);
            padding: 12px 4px;
            cursor: pointer;
            transition: background 0.15s ease;
        }
        .checkbox-ios {
            width: 22px;
            height: 22px;
            border-radius: 50%;
            border: 1.8px solid #D5CCC0;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-top: 1px;
            flex-shrink: 0;
            transition: all 0.2s ease;
        }
        .check-item-ios.checked .checkbox-ios {
            background-color: var(--gold);
            border-color: var(--gold);
        }
        .checkbox-ios svg {
            width: 12px;
            height: 12px;
            stroke: #FFFFFF;
            stroke-width: 3.5;
            fill: none;
            display: none;
        }
        .check-item-ios.checked .checkbox-ios svg { display: block; }
        .check-item-ios.checked .check-text-title {
            color: var(--text-muted);
            text-decoration: line-through;
        }
        .check-text-title {
            font-size: 0.85rem;
            font-weight: 600;
            color: var(--text-main);
            line-height: 1.3;
        }
        .check-text-desc {
            font-size: 0.74rem;
            color: var(--text-muted);
            margin-top: 2px;
        }

        /* Activity Toggles (Golf & Playa) */
        .activity-toggles-bar {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            margin-bottom: 12px;
        }
        @media (max-width: 540px) {
            .activity-toggles-bar {
                grid-template-columns: 1fr;
            }
        }
        .activity-toggle-card {
            background: #FFFFFF;
            border: 1.5px solid var(--border-subtle);
            border-radius: 14px;
            padding: 10px 14px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            transition: all 0.2s ease;
            box-shadow: 0 2px 6px rgba(0,0,0,0.02);
        }
        .activity-toggle-card.active {
            border-color: #10B981;
            background: #F0FDF4;
        }
        .toggle-info {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .toggle-icon {
            font-size: 1.4rem;
            line-height: 1;
        }
        .toggle-label {
            font-size: 0.82rem;
            font-weight: 700;
            color: var(--text-main);
        }
        .toggle-desc {
            font-size: 0.68rem;
            color: var(--text-muted);
            line-height: 1.2;
            margin-top: 2px;
        }
        .ios-switch {
            position: relative;
            display: inline-block;
            width: 44px;
            height: 26px;
            flex-shrink: 0;
            margin-left: 8px;
        }
        .ios-switch input {
            opacity: 0;
            width: 0;
            height: 0;
        }
        .ios-switch .slider {
            position: absolute;
            cursor: pointer;
            top: 0; left: 0; right: 0; bottom: 0;
            background-color: #CBD5E1;
            transition: .25s;
            border-radius: 26px;
        }
        .ios-switch .slider:before {
            position: absolute;
            content: "";
            height: 20px;
            width: 20px;
            left: 3px;
            bottom: 3px;
            background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.25);
            transition: .25s;
            border-radius: 50%;
        }
        .ios-switch input:checked + .slider {
            background-color: #10B981;
        }
        .ios-switch input:checked + .slider:before {
            transform: translateX(18px);
        }

        /* Traveler Segmented Selector & Progress */
        .traveler-selector {
            display: flex;
            background: #EFECE6;
            border-radius: 14px;
            padding: 4px;
            gap: 4px;
            margin-bottom: 12px;
        }
        .traveler-selector-btn {
            flex: 1;
            padding: 10px 4px;
            font-size: 0.76rem;
            font-weight: 700;
            border: none;
            border-radius: 10px;
            background: transparent;
            color: var(--text-muted);
            cursor: pointer;
            transition: all 0.2s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 5px;
        }
        .traveler-selector-btn.active {
            background: #FFFFFF;
            color: var(--text-main);
            box-shadow: 0 2px 6px rgba(0,0,0,0.06);
        }
        .badge-count {
            font-size: 0.66rem;
            background: rgba(0,0,0,0.06);
            padding: 2px 6px;
            border-radius: 10px;
            font-weight: 800;
        }
        .traveler-selector-btn.active .badge-count {
            background: var(--gold-light);
            color: var(--gold-dark);
        }
        .packing-progress-wrapper {
            background: #FFFFFF;
            border: 1px solid var(--border-subtle);
            border-radius: 14px;
            padding: 12px 14px;
            margin-bottom: 14px;
        }
        .packing-progress-bar-bg {
            height: 6px;
            background: #EFECE6;
            border-radius: 6px;
            overflow: hidden;
            margin-top: 8px;
        }
        .packing-progress-bar-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--gold), #10B981);
            border-radius: 6px;
            transition: width 0.3s ease;
        }
        .weather-advisory-box {
            background: #F0FDF4;
            border: 1px solid #BBF7D0;
            border-radius: 14px;
            padding: 12px 14px;
            margin-bottom: 14px;
            font-size: 0.78rem;
            color: #166534;
            line-height: 1.45;
        }

        /* Flight & Hotel Cards */
        .flight-card, .hotel-card, .day-card {
            background: #FFFFFF;
            border: 1px solid var(--border-subtle);
            border-radius: 16px;
            padding: 16px;
            margin-bottom: 14px;
            box-shadow: 0 2px 10px rgba(31, 27, 24, 0.025);
        }
        .card-action-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 6px;
            width: 100%;
            background: var(--gold-light);
            border: 1px solid var(--gold-border);
            color: var(--gold-dark);
            padding: 10px 14px;
            border-radius: 12px;
            font-size: 0.78rem;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            cursor: pointer;
            margin-top: 10px;
            text-decoration: none;
            transition: var(--transition);
        }
        .card-action-btn:active {
            transform: scale(0.98);
            background: rgba(201, 168, 76, 0.22);
        }

        /* Day Timeline items */
        .day-bullet {
            font-size: 0.82rem;
            color: var(--text-main);
            margin-bottom: 6px;
            line-height: 1.4;
            display: flex;
            align-items: flex-start;
            gap: 8px;
        }
        .day-bullet::before {
            content: '•';
            color: var(--gold);
            font-size: 1.2rem;
            line-height: 1;
        }
        .chips-container {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            margin-top: 10px;
        }
        .food-chip {
            background: #FFF7ED;
            border: 1px solid #FED7AA;
            border-radius: 20px;
            padding: 5px 12px;
            font-size: 0.74rem;
            font-weight: 600;
            color: #9A3412;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 6px;
            box-shadow: 0 1px 3px rgba(154, 52, 18, 0.06);
            transition: var(--transition);
        }
        .food-chip:active {
            transform: scale(0.96);
            background: #FFEDD5;
        }

        /* Fixed Bottom Dock */
        .bottom-dock {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            min-height: 64px;
            height: calc(64px + env(safe-area-inset-bottom, 0px));
            background-color: rgba(250, 247, 242, 0.96);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border-top: 1px solid var(--border-subtle);
            display: flex;
            justify-content: space-around;
            align-items: flex-start;
            padding-top: 6px;
            padding-left: calc(10px + env(safe-area-inset-left, 0px));
            padding-right: calc(10px + env(safe-area-inset-right, 0px));
            padding-bottom: calc(6px + env(safe-area-inset-bottom, 0px));
            user-select: none;
            -webkit-user-select: none;
            z-index: 200;
        }
        @media (min-width: 720px) {
            .bottom-dock {
                max-width: 720px;
                left: 50%;
                transform: translateX(-50%);
                border-radius: 20px 20px 0 0;
            }
        }
        .dock-btn {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            background: none;
            border: none;
            color: var(--text-muted);
            cursor: pointer;
            font-size: 0.62rem;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.03em;
            gap: 4px;
            padding: 6px 14px;
            transition: var(--transition);
        }
        .dock-btn svg {
            width: 21px;
            height: 21px;
            stroke: currentColor;
            stroke-width: 2.1;
            fill: none;
        }
        .dock-btn.active { color: var(--gold-dark); }
        .dock-btn.active svg { stroke: var(--gold-dark); }

        /* Toast */
        .toast {
            position: fixed;
            bottom: 85px;
            left: 50%;
            transform: translateX(-50%) translateY(30px);
            background-color: rgba(31, 27, 24, 0.94);
            color: #FFFFFF;
            padding: 9px 20px;
            border-radius: 22px;
            font-size: 0.78rem;
            font-weight: 600;
            z-index: 400;
            opacity: 0;
            pointer-events: none;
            transition: all 0.25s ease;
            box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
        }
        .toast.show {
            opacity: 1;
            transform: translateX(-50%) translateY(0);
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(4px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .print-checklist-btn {
            width: 100%;
            background: linear-gradient(135deg, #0F1D2E 0%, #1E293B 100%);
            color: #FFFFFF;
            border: 1px solid #0F1D2E;
            border-radius: 14px;
            padding: 12px 18px;
            font-size: 0.82rem;
            font-weight: 700;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            gap: 10px;
            margin-bottom: 14px;
            box-shadow: 0 4px 14px rgba(15, 29, 46, 0.15);
            transition: var(--transition);
        }
        .print-checklist-btn:active {
            transform: scale(0.98);
            background: #0F1D2E;
        }

        #printable-packing-area {
            display: none;
        }

        @media print {
            @page {
                size: letter portrait;
                margin: 10mm 12mm;
            }

            body::after { display: none !important; }

            /* When printing only checklists */
            body.print-only-checklists .app-shell,
            body.print-only-checklists header,
            body.print-only-checklists .bottom-dock,
            body.print-only-checklists .screen,
            body.print-only-checklists .breadcrumb-bar,
            body.print-only-checklists .toast {
                display: none !important;
            }

            body.print-only-checklists #printable-packing-area {
                display: block !important;
                position: absolute !important;
                left: 0 !important;
                top: 0 !important;
                width: 100% !important;
                background: #FFFFFF !important;
                color: #111827 !important;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
                padding: 0 !important;
                margin: 0 !important;
            }

            .print-document {
                width: 100%;
            }

            .print-main-header {
                border-bottom: 2px solid #0F1D2E;
                padding-bottom: 8px;
                margin-bottom: 12px;
            }

            .print-logo-row {
                display: flex;
                justify-content: space-between;
                align-items: flex-end;
                margin-bottom: 6px;
            }

            .print-trip-summary {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 4px 16px;
                font-size: 8.5pt;
                color: #374151;
                background: #F9FAFB;
                padding: 8px 12px;
                border-radius: 6px;
                border: 1px solid #E5E7EB;
            }

            .print-traveler-section {
                margin-bottom: 16px;
                break-inside: avoid;
            }

            .print-traveler-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                background: #F3F4F6;
                padding: 6px 12px;
                border-left: 4px solid #C9A84C;
                border-radius: 4px;
                margin-bottom: 8px;
                margin-top: 6px;
            }

            .print-category-grid {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 8px 12px;
            }

            .print-category-card {
                border: 1px solid #E5E7EB;
                border-radius: 6px;
                padding: 7px 9px;
                break-inside: avoid;
                page-break-inside: avoid;
                background: #FFFFFF;
            }

            .print-category-title {
                font-size: 8.5pt;
                font-weight: 700;
                color: #1F2937;
                border-bottom: 1px solid #E5E7EB;
                padding-bottom: 3px;
                margin-bottom: 5px;
                display: flex;
                justify-content: space-between;
            }

            .print-items-list {
                display: flex;
                flex-direction: column;
                gap: 3px;
            }

            .print-item-row {
                display: flex;
                align-items: flex-start;
                gap: 6px;
                font-size: 8pt;
                line-height: 1.25;
            }

            .print-checkbox {
                display: inline-block;
                width: 12px;
                height: 12px;
                min-width: 12px;
                border: 1.2px solid #374151;
                border-radius: 2px;
                text-align: center;
                line-height: 10px;
                font-size: 9px;
                font-weight: 900;
                margin-top: 1px;
            }

            .print-checkbox.checked {
                background: #F3F4F6;
                color: #059669;
            }

            .print-item-label {
                color: #111827;
                flex: 1;
            }

            .print-item-label.checked-text {
                color: #374151;
            }

            .print-sub {
                display: block;
                font-size: 7pt;
                color: #6B7280;
            }

            .print-page-break {
                page-break-before: always;
                break-before: page;
            }

            /* Regular print fallback */
            body:not(.print-only-checklists) header,
            body:not(.print-only-checklists) .breadcrumb-bar,
            body:not(.print-only-checklists) .bottom-dock,
            body:not(.print-only-checklists) .header-actions,
            body:not(.print-only-checklists) .toast,
            body:not(.print-only-checklists) button {
                display: none !important;
            }
            body:not(.print-only-checklists) .screen {
                display: block !important;
                position: static !important;
                opacity: 1 !important;
                transform: none !important;
                padding: 10px 0 !important;
                page-break-after: always;
            }
        }
        @keyframes spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
        }
        .spinning {
            animation: spin 0.8s linear infinite !important;
            display: inline-block !important;
        }
    </style>
</head>
<body>
    <div class="app-shell">
        <header>
            <div class="logo-text">
                <span style="color: var(--gold-dark);">🧭</span> Travel Planner
            </div>
            <div class="header-actions">
                <button class="header-btn" id="sync-btn" onclick="syncAndRefresh()"><span id="sync-icon" style="font-size: 0.9rem; display: inline-block;">🔄</span> <span id="sync-text">Sincronizar</span></button>
                <button class="header-btn" onclick="handleHeaderPrint()"><span style="font-size: 0.9rem;">🖨️</span> Imprimir</button>
            </div>
        </header>

        <!-- Top Breadcrumb Navigation -->
        <div id="breadcrumb-bar" class="breadcrumb-bar">
            <button class="back-btn" onclick="backToDashboard()">
                <span style="font-size: 1.1rem; line-height: 1;">‹</span> Dashboard
            </button>
            <div id="breadcrumb-title" class="breadcrumb-title">Detalles del Viaje</div>
        </div>

        <div id="toast" class="toast">Guardado</div>

        <main class="main-content">
            <!-- Screen 1: Executive Master Dashboard -->
            <section id="screen-dashboard" class="screen active">
                <div id="dashboard-hero-container"></div>
                
                <div class="dashboard-section-title">
                    <span>Próximos Viajes Programados</span>
                    <span id="upcoming-count-badge" style="background: rgba(31,27,24,0.06); padding: 2px 8px; border-radius: 10px;">0</span>
                </div>
                <div id="dashboard-upcoming-container" class="trip-card-grid"></div>
            </section>

            <!-- Screen 2: Single Trip Detail View -->
            <section id="screen-trip-detail" class="screen">
                <div id="trip-detail-header"></div>

                <!-- Sub Navigation Pills for active trip -->
                <nav class="detail-sub-nav">
                    <button class="sub-pill active" id="subpill-timeline" onclick="switchDetailTab('timeline')">📅 Agenda</button>
                    <button class="sub-pill" id="subpill-flights" onclick="switchDetailTab('flights')">✈️🚄 Vuelos, Trenes & Tránsito</button>
                    <button class="sub-pill" id="subpill-lodgings" onclick="switchDetailTab('lodgings')">🏨 Hospedaje</button>
                    <button class="sub-pill" id="subpill-packing" onclick="switchDetailTab('packing')">🎒 Empaque Inteligente</button>
                </nav>

                <div id="detail-tab-timeline" class="detail-tab-content"></div>
                <div id="detail-tab-flights" class="detail-tab-content" style="display: none;"></div>
                <div id="detail-tab-lodgings" class="detail-tab-content" style="display: none;"></div>
                <div id="detail-tab-packing" class="detail-tab-content" style="display: none;"></div>
            </section>

            <!-- Screen 3: Global Smart Packing Hub -->
            <section id="screen-packing" class="screen">
                <div style="margin-bottom: 18px;">
                    <h1 style="font-family: 'Cormorant Garamond', serif; font-size: 2.2rem; font-weight: 700;">Motor de Empaque Inteligente</h1>
                    <p style="font-size: 0.8rem; color: var(--text-muted); text-transform: uppercase; font-weight: 700; letter-spacing: 0.05em;">Cálculo dinámico por clima, días y capacidad de equipaje</p>
                </div>
                <div id="global-packing-content"></div>
            </section>

            <!-- Screen 4: Traveler Profile & Emergency Hotlines -->
            <section id="screen-docs" class="screen">
                <div style="margin-bottom: 18px;">
                    <h1 style="font-family: 'Cormorant Garamond', serif; font-size: 2.2rem; font-weight: 700;">Perfil VIP & Hotlines</h1>
                    <p style="font-size: 0.8rem; color: var(--text-muted); text-transform: uppercase; font-weight: 700; letter-spacing: 0.05em;">Programas de fidelidad y conserjería 24 horas</p>
                </div>
                <div id="profile-container"></div>
                <div class="dashboard-section-title" style="margin-top: 24px;">🚨 Directorio de Asistencia Directa</div>
                <div id="hotlines-container"></div>
            </section>
        </main>

        <!-- Fixed Bottom Dock -->
        <nav class="bottom-dock">
            <button class="dock-btn active" id="dock-btn-dashboard" onclick="switchMainTab('dashboard')">
                <svg viewBox="0 0 24 24"><polygon points="3 9 12 2 21 9 21 20 12 20 12 14 3 14"/></svg>
                Dashboard
            </button>
            <button class="dock-btn" id="dock-btn-active-trip" onclick="goToActiveTrip()">
                <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                Próximo
            </button>
            <button class="dock-btn" id="dock-btn-packing" onclick="switchMainTab('packing')">
                <svg viewBox="0 0 24 24"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
                Empaque
            </button>
            <button class="dock-btn" id="dock-btn-docs" onclick="switchMainTab('docs')">
                <svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                Perfil
            </button>
        </nav>
    </div>

    <script>
HTML_HEADER

embedded_js = "const EMBEDDED_STATE = " + state_data.to_json + ";\n"
html_content << embedded_js

html_content << <<-'HTML_FOOTER'
        let appData = null;
        let currentScreen = 'dashboard';
        let currentTripId = null;
        let currentDetailTab = 'timeline';

        // Register Service Worker
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('./sw.js').then((reg) => {
                    reg.update();
                }).catch(err => console.warn('SW:', err));
            });
        }

        // Init App Data
        window.addEventListener('DOMContentLoaded', () => {
            // Check if there is a pending toast after file:// reload
            const pendingMsg = sessionStorage.getItem('sync_toast_msg');
            if (pendingMsg) {
                sessionStorage.removeItem('sync_toast_msg');
                setTimeout(() => {
                    showToast(pendingMsg);
                }, 350);
            }

            const cached = localStorage.getItem('travel_planner_v54_state');
            let useEmbedded = true;
            if (cached) {
                try {
                    const parsed = JSON.parse(cached);
                    // Compare lastUpdated timestamps
                    if (parsed && parsed.lastUpdated && EMBEDDED_STATE.lastUpdated) {
                        const parsedTime = new Date(parsed.lastUpdated.replace(/-/g, '/')).getTime();
                        const embeddedTime = new Date(EMBEDDED_STATE.lastUpdated.replace(/-/g, '/')).getTime();
                        // If embedded state is newer, or if cached has fewer trips, use embedded
                        if (parsedTime >= embeddedTime && (parsed.trips || []).length >= (EMBEDDED_STATE.trips || []).length) {
                            appData = parsed;
                            useEmbedded = false;
                        }
                    }
                } catch(e) {}
            }

            if (useEmbedded) {
                appData = JSON.parse(JSON.stringify(EMBEDDED_STATE));
                saveState();
            }

            // Ensure activitiesConfig exists on all trips
            (appData.trips || []).forEach(t => {
                if (!t.activitiesConfig) t.activitiesConfig = { golf: true, beach: true };
            });

            renderAll();
        });

        function saveState() {
            if (!appData) return;
            localStorage.setItem('travel_planner_v54_state', JSON.stringify(appData));
        }

        async function syncAndRefresh() {
            const btn = document.getElementById('sync-btn');
            const icon = document.getElementById('sync-icon');
            const text = document.getElementById('sync-text');
            if (icon) icon.classList.add('spinning');
            if (text) text.textContent = 'Sincronizando...';

            let synced = false;
            let syncSource = '';

            // Clean up any legacy cache keys
            localStorage.removeItem('travel_planner_v52_state');
            localStorage.removeItem('travel_planner_v51_state');
            localStorage.removeItem('travel_planner_v5_state');

            // 1. Try local sync API (if local server is running)
            try {
                const apiEndpoints = ['/api/sync', 'http://localhost:8080/api/sync'];
                for (const ep of apiEndpoints) {
                    try {
                        const controller = new AbortController();
                        const timer = setTimeout(() => controller.abort(), 3500);
                        const res = await fetch(ep, {
                            method: 'GET',
                            signal: controller.signal,
                            cache: 'no-store',
                            headers: { 'Accept': 'application/json' }
                        });
                        clearTimeout(timer);
                        if (res.ok) {
                            const data = await res.json();
                            if (data && data.trips && data.trips.length > 0) {
                                appData = data;
                                saveState();
                                syncSource = 'OneDrive en Vivo';
                                synced = true;
                                break;
                            }
                        }
                    } catch (err) {}
                }
            } catch (e) {}

            // 2. Try fetching static state.json directly
            if (!synced) {
                try {
                    const controller = new AbortController();
                    const timer = setTimeout(() => controller.abort(), 2000);
                    const res = await fetch('./state.json?_t=' + Date.now(), {
                        signal: controller.signal,
                        cache: 'no-store'
                    });
                    clearTimeout(timer);
                    if (res.ok) {
                        const data = await res.json();
                        if (data && data.trips && data.trips.length > 0) {
                            appData = data;
                            saveState();
                            syncSource = 'state.json';
                            synced = true;
                        }
                    }
                } catch (e) {}
            }

            // 3. Fallback: if running as local file (file:///) or offline
            if (!synced) {
                if (window.location.protocol === 'file:') {
                    localStorage.removeItem('travel_planner_v52_state');
                    sessionStorage.setItem('sync_toast_msg', '✅ Aplicación actualizada con la versión más reciente del disco');
                    window.location.reload();
                    return;
                } else {
                    appData = JSON.parse(JSON.stringify(EMBEDDED_STATE));
                    saveState();
                    syncSource = 'Datos Maestros';
                    synced = true;
                }
            }

            // Clear Service Worker Caches
            if ('caches' in window) {
                try {
                    const keys = await caches.keys();
                    await Promise.all(keys.map(k => caches.delete(k)));
                } catch(e) {}
            }

            renderAll();

            if (icon) icon.classList.remove('spinning');
            if (text) text.textContent = 'Sincronizar';

            const tripCount = (appData.trips || []).length;
            const updatedTime = appData.lastUpdated ? appData.lastUpdated.split(' ')[1] || '' : '';
            showToast(`✅ ${syncSource}: ${tripCount} viajes sincronizados (${updatedTime})`);
        }

        function showToast(msg) {
            const toast = document.getElementById('toast');
            if (!toast) return;
            toast.textContent = msg;
            toast.classList.add('show');
            setTimeout(() => toast.classList.remove('show'), 2200);
        }

        function renderAll() {
            renderDashboard();
            renderGlobalPacking();
            renderDocs();
        }

        // Screen & Tab Routing
        function switchMainTab(tabId) {
            currentScreen = tabId;
            document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
            document.querySelectorAll('.dock-btn').forEach(b => b.classList.remove('active'));

            const targetScreen = document.getElementById('screen-' + tabId);
            if (targetScreen) targetScreen.classList.add('active');

            const targetDockBtn = document.getElementById('dock-btn-' + tabId);
            if (targetDockBtn) targetDockBtn.classList.add('active');

            const breadcrumbBar = document.getElementById('breadcrumb-bar');
            if (breadcrumbBar) breadcrumbBar.classList.remove('active');

            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        function goToActiveTrip() {
            const activeTrip = (appData.trips || []).find(t => t.status === 'active') || (appData.trips || [])[0];
            if (activeTrip) {
                openTripDetail(activeTrip.id);
            } else {
                switchMainTab('dashboard');
            }
        }

        function openTripDetail(tripId, subTab = 'timeline') {
            currentTripId = tripId;
            currentScreen = 'trip-detail';
            const trip = (appData.trips || []).find(t => t.id === tripId);
            if (!trip) return;

            document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
            const detailScreen = document.getElementById('screen-trip-detail');
            if (detailScreen) detailScreen.classList.add('active');

            // Show Breadcrumb
            const breadcrumbBar = document.getElementById('breadcrumb-bar');
            const breadcrumbTitle = document.getElementById('breadcrumb-title');
            if (breadcrumbBar && breadcrumbTitle) {
                breadcrumbBar.classList.add('active');
                breadcrumbTitle.textContent = trip.title;
            }

            renderTripDetailContent(trip);
            switchDetailTab(subTab);
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        function backToDashboard() {
            switchMainTab('dashboard');
        }

        function switchDetailTab(tabId) {
            currentDetailTab = tabId;
            document.querySelectorAll('.sub-pill').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.detail-tab-content').forEach(c => c.style.display = 'none');

            const targetPill = document.getElementById('subpill-' + tabId);
            if (targetPill) targetPill.classList.add('active');

            const targetTab = document.getElementById('detail-tab-' + tabId);
            if (targetTab) targetTab.style.display = 'block';
        }

        // Dashboard Rendering (TripIt Pro + Timepage Hybrid)
        function renderDashboard() {
            const heroContainer = document.getElementById('dashboard-hero-container');
            const upcomingContainer = document.getElementById('dashboard-upcoming-container');
            const upcomingCountEl = document.getElementById('upcoming-count-badge');

            if (!heroContainer || !upcomingContainer) return;

            const trips = appData.trips || [];
            const activeTrip = trips.find(t => t.status === 'active') || trips[0];
            const upcomingTrips = trips.filter(t => t.id !== (activeTrip ? activeTrip.id : ''));

            if (upcomingCountEl) upcomingCountEl.textContent = upcomingTrips.length;

            // 1. Hero Card: Active / Immediate Next Trip
            if (activeTrip) {
                const depDate = new Date(activeTrip.startDate + 'T00:00:00');
                const now = new Date();
                const diffDays = Math.ceil((depDate - now) / (1000 * 60 * 60 * 24));
                const countdownStr = diffDays > 0 ? `✈️ Faltan ${diffDays} días` : (diffDays === 0 ? '✈️ ¡Salida Hoy!' : '🌟 En Progreso');

                heroContainer.innerHTML = `
                    <div class="trip-card-hero" onclick="openTripDetail('${activeTrip.id}')">
                        <img src="${activeTrip.coverImage}" alt="${activeTrip.title}" onerror="this.style.display='none'">
                        <div class="trip-card-hero-overlay">
                            <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                                <span class="badge-status active">PRÓXIMA SALIDA INMEDIATA</span>
                                <div class="weather-pill">
                                    <span>${activeTrip.climate?.icon || '🌤️'}</span>
                                    <span>${activeTrip.climate?.tempLowF || 64}°F / ${activeTrip.climate?.tempHighF || 84}°F</span>
                                </div>
                            </div>
                            <div>
                                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 4px;">
                                    <span style="font-size: 1.2rem;">${activeTrip.flag || '📍'}</span>
                                    <span style="color: #E7C975; font-size: 0.76rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em;">${activeTrip.datesDisplay} · ${activeTrip.durationDays} días</span>
                                </div>
                                <h2 style="font-family: 'Cormorant Garamond', serif; font-size: 2.3rem; font-weight: 700; line-height: 1.05; text-shadow: 0 2px 10px rgba(0,0,0,0.6);">${activeTrip.title}</h2>
                                <p style="font-size: 0.82rem; color: rgba(255,255,255,0.9); margin-top: 4px;">${activeTrip.subtitle || activeTrip.destination}</p>
                                
                                <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 14px; padding-top: 12px; border-top: 1px solid rgba(255,255,255,0.2);">
                                    <span style="background: rgba(255,255,255,0.2); backdrop-filter: blur(8px); padding: 4px 12px; border-radius: 20px; font-size: 0.72rem; font-weight: 700;">${countdownStr}</span>
                                    <span style="font-size: 0.76rem; color: #E7C975; font-weight: 700;">Ver Itinerario Completo ›</span>
                                </div>
                            </div>
                        </div>
                    </div>
                `;
            } else {
                heroContainer.innerHTML = '';
            }

            // 2. Upcoming Trips Grid
            upcomingContainer.innerHTML = '';
            upcomingTrips.forEach(t => {
                const card = document.createElement('div');
                card.className = 'trip-card-item';
                card.onclick = () => openTripDetail(t.id);

                const climateHtml = t.climate ? `
                    <span class="weather-pill-light">
                        <span>${t.climate.icon || '🌤️'}</span> ${t.climate.tempLowF || 64}°F - ${t.climate.tempHighF || 84}°F
                    </span>
                ` : '';

                card.innerHTML = `
                    <div class="trip-card-cover-box">
                        <img src="${t.coverImage}" alt="${t.title}" onerror="this.parentElement.style.display='none'">
                        <div style="position: absolute; top: 12px; left: 12px;">
                            <span class="badge-status upcoming">PROGRAMADO</span>
                        </div>
                        <div style="position: absolute; top: 12px; right: 12px;">
                            <span style="background: rgba(0,0,0,0.6); backdrop-filter: blur(8px); color: #FFF; font-size: 0.68rem; font-weight: 700; padding: 4px 10px; border-radius: 20px;">${t.durationDays} Días</span>
                        </div>
                    </div>
                    <div class="trip-card-body">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                            <span style="font-size: 0.74rem; font-weight: 700; color: var(--gold-dark);">${t.datesDisplay}</span>
                            ${climateHtml}
                        </div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.45rem; font-weight: 700; line-height: 1.15; color: var(--text-main); margin-bottom: 4px;">${t.title}</div>
                        <div style="font-size: 0.78rem; color: var(--text-muted); margin-bottom: 12px;">📍 ${t.destination}</div>
                        <div style="display: flex; justify-content: space-between; align-items: center; border-top: 1px dashed var(--border-subtle); padding-top: 10px; font-size: 0.74rem; font-weight: 700; color: var(--gold-dark);">
                            <span>Logística & Reservas</span>
                            <span>Explorar ›</span>
                        </div>
                    </div>
                `;
                upcomingContainer.appendChild(card);
            });
        }

        // Single Trip Detail Content Renderer
        function renderTripDetailContent(trip) {
            const headerBox = document.getElementById('trip-detail-header');
            if (headerBox) {
                headerBox.innerHTML = `
                    <div style="position: relative; border-radius: 20px; overflow: hidden; height: 180px; margin-bottom: 14px; background: #0F1D2E;">
                        <img src="${trip.coverImage}" alt="${trip.title}" style="width: 100%; height: 100%; object-fit: cover; filter: brightness(0.65);">
                        <div style="position: absolute; inset: 0; padding: 18px; display: flex; flex-direction: column; justify-content: flex-end; color: #FFF;">
                            <div style="font-size: 0.72rem; font-weight: 700; color: #E7C975; text-transform: uppercase;">${trip.datesDisplay} · ${trip.durationDays} Días</div>
                            <h1 style="font-family: 'Cormorant Garamond', serif; font-size: 2rem; font-weight: 700; line-height: 1.1;">${trip.title}</h1>
                            <div style="font-size: 0.78rem; opacity: 0.9;">📍 ${trip.destination}</div>
                        </div>
                    </div>
                `;
            }

            // Tab 1: Timeline
            const tabTimeline = document.getElementById('detail-tab-timeline');
            if (tabTimeline) {
                tabTimeline.innerHTML = '';
                (trip.timeline || []).forEach(day => {
                    const card = document.createElement('div');
                    card.className = 'day-card';
                    let bullets = (day.items || []).map(b => `<div class="day-bullet">${b}</div>`).join('');
                    let diningChips = (day.lunchOptions || []).map(f => {
                        const q = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(f.query || f.name)}`;
                        return `<a href="${q}" target="_blank" class="food-chip">🍽️ ${f.name}</a>`;
                    }).join('');

                    card.innerHTML = `
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                            <span style="font-size: 0.7rem; font-weight: 800; color: var(--gold-dark); text-transform: uppercase; letter-spacing: 0.05em;">${day.date}</span>
                            ${day.dest ? `<span style="font-size: 0.68rem; background: var(--gold-light); color: var(--gold-dark); padding: 2px 8px; border-radius: 10px; font-weight: 700;">${day.dest}</span>` : ''}
                        </div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.35rem; font-weight: 700; color: var(--text-main); margin-bottom: 8px;">${day.title}</div>
                        ${bullets}
                        ${diningChips ? `<div class="chips-container">${diningChips}</div>` : ''}
                    `;
                    tabTimeline.appendChild(card);
                });
            }

            // Tab 2: Flights & Transit
            const tabFlights = document.getElementById('detail-tab-flights');
            if (tabFlights) {
                tabFlights.innerHTML = '';

                // Transfers
                (trip.transfers || []).forEach(tr => {
                    const trCard = document.createElement('div');
                    trCard.className = 'flight-card';
                    trCard.style.borderLeft = '4px solid #10B981';
                    trCard.innerHTML = `
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                            <span style="font-size: 0.68rem; font-weight: 800; background: #ECFDF5; color: #059669; padding: 2px 8px; border-radius: 6px;">TRASLADO PRIVADO</span>
                            <span style="font-size: 0.74rem; font-weight: 700; color: #059669;">Ref: ${tr.ref}</span>
                        </div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.3rem; font-weight: 700;">${tr.company} · ${tr.type}</div>
                        <div style="font-size: 0.78rem; color: var(--text-muted); margin: 4px 0;">📍 <strong>Recogida:</strong> ${tr.pickup} (${tr.pickupTime})</div>
                        <div style="font-size: 0.78rem; color: var(--text-muted); margin-bottom: 8px;">🏁 <strong>Destino:</strong> ${tr.destination} (${tr.duration})</div>
                        <div style="font-size: 0.78rem; background: #FAF9F6; padding: 6px 10px; border-radius: 8px; margin-bottom: 10px;">💶 <strong>Tarifa:</strong> ${tr.price} (${tr.payment})</div>
                        <a href="tel:${tr.supportPhone.replace(/[^0-9+]/g, '')}" class="card-action-btn"><span style="font-size: 1rem;">📞</span> Llamar Asistencia 24h (${tr.supportPhone})</a>
                    `;
                    tabFlights.appendChild(trCard);
                });

                // Trains (Renfe AVE / Alta Velocidad)
                (trip.trains || []).forEach(train => {
                    const tCard = document.createElement('div');
                    tCard.className = 'flight-card';
                    tCard.style.borderLeft = '4px solid #7C3AED';
                    tCard.innerHTML = `
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                            <span style="font-size: 0.68rem; font-weight: 800; background: #EDE9FE; color: #6D28D9; padding: 2px 8px; border-radius: 6px;">🚄 ${train.operator} · ${train.trainType || 'ALTA VELOCIDAD'}</span>
                            <span style="font-size: 0.74rem; font-weight: 800; color: #6D28D9;">Loc: ${train.pnr}</span>
                        </div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.3rem; font-weight: 700; color: var(--text-main); margin-bottom: 6px;">${train.trainNumber} · ${train.route}</div>
                        <div style="background: #FAF9F6; border: 1px solid var(--border-subtle); border-radius: 10px; padding: 12px; margin-bottom: 8px;">
                            <div style="display: flex; justify-content: space-between; align-items: center;">
                                <div>
                                    <div style="font-size: 1.25rem; font-weight: 800; color: var(--text-main);">${train.from}</div>
                                    <div style="font-size: 0.72rem; color: var(--text-muted);">${train.fromStation}</div>
                                    <div style="font-size: 0.85rem; font-weight: 700; color: var(--gold-dark); margin-top: 2px;">${train.depTime}</div>
                                </div>
                                <div style="text-align: center; color: var(--text-muted); font-size: 0.72rem; padding: 0 8px;">
                                    <div style="font-weight: 700; color: #6D28D9;">⏱️ ${train.duration}</div>
                                    <div style="letter-spacing: 2px; color: var(--gold-dark);">────────➔</div>
                                    <div style="font-size: 0.68rem;">${train.class}</div>
                                </div>
                                <div style="text-align: right;">
                                    <div style="font-size: 1.25rem; font-weight: 800; color: var(--text-main);">${train.to}</div>
                                    <div style="font-size: 0.72rem; color: var(--text-muted);">${train.toStation}</div>
                                    <div style="font-size: 0.85rem; font-weight: 700; color: var(--gold-dark); margin-top: 2px;">${train.arrTime}</div>
                                </div>
                            </div>
                        </div>
                        <div style="font-size: 0.78rem; color: var(--text-muted); margin-bottom: 4px;">💺 <strong>Asientos:</strong> ${train.seats}</div>
                        ${train.combinadoCercanias ? `<div style="font-size: 0.74rem; background: #F3F4F6; padding: 4px 8px; border-radius: 6px; margin-bottom: 6px;">🎟️ <strong>CombinadoCercanías:</strong> ${train.combinadoCercanias}</div>` : ''}
                        <div style="font-size: 0.76rem; background: var(--gold-light); padding: 6px 10px; border-radius: 8px; color: var(--text-main); margin-bottom: 6px;">✨ ${train.perks}</div>
                        <div style="font-size: 0.72rem; color: var(--text-muted);">💶 ${train.cost} · ${train.notes || ''}</div>
                    `;
                    tabFlights.appendChild(tCard);
                });

                // Flights
                (trip.flights || []).forEach(fl => {
                    const card = document.createElement('div');
                    card.className = 'flight-card';

                    let legsContent = '';
                    if (fl.legs) {
                        fl.legs.forEach(leg => {
                            if (leg.isLayover) {
                                legsContent += `
                                    <div style="background: var(--gold-light); border: 1px dashed var(--gold-border); border-radius: 10px; padding: 8px 12px; margin: 10px 0; font-size: 0.74rem;">
                                        <strong>⏳ ${leg.title}:</strong> ${leg.duration} · ${leg.details}
                                    </div>
                                `;
                            } else {
                                legsContent += `
                                    <div style="background: #FAF9F6; border: 1px solid var(--border-subtle); border-radius: 10px; padding: 12px; margin-bottom: 8px;">
                                        <div style="display: flex; justify-content: space-between; font-weight: 800; font-size: 0.9rem; color: #0078D2; margin-bottom: 6px;">
                                            <span>${leg.flightNum}</span>
                                            <span style="font-size: 0.74rem; color: var(--text-muted);">${leg.duration || ''}</span>
                                        </div>
                                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                                            <div>
                                                <div style="font-size: 1.3rem; font-weight: 800;">${leg.from}</div>
                                                <div style="font-size: 0.72rem; color: var(--text-muted);">${leg.fromCity || ''}</div>
                                                <div style="font-size: 0.76rem; font-weight: 700;">${leg.dep}</div>
                                            </div>
                                            <span style="font-size: 1.2rem; color: var(--gold);">➔</span>
                                            <div style="text-align: right;">
                                                <div style="font-size: 1.3rem; font-weight: 800;">${leg.to}</div>
                                                <div style="font-size: 0.72rem; color: var(--text-muted);">${leg.toCity || ''}</div>
                                                <div style="font-size: 0.76rem; font-weight: 700;">${leg.arr}</div>
                                            </div>
                                        </div>
                                        <div style="font-size: 0.72rem; color: var(--text-muted); border-top: 1px dashed var(--border-subtle); padding-top: 4px;">
                                            💺 Asientos: <strong>${leg.seats || 'Asignados'}</strong>
                                        </div>
                                    </div>
                                `;
                            }
                        });
                    } else {
                        legsContent = `
                            <div style="background: #FAF9F6; border: 1px solid var(--border-subtle); border-radius: 10px; padding: 12px; margin-bottom: 8px;">
                                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                                    <div style="font-size: 1.3rem; font-weight: 800;">${fl.from} ➔ ${fl.to}</div>
                                    <span style="font-size: 0.76rem; font-weight: 700; color: var(--gold-dark);">${fl.depTime ? fl.depTime + ' ➔ ' + fl.arrTime : fl.date}</span>
                                </div>
                                <div style="font-size: 0.76rem; color: var(--text-muted); margin-bottom: 4px;">${fl.fromName || ''} ➔ ${fl.toName || ''}</div>
                                ${fl.seats ? `<div style="font-size: 0.74rem; color: var(--text-main); margin-bottom: 4px;">💺 Asientos: <strong>${fl.seats}</strong></div>` : ''}
                                ${fl.perks ? `<div style="font-size: 0.72rem; color: var(--gold-dark); margin-bottom: 4px;">✨ ${fl.perks}</div>` : ''}
                                ${fl.notes ? `<div style="font-size: 0.72rem; color: var(--text-muted); border-top: 1px dashed var(--border-subtle); padding-top: 4px;">${fl.notes}</div>` : ''}
                            </div>
                        `;
                    }

                    card.innerHTML = `
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                            <span class="badge-status upcoming" style="background: rgba(0, 120, 210, 0.1); color: #0078D2; border: none;">✈️ ${fl.airline || fl.carrier}</span>
                            <span style="font-size: 0.74rem; font-weight: 800; color: var(--gold-dark);">${fl.pnr ? 'Loc: ' + fl.pnr : ''}</span>
                        </div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.25rem; font-weight: 700; margin-bottom: 8px;">${fl.segment || fl.flightNumber}</div>
                        ${legsContent}
                    `;
                    tabFlights.appendChild(card);
                });
            }

            // Tab 3: Lodgings
            const tabLodgings = document.getElementById('detail-tab-lodgings');
            if (tabLodgings) {
                tabLodgings.innerHTML = '';
                (trip.lodgings || []).forEach(lodg => {
                    const card = document.createElement('div');
                    card.className = 'hotel-card';
                    card.style.overflow = 'hidden';
                    const mapUrl = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(lodg.mapQuery || lodg.address)}`;
                    const imgHtml = lodg.image ? `
                        <div style="position: relative; height: 130px; width: calc(100% + 32px); margin: -16px -16px 12px -16px; overflow: hidden;">
                            <img src="${lodg.image}" alt="${lodg.name}" style="width: 100%; height: 100%; object-fit: cover;">
                            <div style="position: absolute; top: 10px; right: 10px; background: #C9A84C; color: #1F1B18; font-size: 0.65rem; font-weight: 800; padding: 3px 8px; border-radius: 20px;">CONFIRMADO</div>
                        </div>
                    ` : '';

                    card.innerHTML = `
                        ${imgHtml}
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
                            <span style="font-size: 0.72rem; font-weight: 800; color: var(--gold-dark);">🏨 ${lodg.city || trip.country}</span>
                            <span style="font-size: 0.72rem; font-weight: 700; color: var(--text-muted);">${lodg.conf}</span>
                        </div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.35rem; font-weight: 700; color: var(--text-main); margin-bottom: 4px;">${lodg.name}</div>
                        <div style="font-size: 0.78rem; color: var(--text-muted); margin-bottom: 6px;">📍 ${lodg.address}</div>
                        <div style="font-size: 0.74rem; background: var(--gold-light); padding: 5px 10px; border-radius: 8px; margin-bottom: 8px;">✨ ${lodg.cost}</div>
                        <div style="display: flex; gap: 8px;">
                            ${lodg.phone ? `<a href="tel:${lodg.phone.replace(/[^0-9+]/g, '')}" class="card-action-btn" style="flex: 1;"><span style="font-size: 0.9rem;">📞</span> Llamar</a>` : ''}
                            <a href="${mapUrl}" target="_blank" class="card-action-btn" style="flex: 1;"><span style="font-size: 0.9rem;">📍</span> Ver en Maps</a>
                        </div>
                    `;
                    tabLodgings.appendChild(card);
                });
            }

            // Tab 4: Smart Packing for this Trip
            const tabPacking = document.getElementById('detail-tab-packing');
            if (tabPacking) {
                tabPacking.innerHTML = '';
                renderSmartPackingComponent(tabPacking, trip);
            }
        }

        // Smart Packing Engine (Traveler Personalized & Activity Aware)
        let currentPackingTraveler = 'milton'; // 'milton' | 'aileen' | 'shared'

        const TRAVELER_PACKING_SPECS = {
            milton: {
                name: "Milton Cruz",
                icon: "👔",
                categories: [
                    {
                        name: "Checklist Viaje Original (Milton Cruz)",
                        icon: "📋",
                        badge: "Lista Original",
                        items: [
                            { id: "m_camisas_larga", text: "Camisas manga larga", sub: "De vestir y casual" },
                            { id: "m_camisas_obscure", text: "Camisas de traje obscure", sub: "Para noches de gala y cenas de autor" },
                            { id: "m_polos", text: "Polos", sub: "Uso diario y paseos" },
                            { id: "m_tshirt", text: "T-shirt", sub: "Capas base de algodón" },
                            { id: "m_mahones", text: "Mahones", sub: "Casual chic para desplazamientos" },
                            { id: "m_pantalones", text: "Pantalones", sub: "Ligeros de vestir / Chinos" },
                            { id: "m_bermuda", text: "Bermuda", sub: "Clima cálido en el sur (Sotogrande)" },
                            { id: "m_chaqueta", text: "Chaqueta", sub: "🍽️ Blazer estructurado para cenas y restaurantes" },
                            { id: "m_jacket_liviano", text: "Jacket Liviano", sub: "🌙 Ideal para las noches frescas de Madrid (55°F)" },
                            { id: "m_jacket_pesado", text: "Jacket pesado", sub: "🌙 Noches de 55°F en Madrid / Llevar si prefiere mayor abrigo", badge: "Clima 55°F" },
                            { id: "m_fleece", text: "Fleece", sub: "Confort en cabina presurizada de vuelo nocturno" },
                            { id: "m_correa_diario", text: "Correa diario", sub: "Uso casual" },
                            { id: "m_correa_salir", text: "Correa salir", sub: "Piel formal para combinar con calzado de noche" },
                            { id: "m_pantalon_pajama", text: "Pantalon pajama", sub: "Descanso" },
                            { id: "m_camisa_pajama", text: "Camisa pajama", sub: "Descanso" },
                            { id: "m_calsoncillos", text: "Calsoncillos", sub: "Mudas suficientes de algodón" },
                            { id: "m_medias_salir", text: "Medias salir", sub: "Para calzado formal" },
                            { id: "m_medias_diario", text: "Medias diario", sub: "Uso diario" },
                            { id: "m_medias_tenis", text: "Medias tenis", sub: "Deportivas y caminatas" },
                            { id: "m_ropa_ejercicio", text: "Ropa ejercicio", sub: "Gimnasio y entrenamientos" },
                            { id: "m_traje_bano", text: "Traje de baño", sub: "🏊 Piscina y spa (controlado por toggle de Playa)", tag: "beach" },
                            { id: "m_zapatos_salir", text: "Zapatos de salir", sub: "Mocasines / Piel formal" },
                            { id: "m_zapatos_diario", text: "Zapatos diario", sub: "Suela de goma para adoquines del Casco Antiguo" },
                            { id: "m_tenis", text: "Tenis", sub: "Deportivos / Caminatas largas" },
                            { id: "m_cepillo_dientes", text: "Cepillo dientes", sub: "Aseo dental" },
                            { id: "m_cepillo_pelo", text: "Cepillo pelo", sub: "Cuidado capilar" },
                            { id: "m_chapstik", text: "Chapstik", sub: "Bálsamo labial protector" },
                            { id: "m_corta_unas", text: "Corta uñas", sub: "Cuidado personal" },
                            { id: "m_dental_floss", text: "Dental floss", sub: "Hilo dental" },
                            { id: "m_desodorante", text: "Desodorante", sub: "Aseo personal" },
                            { id: "m_pasta_dientes", text: "Pasta dientes", sub: "Aseo dental" },
                            { id: "m_perfume", text: "Perfume", sub: "Fragrancia de viaje" },
                            { id: "m_razuradora", text: "Razuradora", sub: "Afeitado y cuchillas" },
                            { id: "m_shampoo", text: "Shampoo", sub: "Cuidado capilar" },
                            { id: "m_conditioner", text: "Conditioner", sub: "Acondicionador capilar" },
                            { id: "m_medicinas", text: "Medicinas", sub: "Botiquín y recetas personales para el viaje" },
                            { id: "m_cargador_celular", text: "Cargador Celular", sub: "Cable y cargador móvil" },
                            { id: "m_cargador_reloj", text: "Cargador reloj", sub: "Cargador Apple Watch / Smartwatch" },
                            { id: "m_prendas", text: "Prendas", sub: "Reloj de vestir, gemelos y accesorios personales" }
                        ]
                    },
                    {
                        name: "Equipamiento & Indumentaria de Golf",
                        icon: "⛳",
                        tag: "golf",
                        badge: "Golf Activo",
                        items: [
                            { id: "m_golf_polo", text: "Polos técnicos de golf con cuello", sub: "Código de vestimenta exigido en Almenara Golf Club", tag: "golf" },
                            { id: "m_golf_pants", text: "Pantalones / Bermudas técnicas de golf", sub: "Tejido elástico transpirable para campo", tag: "golf" },
                            { id: "m_golf_socks", text: "Medias de golf técnicas", sub: "Acolchado anti-rozaduras en talón y planta", tag: "golf" },
                            { id: "m_golf_belt", text: "Correa de golf deportiva", sub: "Ajuste elástico para el swing", tag: "golf" },
                            { id: "m_golf_windbreaker", text: "Chaqueta cortavientos / Chaleco ligero de golf", sub: "Para la brisa matutina en el campo", tag: "golf" },
                            { id: "m_golf_shoes", text: "Zapatos de golf (Spikeless / Soft spikes)", sub: "Suela con agarre especial sin clavos metálicos", tag: "golf" },
                            { id: "m_golf_gloves", text: "Guantes de golf (Piel Cabretta)", sub: "Guante principal + repuesto nuevo en empaque", tag: "golf" },
                            { id: "m_golf_cap", text: "Gorra deportiva o visera de golf", sub: "Protección solar obligatoria para 18 hoyos", tag: "golf" },
                            { id: "m_golf_balls", text: "Bolas de golf (Titleist Pro V1 o similar)", sub: "1 docena / bolas de juego para Almenara", tag: "golf" },
                            { id: "m_golf_tees", text: "Tees de golf (madera o bambú)", sub: "Surtido de alturas para Driver y hierros", tag: "golf" },
                            { id: "m_golf_divot_marker", text: "Arreglapiques (Divot tool) & Marcadores de bola", sub: "Reparador de piques y marcador para greens", tag: "golf" },
                            { id: "m_golf_towel", text: "Toalla de microfibra de golf", sub: "Para limpieza de varillas, palos y bolas", tag: "golf" },
                            { id: "m_golf_rangefinder", text: "Telémetro láser (Rangefinder) o Reloj GPS de golf", sub: "Medición exacta de distancias (+ cargador)", tag: "golf" },
                            { id: "m_golf_sunscreen", text: "Protector solar deportivo resistente al sudor (SPF 50+)", sub: "Protección de alta duración para 4-5h de juego", tag: "golf" },
                            { id: "m_golf_travel_bag", text: "Funda de viaje acolchada para palos", sub: "Protección en bodega o coordinar alquiler en club", tag: "golf" },
                            { id: "m_golf_thermos", text: "Botella térmica / Termo de agua para la ronda", sub: "Hidratación continua durante los 18 hoyos", tag: "golf" }
                        ]
                    },
                    {
                        name: "Indumentaria & Accesorios de Playa / Piscina",
                        icon: "🏖️",
                        tag: "beach",
                        badge: "Playa Activa",
                        items: [
                            { id: "m_beach_swim_extra", text: "Traje de baño adicional de cambio", sub: "Para rotar tras piscina infinita o solárium", tag: "beach" },
                            { id: "m_beach_linen_shirt", text: "Camisas de lino fresco / Polos de verano", sub: "Para almuerzos en el Beach Club o terraza", tag: "beach" },
                            { id: "m_beach_slides", text: "Sandalias de playa / Chanclas impermeables", sub: "Resistentes al agua para piscina y arena", tag: "beach" },
                            { id: "m_beach_hat", text: "Sombrero de sol / Panamá", sub: "Protección solar distinguida", tag: "beach" },
                            { id: "m_beach_sunglasses", text: "Gafas de sol polarizadas UV400", sub: "Anti-reflejo para agua y sol andaluz", tag: "beach" },
                            { id: "m_beach_bag", text: "Bolsa de playa / Mochila impermeable", sub: "Para llevar toalla, cremas y móvil", tag: "beach" },
                            { id: "m_beach_phone_pouch", text: "Funda impermeable o estanca para smartphone", sub: "Protección contra salpicaduras de agua y arena", tag: "beach" },
                            { id: "m_beach_sunscreen", text: "Protector solar corporal resistente al agua (SPF 50+)", sub: "Protección de amplio espectro para Costa del Sol", tag: "beach" },
                            { id: "m_beach_aftersun", text: "Gel hidratante post-solar (After-sun / Aloe Vera)", sub: "Alivio y regeneración tras el sol", tag: "beach" }
                        ]
                    },
                    {
                        name: "Sugerencias Complementarias (Cenas Michelin & Confort)",
                        icon: "✨",
                        badge: "Sugerido",
                        items: [
                            { id: "m_panuelo_bolsillo", text: "Pañuelo de bolsillo o corbata de seda", sub: "Para cena de gala en Amós 3★ Michelin / Rosewood Villa Magna" },
                            { id: "m_flight_socks", text: "Calcetines de descanso / compresión suave", sub: "Para vuelo transatlántico en Business de 8h 35m" },
                            { id: "m_airpods", text: "Auriculares con cancelación activa de ruido", sub: "Para descanso en vuelos y tren AVE" },
                            { id: "m_airtag", text: "Apple AirTag en maleta facturada y maletín", sub: "Rastreo de equipaje en tiempo real" }
                        ]
                    }
                ]
            },
            aileen: {
                name: "Aileen Rosso",
                icon: "👗",
                categories: [
                    {
                        name: "Checklist Viaje Original (Aileen Rosso)",
                        icon: "📋",
                        badge: "Lista Original",
                        items: [
                            { id: "a_camisas_larga", text: "Camisas manga larga", sub: "Lino y vestir para cenas y visitas" },
                            { id: "a_camisas_salir", text: "Camisas de Salir", sub: "Blusas elegantes de seda o satén para cenas" },
                            { id: "a_camisas_diario", text: "Camisas de Diario", sub: "Tejidos frescos y transpirables" },
                            { id: "a_mahones", text: "Mahones", sub: "Jeans de corte impecable para tours y traslados" },
                            { id: "a_pantalones", text: "Pantalones", sub: "Pantalones de vestir / lino para el sur" },
                            { id: "a_abrigo_pesado", text: "Abrigo pesado", sub: "🌙 Noches de 55°F en Madrid / Opcional según preferencia", badge: "Clima 55°F" },
                            { id: "a_abrigo_liviano", text: "Abrigo Liviano", sub: "Trench coat liviano / chaqueta de entretiempo" },
                            { id: "a_fleece", text: "Fleece", sub: "Cárdigan fino o abrigo suave para el avión" },
                            { id: "a_panuelo", text: "Pañuelo", sub: "Pashmina de seda para brisa, iglesias y aire acondicionado" },
                            { id: "a_bermuda", text: "Bermuda", sub: "☀️ Shorts elegantes para Sotogrande y paseos" },
                            { id: "a_correa", text: "Correa", sub: "Accesorio de diario" },
                            { id: "a_pajama", text: "Pajama", sub: "Pajama fresca de descanso" },
                            { id: "a_panties", text: "Panties", sub: "Mudas suficientes de algodón o microfibra" },
                            { id: "a_brazier", text: "Brazier", sub: "Diarios, strapless y de vestir" },
                            { id: "a_medias_diario", text: "Medias diario", sub: "Uso diario" },
                            { id: "a_medias_tenis", text: "Medias tenis", sub: "Para calzado deportivo y caminatas" },
                            { id: "a_ropa_ejercicio", text: "Ropa ejercicio", sub: "Gym y entrenamientos" },
                            { id: "a_brazier_ejercicios", text: "Brazier ejercicios", sub: "Top deportivo de soporte" },
                            { id: "a_traje_bano", text: "Traje de baño", sub: "🏊 Piscina y spa (controlado por toggle de Playa)", tag: "beach" },
                            { id: "a_zapatos_salir", text: "Zapatos de salir", sub: "Tacón cómodo o cuña elegante" },
                            { id: "a_zapatos_walking", text: "Zapatos diario walking", sub: "Suela plana indispensable para adoquines de Sevilla" },
                            { id: "a_tenis", text: "Tenis", sub: "Caminatas largas por museos y parques" },
                            { id: "a_cepillo_dientes", text: "Cepillo dientes", sub: "Aseo dental" },
                            { id: "a_cepillo_pelo", text: "Cepillo pelo", sub: "Peinado y cepillado" },
                            { id: "a_chapstik", text: "Chapstik", sub: "Bálsamo labial hidratante" },
                            { id: "a_corta_unas", text: "Corta uñas", sub: "Corta uñas y lima de viaje" },
                            { id: "a_dental_floss", text: "Dental floss", sub: "Hilo dental" },
                            { id: "a_desodorante", text: "Desodorante", sub: "Aseo personal" },
                            { id: "a_pasta_dientes", text: "Pasta dientes", sub: "Aseo dental" },
                            { id: "a_perfume", text: "Perfume", sub: "Fragrancia de viaje" },
                            { id: "a_razuradora", text: "Razuradora", sub: "Rasuradora femenina" },
                            { id: "a_shampoo", text: "Shampoo", sub: "Cuidado capilar" },
                            { id: "a_plancha_pelo", text: "Plancha de Pelo", sub: "⚡ Verificar voltaje 110-240V para red de 230V de España", badge: "230V España" },
                            { id: "a_medicinas", text: "Medicinas", sub: "Botiquín personal y analgésicos" },
                            { id: "a_cargador_celular", text: "Cargador Celular", sub: "Cable y cargador móvil" },
                            { id: "a_cargador_reloj", text: "Cargador reloj", sub: "Cargador Smartwatch" },
                            { id: "a_prendas", text: "Prendas", sub: "Joyero de viaje seguro en bolso de mano" },
                            { id: "a_voltage_converter", text: "Voltage converter", sub: "Adaptador europeo Tipo C/F (230V / 50Hz)", badge: "Enchufe EU" }
                        ]
                    },
                    {
                        name: "Acompañamiento / Indumentaria de Golf",
                        icon: "⛳",
                        tag: "golf",
                        badge: "Golf Activo",
                        items: [
                            { id: "a_golf_polo", text: "Polo de golf / Top técnico con cuello", sub: "Etiqueta exigida en casa club y campo de golf", tag: "golf" },
                            { id: "a_golf_skort", text: "Pantalones / Shorts / Falda-pantalón de golf", sub: "Tejido técnico elástico y transpirable", tag: "golf" },
                            { id: "a_golf_shoes", text: "Zapatos de golf o tenis de suela plana", sub: "Aptos para caminar sobre césped de campo", tag: "golf" },
                            { id: "a_golf_visor", text: "Visera o gorra deportiva de golf", sub: "Protección solar chic para 18 hoyos", tag: "golf" },
                            { id: "a_golf_sunglasses", text: "Gafas de sol con alta protección UV", sub: "Descanso visual en campo abierto", tag: "golf" },
                            { id: "a_golf_sunscreen", text: "Protector solar facial & corporal deportivo SPF 50+", sub: "Resistente a la exposición continua al aire libre", tag: "golf" }
                        ]
                    },
                    {
                        name: "Indumentaria & Accesorios de Playa / Piscina",
                        icon: "🏖️",
                        tag: "beach",
                        badge: "Playa Activa",
                        items: [
                            { id: "a_beach_swim_extra", text: "Traje de baño adicional de cambio", sub: "Para alternar en spa, solárium y piscinas", tag: "beach" },
                            { id: "a_beach_coverup", text: "Salida de baño / Kimono / Pareo elegante", sub: "Para tránsito del spa a la piscina o solárium", tag: "beach" },
                            { id: "a_beach_sandals", text: "Sandalias de playa / Chanclas de diseño impermeables", sub: "Calzado para áreas húmedas y piscina", tag: "beach" },
                            { id: "a_beach_hat", text: "Sombrero de sol / Pamina de ala ancha", sub: "Protección solar chic para la Costa del Sol", tag: "beach" },
                            { id: "a_beach_tote", text: "Bolso de playa / Capazo o Tote bag amplio", sub: "Para llevar toalla, libros y cosmética", tag: "beach" },
                            { id: "a_beach_phone_pouch", text: "Funda impermeable o estanca para smartphone", sub: "Protección total contra agua y arena", tag: "beach" },
                            { id: "a_beach_sunscreen", text: "Protector solar corporal resistente al agua SPF 50+", sub: "Protección de amplio espectro", tag: "beach" },
                            { id: "a_beach_aftersun", text: "Loción o gel post-solar calmante (After-sun)", sub: "Hidratación profunda post-bronceado", tag: "beach" }
                        ]
                    },
                    {
                        name: "Sugerencias Complementarias (Cenas VIP & Belleza)",
                        icon: "✨",
                        badge: "Sugerido",
                        items: [
                            { id: "a_vestidos_dia", text: "Vestidos midi vaporosos de lino para el día", sub: "Frescura distinguida para Sevilla y bodegas" },
                            { id: "a_vestidos_noche", text: "Vestidos de cóctel / noche de gala", sub: "Para Rosewood Villa Magna y Hotel Colón" },
                            { id: "a_bolso_crossbody", text: "Bolso cruzado seguro (Crossbody) y Clutch de noche", sub: "Seguridad en tours y elegancia en cenas" },
                            { id: "a_protector_facial", text: "Protector solar facial antiedad SPF 50+ de amplio espectro", sub: "Protección diaria antienvejecimiento indispensable" },
                            { id: "a_crema_hidratante", text: "Sérum facial ultra-hidratante & Crema intensiva", sub: "Recuperación cutánea tras vuelo y clima seco" },
                            { id: "a_desmaquillante", text: "Toallitas desmaquillantes / Agua micelar viaje", sub: "Limpieza facial nocturna" },
                            { id: "a_airtag", text: "Apple AirTag en cartera de mano y maleta", sub: "Localización precisa en iPhone" }
                        ]
                    }
                ]
            },
            shared: {
                name: "Equipaje Compartido",
                icon: "🧳",
                categories: [
                    {
                        name: "Documentos, Finanzas & Fidelización VIP",
                        icon: "🛂",
                        badge: "VIP",
                        items: [
                            { id: "s_pasaportes", text: "Pasaportes vigentes (Milton & Aileen)", sub: "Mínimo 6 meses de vigencia y copias en la nube" },
                            { id: "s_amex", text: "Tarjeta American Express Platinum", sub: "Acceso a Centurion Lounges, Delta Sky Club y beneficios FHR" },
                            { id: "s_loyalty", text: "Tarjetas de fidelización digitales (Delta Platinum, Mosaic 3, Iberia Plus)", sub: "Prioridad de equipaje y embarque" },
                            { id: "s_ave_tickets", text: "Billetes de tren Renfe AVE Confort (Localizador 73MWSR)", sub: "Coche 1, Asientos 9B y 9C (25 Sep)" },
                            { id: "s_hotel_vmagna", text: "Confirmación Rosewood Villa Magna Madrid (32298SG208578)", sub: "Paseo de la Castellana 22, Barrio de Salamanca" }
                        ]
                    },
                    {
                        name: "Conectividad, Carga & Dispositivos",
                        icon: "⚡",
                        badge: "Tech",
                        items: [
                            { id: "s_adaptadores", text: "2x Adaptadores de enchufe europeo (Tipo C/F)", sub: "Para enchufes redondos de pared en España" },
                            { id: "s_cargador_gan", text: "Cargador de pared GaN 65W multidispositivo (USB-C/A)", sub: "Carga simultánea de iPhones, Apple Watch y iPads" },
                            { id: "s_cables", text: "Cables de carga rápida largos (USB-C y Lightning 2m)", sub: "Para habitaciones de hotel y transporte" },
                            { id: "s_powerbank", text: "Batería externa portátil (PowerBank 10,000 mAh)", sub: "🔋 Llevar siempre en equipaje de mano (prohibido en bodega)" },
                            { id: "s_audio_adapter", text: "Adaptador de audio para cabina de avión (Jack 3.5mm o Bluetooth)", sub: "Para conectar auriculares al sistema de entretenimiento de vuelo" }
                        ]
                    },
                    {
                        name: "Botiquín de Viaje & Confort en Ruta",
                        icon: "💊",
                        badge: "Salud",
                        items: [
                            { id: "s_compeed", text: "Curitas hidrocoloides para ampollas (tipo Compeed)", sub: "Salvavidas para caminatas en adoquines de Sevilla y Madrid" },
                            { id: "s_digestivos", text: "Antiácidos / Digestivos", sub: "Para degustar la gastronomía española sin molestias" },
                            { id: "s_analgesicos", text: "Analgésicos (Ibuprofeno, Paracetamol)", sub: "Alivio general para dolores o fatiga" },
                            { id: "s_gotas_ojos", text: "Gotas oculares lubricantes (Lágrimas artificiales)", sub: "Para evitar sequedad ocular en vuelos largos" },
                            { id: "s_toallitas", text: "Toallitas desinfectantes de viaje", sub: "Para superficies de avión y tren" }
                        ]
                    }
                ]
            }
        };

        function getTravelerPackingStats(tripId, travelerKey) {
            const spec = TRAVELER_PACKING_SPECS[travelerKey];
            if (!spec) return { total: 0, checked: 0, pct: 0 };
            const trip = (appData.trips || []).find(t => t.id === tripId);
            const acts = trip?.activitiesConfig || { golf: true, beach: true };
            const storageKey = `packing_checked_${tripId}`;
            const checkedState = JSON.parse(localStorage.getItem(storageKey) || '{}');
            let total = 0, checked = 0;

            spec.categories.forEach(cat => {
                if (cat.tag === 'golf' && !acts.golf) return;
                if (cat.tag === 'beach' && !acts.beach) return;
                cat.items.forEach(item => {
                    if (item.tag === 'golf' && !acts.golf) return;
                    if (item.tag === 'beach' && !acts.beach) return;
                    total++;
                    if (checkedState[item.id]) checked++;
                });
            });

            const custom = (trip?.customPackingList || []).filter(c => c.traveler === travelerKey || (!c.traveler && travelerKey === 'shared'));
            custom.forEach(c => {
                total++;
                if (checkedState[c.id]) checked++;
            });
            const pct = total > 0 ? Math.round((checked / total) * 100) : 0;
            return { total, checked, pct };
        }

        function switchPackingTraveler(travelerKey, tripId) {
            currentPackingTraveler = travelerKey;
            refreshAllPackingComponents(tripId);
        }

        function toggleTripActivity(tripId, activityKey, isChecked) {
            const trip = (appData.trips || []).find(t => t.id === tripId);
            if (trip) {
                if (!trip.activitiesConfig) trip.activitiesConfig = { golf: true, beach: true };
                trip.activitiesConfig[activityKey] = isChecked;
                saveState();
                refreshAllPackingComponents(tripId);
                showToast(`${activityKey === 'golf' ? '⛳ Golf' : '🏖️ Playa & Piscina'} ${isChecked ? 'activado' : 'desactivado'}`);
            }
        }

        function refreshAllPackingComponents(tripId) {
            const trip = (appData.trips || []).find(t => t.id === tripId) || (appData.trips || [])[0];
            if (!trip) return;
            const detailHost = document.getElementById('detail-tab-packing');
            if (detailHost && (detailHost.innerHTML.trim() !== '' || document.getElementById('view-detail')?.classList.contains('active'))) {
                renderSmartPackingComponent(detailHost, trip);
            }
            const globalHost = document.getElementById('global-packing-matrix-host');
            if (globalHost) {
                renderSmartPackingComponent(globalHost, trip);
            }
        }

        function renderSmartPackingComponent(container, trip) {
            const config = trip.baggageConfig || { mode: 'checked', laundryAvailable: true };
            const climate = trip.climate || { tempLowF: 55, tempHighF: 84 };
            const days = trip.durationDays || 12;
            const acts = trip.activitiesConfig || { golf: true, beach: true };

            const mStats = getTravelerPackingStats(trip.id, 'milton');
            const aStats = getTravelerPackingStats(trip.id, 'aileen');
            const sStats = getTravelerPackingStats(trip.id, 'shared');
            const currentStats = currentPackingTraveler === 'milton' ? mStats : (currentPackingTraveler === 'aileen' ? aStats : sStats);

            container.innerHTML = `
                <!-- Activity Toggles: Golf & Playa/Piscina -->
                <div class="activity-toggles-bar">
                    <div class="activity-toggle-card ${acts.golf ? 'active' : ''}">
                        <div class="toggle-info">
                            <span class="toggle-icon">⛳</span>
                            <div>
                                <div class="toggle-label">¿Jugarás Golf?</div>
                                <div class="toggle-desc">${acts.golf ? 'Indumentaria técnica, calzado, palos y accesorios activados' : 'Desactivado (sin equipo de golf)'}</div>
                            </div>
                        </div>
                        <label class="ios-switch">
                            <input type="checkbox" ${acts.golf ? 'checked' : ''} onchange="toggleTripActivity('${trip.id}', 'golf', this.checked)">
                            <span class="slider"></span>
                        </label>
                    </div>

                    <div class="activity-toggle-card ${acts.beach ? 'active' : ''}">
                        <div class="toggle-info">
                            <span class="toggle-icon">🏖️</span>
                            <div>
                                <div class="toggle-label">¿Playa o Piscina?</div>
                                <div class="toggle-desc">${acts.beach ? 'Trajes de baño, salidas, sandalias y protección solar activados' : 'Desactivado (sin ropa de playa)'}</div>
                            </div>
                        </div>
                        <label class="ios-switch">
                            <input type="checkbox" ${acts.beach ? 'checked' : ''} onchange="toggleTripActivity('${trip.id}', 'beach', this.checked)">
                            <span class="slider"></span>
                        </label>
                    </div>
                </div>

                <!-- Baggage Mode Selector (Carry-on vs Bodega) -->
                <div class="packing-config-card" style="margin-bottom: 12px; padding: 12px 14px;">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
                        <span style="font-size: 0.75rem; font-weight: 800; color: var(--text-main); text-transform: uppercase; letter-spacing: 0.04em;">
                            🧳 Categoría de Equipaje
                        </span>
                        <span style="font-size: 0.72rem; font-weight: 700; color: var(--gold-dark); background: var(--gold-light); padding: 2px 8px; border-radius: 8px;">
                            ${config.mode === 'carry_on' ? '🎒 Solo Carry-On (Mano)' : '🧳 Maleta en Bodega (Facturada)'}
                        </span>
                    </div>

                    <div class="segmented-control" style="margin-bottom: 8px;">
                        <button class="segment-btn ${config.mode !== 'carry_on' ? 'active' : ''}" onclick="setTripBaggageMode('${trip.id}', 'checked')">
                            🧳 Maleta en Bodega
                        </button>
                        <button class="segment-btn ${config.mode === 'carry_on' ? 'active' : ''}" onclick="setTripBaggageMode('${trip.id}', 'carry_on')">
                            🎒 Solo Carry-On
                        </button>
                    </div>

                    <div style="font-size: 0.72rem; color: var(--text-muted); line-height: 1.35;">
                        ${config.mode === 'carry_on' 
                            ? '⚡ <strong>Modo Carry-On activo:</strong> Líquidos restringidos a envases ≤100 ml en bolsa transparente. Equipaje de cabina sin esperas en carrusel.' 
                            : '✨ <strong>Modo Maleta en Bodega activo:</strong> Franquicia Business (2x gratis de 32 kg c/u con JetBlue Mosaic 3 / Iberia Business). Espacio completo para ropa formal, calzado y palos de golf.'}
                    </div>
                </div>

                <!-- Print All Checklists Button -->
                <button class="print-checklist-btn" onclick="printPackingChecklists('${trip.id}')">
                    <span style="font-size: 1.1rem;">🖨️</span>
                    <span>Imprimir Checklists (Milton, Aileen y Compartida)</span>
                </button>

                <!-- Traveler Selector Tabs -->
                <div class="traveler-selector">
                    <button class="traveler-selector-btn ${currentPackingTraveler === 'milton' ? 'active' : ''}" onclick="switchPackingTraveler('milton', '${trip.id}')">
                        👔 Milton <span class="badge-count">${mStats.checked}/${mStats.total}</span>
                    </button>
                    <button class="traveler-selector-btn ${currentPackingTraveler === 'aileen' ? 'active' : ''}" onclick="switchPackingTraveler('aileen', '${trip.id}')">
                        👗 Aileen <span class="badge-count">${aStats.checked}/${aStats.total}</span>
                    </button>
                    <button class="traveler-selector-btn ${currentPackingTraveler === 'shared' ? 'active' : ''}" onclick="switchPackingTraveler('shared', '${trip.id}')">
                        🧳 Compartido <span class="badge-count">${sStats.checked}/${sStats.total}</span>
                    </button>
                </div>

                <!-- Weather Advisory Card -->
                <div class="weather-advisory-box">
                    <div style="font-weight: 800; display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px;">
                        <span>🌤️ Previsión Climática · España (18–29 Sep):</span>
                        <span style="font-size: 0.7rem; background: #DCFCE7; color: #15803D; padding: 2px 8px; border-radius: 12px; font-weight: 700;">12 Días</span>
                    </div>
                    <div style="margin-bottom: 3px;">• <strong>Sotogrande (Costa del Sol):</strong> 64°F a 79°F · Soleado mediterráneo (golf en Almenara, spa y piscinas).</div>
                    <div style="margin-bottom: 3px;">• <strong>Sevilla:</strong> 64°F a 84°F · Caluroso y seco de día, noches cálidas (caminatas monumentales por adoquines).</div>
                    <div style="margin-bottom: 6px;">• <strong>Madrid:</strong> 55°F a 75°F · Noches frescas (55°F) y tardes templadas (cenas elegantes en Rosewood Villa Magna).</div>
                    <div style="padding-top: 6px; border-top: 1px dashed #86EFAC; font-size: 0.74rem; color: #14532D;">
                        📋 <strong>Checklist Viaje integrado al 100%:</strong> Contiene todas tus prendas y accesorios originales. Para las noches frescas de Madrid (55°F), tu <em>Jacket pesado / Abrigo pesado</em> está disponible y marcado para llevar según tu preferencia. Activa o desactiva Golf y Playa con los botones superiores para adaptar el equipaje dinámicamente.
                    </div>
                </div>

                <!-- Luggage Config & Progress Card -->
                <div class="packing-progress-wrapper">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                        <span style="font-size: 0.8rem; font-weight: 700; color: var(--text-main);">
                            Progreso de ${TRAVELER_PACKING_SPECS[currentPackingTraveler].name}
                        </span>
                        <span style="font-size: 0.8rem; font-weight: 800; color: var(--gold-dark);">
                            ${currentStats.checked} de ${currentStats.total} (${currentStats.pct}%)
                        </span>
                    </div>
                    <div class="packing-progress-bar-bg">
                        <div class="packing-progress-bar-fill" style="width: ${currentStats.pct}%;"></div>
                    </div>
                    
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 12px; padding-top: 10px; border-top: 1px solid var(--border-subtle); font-size: 0.74rem;">
                        <span style="color: var(--text-muted);">
                            🧳 Maleta Facturada Business (2x gratis c/u) · 🧺 Lavandería en hoteles 5★
                        </span>
                        <button onclick="resetPackingChecklist('${trip.id}')" style="background: none; border: none; color: #EF4444; font-size: 0.72rem; font-weight: 700; cursor: pointer;">
                            Desmarcar pestaña
                        </button>
                    </div>
                </div>

                <!-- Custom Item Input -->
                <div style="display: flex; gap: 8px; margin-bottom: 14px;">
                    <input type="text" class="custom-item-input" style="flex: 1; background: #FFF; border: 1px solid var(--border-subtle); border-radius: 12px; padding: 10px 14px; font-size: 0.8rem; outline: none;" placeholder="Añadir a la maleta de ${TRAVELER_PACKING_SPECS[currentPackingTraveler].name.split(' ')[0]}...">
                    <button class="header-btn" onclick="addCustomPackingItem('${trip.id}', this)" style="padding: 0 16px;">➕ Añadir</button>
                </div>

                <div class="packing-matrix-items"></div>
            `;

            renderCalculatedPackingList(container, trip);
        }

        function setTripBaggageMode(tripId, mode) {
            const trip = (appData.trips || []).find(t => t.id === tripId);
            if (trip) {
                if (!trip.baggageConfig) trip.baggageConfig = {};
                trip.baggageConfig.mode = mode;
                saveState();
                refreshAllPackingComponents(tripId);
                showToast(`🧳 Modo ajustado a: ${mode === 'carry_on' ? 'Solo Carry-On' : 'Maleta en Bodega'}`);
            }
        }

        function handleHeaderPrint() {
            const activeTrip = (appData.trips || []).find(t => t.status === 'active') || (appData.trips || [])[0];
            const isPackingView = document.getElementById('view-packing')?.classList.contains('active') ||
                (document.getElementById('view-detail')?.classList.contains('active') && document.getElementById('detail-tab-packing')?.style.display !== 'none');
            
            if (activeTrip && isPackingView) {
                printPackingChecklists(activeTrip.id);
            } else if (activeTrip && confirm("¿Deseas imprimir las listas de empaque (Milton, Aileen y Compartida)?\n\n• Pulsa ACEPTAR para imprimir las Listas de Empaque.\n• Pulsa CANCELAR para imprimir la vista general del itinerario.")) {
                printPackingChecklists(activeTrip.id);
            } else {
                window.print();
            }
        }

        function printPackingChecklists(tripId) {
            const trip = (appData.trips || []).find(t => t.id === tripId) || (appData.trips || [])[0];
            if (!trip) return;

            const acts = trip.activitiesConfig || { golf: true, beach: true };
            const config = trip.baggageConfig || { mode: 'checked' };
            const storageKey = `packing_checked_${trip.id}`;
            const checkedState = JSON.parse(localStorage.getItem(storageKey) || '{}');

            let printArea = document.getElementById('printable-packing-area');
            if (!printArea) {
                printArea = document.createElement('div');
                printArea.id = 'printable-packing-area';
                document.body.appendChild(printArea);
            }

            const mStats = getTravelerPackingStats(trip.id, 'milton');
            const aStats = getTravelerPackingStats(trip.id, 'aileen');
            const sStats = getTravelerPackingStats(trip.id, 'shared');

            const renderTravelerPrintSection = (travelerKey, title, icon, stats) => {
                const spec = TRAVELER_PACKING_SPECS[travelerKey];
                if (!spec) return '';

                const categories = [];
                spec.categories.forEach(cat => {
                    if (cat.tag === 'golf' && !acts.golf) return;
                    if (cat.tag === 'beach' && !acts.beach) return;

                    const filteredItems = cat.items.filter(it => {
                        if (it.tag === 'golf' && !acts.golf) return false;
                        if (it.tag === 'beach' && !acts.beach) return false;
                        return true;
                    });

                    if (filteredItems.length > 0) {
                        categories.push({
                            name: cat.name,
                            icon: cat.icon,
                            tag: cat.tag,
                            badge: cat.badge,
                            items: filteredItems
                        });
                    }
                });

                // Custom items
                const customItems = (trip.customPackingList || []).filter(c => c.traveler === travelerKey || (!c.traveler && travelerKey === 'shared'));
                if (customItems.length > 0) {
                    categories.push({
                        name: "Artículos Personalizados Añadidos",
                        icon: "✨",
                        items: customItems
                    });
                }

                return `
                    <div class="print-traveler-section">
                        <div class="print-traveler-header">
                            <div style="font-size: 13pt; font-weight: 800; color: #0F1D2E;">
                                ${icon} ${title}
                            </div>
                            <div style="font-size: 9pt; font-weight: 700; color: #4B5563;">
                                ${stats.checked} de ${stats.total} empacados (${stats.pct}%)
                            </div>
                        </div>
                        <div class="print-category-grid">
                            ${categories.map(cat => {
                                let catChecked = 0;
                                cat.items.forEach(it => { if (checkedState[it.id]) catChecked++; });
                                return `
                                    <div class="print-category-card">
                                        <div class="print-category-title">
                                            <span>${cat.icon} <strong>${cat.name}</strong></span>
                                            <span style="font-size: 7.5pt; color: #6B7280; font-weight: 600;">${catChecked}/${cat.items.length}</span>
                                        </div>
                                        <div class="print-items-list">
                                            ${cat.items.map(it => {
                                                const isChecked = !!checkedState[it.id];
                                                return `
                                                    <div class="print-item-row ${isChecked ? 'is-checked' : ''}">
                                                        <span class="print-checkbox ${isChecked ? 'checked' : ''}">
                                                            ${isChecked ? '✓' : ''}
                                                        </span>
                                                        <span class="print-item-label ${isChecked ? 'checked-text' : ''}">
                                                            ${it.text}
                                                            ${it.sub ? `<small class="print-sub">${it.sub}</small>` : ''}
                                                        </span>
                                                    </div>
                                                `;
                                            }).join('')}
                                        </div>
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    </div>
                `;
            };

            const nowStr = new Date().toLocaleDateString('es-ES', { day: '2-digit', month: 'short', year: 'numeric' });

            printArea.innerHTML = `
                <div class="print-document">
                    <div class="print-main-header">
                        <div class="print-logo-row">
                            <div style="font-family: 'Cormorant Garamond', Georgia, serif; font-size: 18pt; font-weight: 700; color: #0F1D2E; letter-spacing: 0.5px;">
                                🧭 TRAVEL PLANNER · LISTAS DE EMPAQUE OFICIALES
                            </div>
                            <div style="font-size: 8.5pt; color: #6B7280; text-align: right;">
                                Fecha de Impresión: ${nowStr}
                            </div>
                        </div>
                        
                        <div class="print-trip-summary">
                            <div><strong>Viaje:</strong> ${trip.title}</div>
                            <div><strong>Fechas:</strong> ${trip.datesDisplay || (trip.startDate + ' a ' + trip.endDate)} (${trip.durationDays || 12} Días)</div>
                            <div><strong>Destino:</strong> ${trip.destination}</div>
                            <div><strong>Previsión Clima:</strong> ${trip.climate?.tempLowF || 55}°F a ${trip.climate?.tempHighF || 84}°F · ${trip.climate?.condition || 'Soleado'}</div>
                            <div><strong>Modalidad Equipaje:</strong> ${config.mode === 'carry_on' ? '🎒 Solo Carry-On (Equipaje de Mano)' : '🧳 Maleta en Bodega (Checked Baggage Business)'}</div>
                            <div><strong>Actividades:</strong> ${acts.golf ? '⛳ Golf Activo' : 'Sin Golf'} &nbsp;|&nbsp; ${acts.beach ? '🏖️ Playa/Piscina Activa' : 'Sin Playa'}</div>
                        </div>
                    </div>

                    <!-- 1. MILTON CRUZ -->
                    ${renderTravelerPrintSection('milton', 'Milton Cruz', '👔', mStats)}

                    <div class="print-page-break"></div>

                    <!-- 2. AILEEN ROSSO -->
                    ${renderTravelerPrintSection('aileen', 'Aileen Rosso', '👗', aStats)}

                    <div class="print-page-break"></div>

                    <!-- 3. EQUIPAJE COMPARTIDO & VIP -->
                    ${renderTravelerPrintSection('shared', 'Equipaje Compartido & VIP', '🧳', sStats)}
                </div>
            `;

            document.body.classList.add('print-only-checklists');

            window.onafterprint = () => {
                document.body.classList.remove('print-only-checklists');
            };

            setTimeout(() => {
                window.print();
            }, 120);
        }

        function toggleTripLaundry(tripId, val) {
            const trip = (appData.trips || []).find(t => t.id === tripId);
            if (trip) {
                if (!trip.baggageConfig) trip.baggageConfig = {};
                trip.baggageConfig.laundryAvailable = val;
                saveState();
                refreshAllPackingComponents(tripId);
                showToast(val ? '🧺 Lavandería activada (ropa reducida)' : 'Lavandería desactivada');
            }
        }

        function renderCalculatedPackingList(container, trip) {
            const itemsContainer = container.querySelector('.packing-matrix-items');
            if (!itemsContainer) return;
            itemsContainer.innerHTML = '';

            const acts = trip.activitiesConfig || { golf: true, beach: true };
            const storageKey = `packing_checked_${trip.id}`;
            const checkedState = JSON.parse(localStorage.getItem(storageKey) || '{}');
            const spec = TRAVELER_PACKING_SPECS[currentPackingTraveler] || TRAVELER_PACKING_SPECS.milton;

            const categories = [];

            spec.categories.forEach(cat => {
                if (cat.tag === 'golf' && !acts.golf) return;
                if (cat.tag === 'beach' && !acts.beach) return;

                const filteredItems = cat.items.filter(it => {
                    if (it.tag === 'golf' && !acts.golf) return false;
                    if (it.tag === 'beach' && !acts.beach) return false;
                    return true;
                });

                if (filteredItems.length > 0) {
                    categories.push({
                        name: cat.name,
                        icon: cat.icon,
                        tag: cat.tag,
                        badge: cat.badge,
                        items: filteredItems
                    });
                }
            });

            // Custom items for this traveler
            const customItems = (trip.customPackingList || []).filter(c => c.traveler === currentPackingTraveler || (!c.traveler && currentPackingTraveler === 'shared'));
            if (customItems.length > 0) {
                categories.push({
                    name: "Artículos Personalizados Añadidos",
                    icon: "✨",
                    items: customItems
                });
            }

            categories.forEach(cat => {
                const box = document.createElement('div');
                box.style.marginBottom = '14px';

                let catChecked = 0;
                cat.items.forEach(it => { if (checkedState[it.id]) catChecked++; });

                box.innerHTML = `
                    <div class="packing-category-title" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                        <span>
                            ${cat.icon} ${cat.name}
                            ${cat.badge ? `<span style="font-size: 0.65rem; background: var(--gold-light); color: var(--gold-dark); padding: 2px 6px; border-radius: 6px; margin-left: 6px; font-weight: 700;">${cat.badge}</span>` : ''}
                        </span>
                        <span style="font-size: 0.7rem; font-weight: 700; color: var(--text-muted);">${catChecked}/${cat.items.length}</span>
                    </div>
                `;

                const list = document.createElement('div');
                list.style.background = '#FFFFFF';
                list.style.border = '1px solid var(--border-subtle)';
                list.style.borderRadius = '16px';
                list.style.padding = '4px 14px';

                const isCarryOn = (trip.baggageConfig?.mode === 'carry_on');
                cat.items.forEach(item => {
                    const isChecked = !!checkedState[item.id];
                    const row = document.createElement('div');
                    row.className = `check-item-ios ${isChecked ? 'checked' : ''}`;
                    row.onclick = () => togglePackingItemState(trip.id, item.id);

                    const isLiquid = /perfume|shampoo|conditioner|pasta dientes|protector|crema|bloqueador/i.test(item.text);
                    const carryOnBadge = (isCarryOn && isLiquid) ? `<span style="font-size: 0.62rem; background: #FEF3C7; color: #B45309; padding: 2px 6px; border-radius: 6px; margin-left: 6px; font-weight: 700;">🧴 Máx 100ml</span>` : '';

                    row.innerHTML = `
                        <div class="checkbox-ios">
                            <svg viewBox="0 0 24 24"><polyline points="20 6 9 17 4 12"/></svg>
                        </div>
                        <div style="flex: 1;">
                            <div class="check-text-title">
                                ${item.text}
                                ${item.badge ? `<span style="font-size: 0.65rem; background: #FEF3C7; color: #B45309; padding: 2px 6px; border-radius: 6px; margin-left: 6px; font-weight: 700;">${item.badge}</span>` : ''}
                                ${carryOnBadge}
                            </div>
                            ${item.sub ? `<div class="check-text-desc">${item.sub}</div>` : ''}
                        </div>
                    `;
                    list.appendChild(row);
                });

                box.appendChild(list);
                itemsContainer.appendChild(box);
            });
        }

        function togglePackingItemState(tripId, itemId) {
            const storageKey = `packing_checked_${tripId}`;
            const checkedState = JSON.parse(localStorage.getItem(storageKey) || '{}');
            checkedState[itemId] = !checkedState[itemId];
            localStorage.setItem(storageKey, JSON.stringify(checkedState));
            refreshAllPackingComponents(tripId);
        }

        function resetPackingChecklist(tripId) {
            if (!confirm(`¿Deseas desmarcar todos los artículos de la maleta de ${TRAVELER_PACKING_SPECS[currentPackingTraveler].name}?`)) return;
            const storageKey = `packing_checked_${tripId}`;
            const checkedState = JSON.parse(localStorage.getItem(storageKey) || '{}');
            const spec = TRAVELER_PACKING_SPECS[currentPackingTraveler];
            if (spec) {
                spec.categories.forEach(c => {
                    c.items.forEach(i => delete checkedState[i.id]);
                });
            }
            const trip = (appData.trips || []).find(t => t.id === tripId);
            (trip?.customPackingList || []).filter(c => c.traveler === currentPackingTraveler).forEach(i => delete checkedState[i.id]);
            localStorage.setItem(storageKey, JSON.stringify(checkedState));
            refreshAllPackingComponents(tripId);
            showToast('Checklist desmarcado');
        }

        function addCustomPackingItem(tripId, btnEl) {
            let input = null;
            if (btnEl && btnEl.parentElement) {
                input = btnEl.parentElement.querySelector('.custom-item-input');
            }
            if (!input) {
                input = document.querySelector('.custom-item-input');
            }
            const val = (input?.value || '').trim();
            if (!val) return;

            const trip = (appData.trips || []).find(t => t.id === tripId);
            if (trip) {
                if (!trip.customPackingList) trip.customPackingList = [];
                trip.customPackingList.push({
                    id: 'custom_' + Date.now(),
                    text: val,
                    sub: `Añadido para ${TRAVELER_PACKING_SPECS[currentPackingTraveler].name}`,
                    traveler: currentPackingTraveler
                });
                input.value = '';
                saveState();
                refreshAllPackingComponents(tripId);
                showToast(`Artículo añadido a la maleta de ${TRAVELER_PACKING_SPECS[currentPackingTraveler].name.split(' ')[0]}`);
            }
        }

        // Global Packing Screen
        let activeGlobalPackingTripId = null;

        function renderGlobalPacking() {
            const container = document.getElementById('global-packing-content');
            if (!container) return;

            if (!activeGlobalPackingTripId) {
                const activeTrip = (appData.trips || []).find(t => t.status === 'active') || (appData.trips || [])[0];
                if (activeTrip) activeGlobalPackingTripId = activeTrip.id;
            }
            const trip = (appData.trips || []).find(t => t.id === activeGlobalPackingTripId) || (appData.trips || [])[0];
            if (!trip) {
                container.innerHTML = `<div style="text-align: center; padding: 20px; color: var(--text-muted);">No hay viajes seleccionados para empaque.</div>`;
                return;
            }

            container.innerHTML = `
                <div style="display: flex; gap: 8px; overflow-x: auto; padding-bottom: 12px; margin-bottom: 8px; scrollbar-width: none;">
                    ${(appData.trips || []).map(t => `
                        <button class="sub-pill ${t.id === trip.id ? 'active' : ''}" onclick="selectGlobalPackingTrip('${t.id}')">
                            ${t.flag || '📍'} ${t.title.split(':')[0].slice(0, 22)}
                        </button>
                    `).join('')}
                </div>
                <div id="global-packing-matrix-host"></div>
            `;

            const host = document.getElementById('global-packing-matrix-host');
            if (host) renderSmartPackingComponent(host, trip);
        }

        function selectGlobalPackingTrip(tripId) {
            activeGlobalPackingTripId = tripId;
            renderGlobalPacking();
        }

        // Docs & Profile Screen
        function renderDocs() {
            const profileContainer = document.getElementById('profile-container');
            const hotlinesContainer = document.getElementById('hotlines-container');
            const prof = appData.travelersProfile || {};

            if (profileContainer) {
                const loy = prof.loyaltyPrograms || {};
                profileContainer.innerHTML = `
                    <div class="packing-config-card">
                        <div style="font-size: 0.7rem; font-weight: 800; color: var(--gold-dark); text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 4px;">Viajeros Titulares</div>
                        <div style="font-family: 'Cormorant Garamond', serif; font-size: 1.5rem; font-weight: 700; color: var(--text-main); margin-bottom: 12px;">${prof.primaryTravelers || 'Milton Cruz & Aileen Rosso'}</div>
                        
                        <div style="display: flex; flex-direction: column; gap: 8px; font-size: 0.78rem; border-top: 1px solid var(--border-subtle); padding-top: 10px;">
                            <div>✈️ <strong>Delta Air Lines:</strong> ${loy.delta}</div>
                            <div>💎 <strong>JetBlue Airways:</strong> ${loy.jetblue}</div>
                            <div>🇪🇸 <strong>Iberia Plus:</strong> ${loy.iberia}</div>
                            <div>💳 <strong>American Express:</strong> ${loy.amex}</div>
                        </div>
                    </div>
                `;
            }

            if (hotlinesContainer) {
                hotlinesContainer.innerHTML = '';
                (prof.emergencyContacts || []).forEach(c => {
                    const row = document.createElement('div');
                    row.style.cssText = 'display: flex; justify-content: space-between; align-items: center; padding: 12px 4px; border-bottom: 1px solid var(--border-subtle); font-size: 0.82rem;';
                    const cleanPhone = c.number.replace(/[^0-9+]/g, '');
                    row.innerHTML = `
                        <span style="font-weight: 600;">${c.label}</span>
                        <a href="tel:${cleanPhone}" class="header-btn" style="padding: 6px 12px; font-size: 0.74rem;">📞 ${c.number}</a>
                    `;
                    hotlinesContainer.appendChild(row);
                });
            }
        }
    </script>
</body>
</html>
HTML_FOOTER

  File.write(File.join(LOCAL_TRAVEL_DIR, "index.html"), html_content, encoding: "UTF-8")
  puts "Successfully compiled single-file PWA: index.html (Version 5.4)"
  state_data
end

if __FILE__ == $0
  build_pwa!
end
