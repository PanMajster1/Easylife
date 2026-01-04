#!/bin/bash
# ==========================================
# EASYLIFE OS - AKTUALIZATOR
# ==========================================

echo "⬇️  Pobieranie aktualizacji z GitHub..."
git fetch --all
git reset --hard origin/main
chmod +x infrastructure/*.sh

echo "🗄  Aktualizacja bazy..."
./infrastructure/db_migrator.sh

ID_HUB=102
ID_GOLDTRACK=105

echo "🔄 Hub Update..."
pct push $ID_HUB hub/package.json /opt/easylife/hub/package.json
pct push $ID_HUB hub/server.js /opt/easylife/hub/server.js
tar -cf v.tar -C hub views; pct push $ID_HUB v.tar /opt/easylife/hub/v.tar; pct exec $ID_HUB -- tar -xf /opt/easylife/hub/v.tar -C /opt/easylife/hub/; rm v.tar
pct exec $ID_HUB -- bash -c "cd /opt/easylife/hub && npm install --production"
pct exec $ID_HUB -- pm2 restart hub

if pct status $ID_GOLDTRACK >/dev/null 2>&1; then
    echo "🔄 GoldTrack Update..."
    pct push $ID_GOLDTRACK apps/goldtrack/app.py /opt/goldtrack/app.py
    pct push $ID_GOLDTRACK apps/goldtrack/requirements.txt /opt/goldtrack/requirements.txt
    tar -cf t.tar -C apps/goldtrack templates; pct push $ID_GOLDTRACK t.tar /opt/goldtrack/t.tar; pct exec $ID_GOLDTRACK -- tar -xf /opt/goldtrack/t.tar -C /opt/goldtrack/; rm t.tar
    pct exec $ID_GOLDTRACK -- bash -c "cd /opt/goldtrack && source venv/bin/activate && pip install -r requirements.txt"
    pct exec $ID_GOLDTRACK -- rc-service goldtrack restart
fi

echo "✅ System zaktualizowany!"