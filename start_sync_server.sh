#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"
if lsof -iTCP:8080 -sTCP:LISTEN -n -P > /dev/null 2>&1; then
    echo "✅ Servidor Travel Planner ya está activo en http://localhost:8080"
else
    echo "🚀 Iniciando Servidor Travel Planner & OneDrive Watcher..."
    nohup ruby server.rb > server.log 2>&1 &
    sleep 1
    echo "✅ Servidor activo en http://localhost:8080"
fi
