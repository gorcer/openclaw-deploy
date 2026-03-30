#!/bin/bash
# Health check script for vpn2 (144.31.241.121)
# Checks: Xray, Marzban, Nginx, Docker, general system health

HOST="root@144.31.241.121"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
ALERT=""
OK=0
WARN=0
FAIL=0

echo "╔══════════════════════════════════════════════════════╗"
echo "║       VPN2 Health Check — $DATE     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $HOST << 'EOF'
# 1. System load
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
LOAD_INT=$(echo "$LOAD" | cut -d. -f1)
echo "▸ System load: $LOAD"
if [ "$LOAD_INT" -gt 4 ]; then
    echo "  ⚠️  HIGH LOAD"
else
    echo "  ✅ OK"
fi

# 2. Disk space
DISK=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
echo "▸ Disk /: ${DISK}%"
if [ "$DISK" -gt 90 ]; then
    echo "  ❌ CRITICAL - disk almost full!"
else
    echo "  ✅ OK"
fi

# 3. Memory
MEM_PCT=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
echo "▸ Memory: ${MEM_PCT}%"
if [ "$MEM_PCT" -gt 90 ]; then
    echo "  ❌ CRITICAL"
else
    echo "  ✅ OK"
fi

# 4. Xray (main VPN service)
echo ""
echo "▸ Xray (VPN) — ports 20463, 443:"
XRAY_PID=$(pgrep -x xray 2>/dev/null)
if [ -n "$XRAY_PID" ]; then
    echo "  ✅ Running (PID: $XRAY_PID)"
    ss -tlnp | grep xray | grep -v grep | awk '{print "     ↳ "$4" → "$5}'
else
    echo "  ❌ NOT RUNNING!"
fi

# 5. Xray API (Marzban connects via API)
echo ""
echo "▸ Xray API port 20463:"
if ss -tlnp | grep -q "127.0.0.1:20463"; then
    echo "  ✅ Listening"
else
    echo "  ❌ NOT LISTENING"
fi

# 6. Marzban
echo ""
echo "▸ Marzban:"
MARZBAN=$(docker ps --filter name=marzban-marzban --format '{{.Status}}' 2>/dev/null)
if docker ps --filter name=marzban-marzban --format '{{.Names}}' 2>/dev/null | grep -q marzban; then
    echo "  ✅ Container running"
    docker ps --filter name=marzban --format '    ↳ {{.Names}} — {{.Status}}'
else
    echo "  ❌ NOT RUNNING"
fi

# 7. Nginx
echo ""
echo "▸ Nginx:"
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo "  ✅ Running"
else
    echo "  ❌ NOT RUNNING"
fi

# 8. Docker
echo ""
echo "▸ Docker:"
if systemctl is-active --quiet docker 2>/dev/null; then
    echo "  ✅ Running"
    docker ps --format '    ↳ {{.Names}} — {{.Status}}' | head -5
else
    echo "  ❌ NOT RUNNING"
fi

# 9. External connectivity
echo ""
echo "▸ Internet connectivity:"
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "  ✅ Internet OK"
else
    echo "  ❌ NO INTERNET"
fi

# 10. VPN specific — check if xray is actually proxying
echo ""
echo "▸ VPN port 443 check:"
if ss -tlnp | grep -q ":443" && pgrep -x xray &>/dev/null; then
    echo "  ✅ VPN port 443 open"
else
    echo "  ❌ VPN port 443 issue"
fi

# 11. CPU temperature (if available)
echo ""
echo "▸ CPU temperature:"
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    TEMP_C=$((TEMP / 1000))
    echo "  🌡️  ${TEMP_C}°C"
    if [ "$TEMP_C" -gt 80 ]; then
        echo "  ⚠️  HIGH TEMPERATURE!"
    fi
else
    echo "  ⬜ Not available"
fi
EOF

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Check completed: $(date '+%Y-%m-%d %H:%M:%S')"
