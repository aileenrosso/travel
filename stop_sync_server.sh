#!/bin/bash
PID=$(lsof -t -iTCP:8080 -sTCP:LISTEN 2>/dev/null)
if [ -n "$PID" ]; then
    kill $PID 2>/dev/null
    echo "🛑 Servidor Travel Planner detenido."
else
    echo "ℹ️ No había ningún servidor activo en el puerto 8080."
fi
