#!/bin/bash
# ==========================================
# EASYLIFE OS - GŁÓWNY INSTALATOR
# ==========================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}   EASYLIFE OS - KREATOR SYSTEMU          ${NC}"
echo -e "${BLUE}==========================================${NC}"

# 1. SZABLON ALPINE
LOCAL_TEMPLATE=$(pveam list local | grep "alpine-" | sort -r | head -n 1 | awk '{print $2}')
if [ -z "$LOCAL_TEMPLATE" ]; then
    echo -e "${YELLOW}Pobieranie szablonu Alpine Linux...${NC}"
    pveam update > /dev/null
    REMOTE_TEMPLATE=$(pveam available | grep "alpine-" | grep "standard" | sort -r | head -n 1 | awk '{print $2}')
    pveam download local $REMOTE_TEMPLATE
    TEMPLATE="local:vztmpl/$REMOTE_TEMPLATE"
else
    TEMPLATE="local:vztmpl/$(basename $LOCAL_TEMPLATE)"
fi

# 2. KONFIGURACJA SIECI
echo ""
while [[ ! $GATEWAY_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
    read -p "Podaj IP routera (np. 192.168.1.1): " GATEWAY_IP
done
SUBNET_PREFIX=$(echo $GATEWAY_IP | cut -d'.' -f1-3)
echo -e "Podsieć: ${GREEN}${SUBNET_PREFIX}.x${NC}"

# 3. HASŁO
echo ""
while [ -z "$PASSWORD" ]; do
    read -s -p "Ustaw hasło root dla kontenerów: " PASSWORD
    echo ""
    read -s -p "Powtórz hasło: " PASSWORD_CONFIRM
    echo ""
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then echo "Hasła nie pasują!"; PASSWORD=""; fi
done

# 4. WYBÓR APLIKACJI
echo ""
INSTALL_GOLDTRACK=false
read -p "Zainstalować GoldTrack (Finanse)? [t/N]: " gt_choice
if [[ "$gt_choice" =~ ^[TtYy]$ ]]; then INSTALL_GOLDTRACK=true; fi

# ADRESACJA
STORAGE="local-lvm"
ID_GATEWAY=100; IP_GATEWAY="${SUBNET_PREFIX}.100"
ID_DB=101;      IP_DB="${SUBNET_PREFIX}.101"
ID_HUB=102;     IP_HUB="${SUBNET_PREFIX}.102"
ID_GOLDTRACK=105; IP_GOLDTRACK="${SUBNET_PREFIX}.105"

declare -A MAC_ADDRESSES

# --- FUNKCJE ---

check_ip_free() {
    if ping -c 1 -W 1 $1 >/dev/null 2>&1; then
        echo -e "${RED}⛔ BŁĄD: IP $1 jest zajęte! Przerwanie instalacji.${NC}"
        exit 1
    fi
}

create_ct() {
    local ID=$1; local NAME=$2; local IP=$3
    echo -e "${BLUE}🔨 [$NAME] Tworzenie kontenera...${NC}"
    if ! pct status $ID >/dev/null 2>&1; then
        echo "   Sprawdzanie dostępności IP..."
        check_ip_free $IP
        pct create $ID $TEMPLATE --hostname $NAME --storage $STORAGE --password $PASSWORD \
            --net0 name=eth0,bridge=vmbr0,ip=$IP/24,gw=$GATEWAY_IP \
            --cores 1 --memory 512 --swap 256 --features nesting=1 --unprivileged 1 --start 1
        sleep 5
        pct exec $ID -- apk update
        pct exec $ID -- apk add bash curl
    else
        echo "   Kontener już istnieje."
    fi
    MAC_ADDRESSES[$NAME]=$(pct config $ID | grep -oE '([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})')
}

add_nginx_proxy() {
    local APP=$1; local IP=$2; local PORT=$3; local DOMAIN="${APP,,}.local"
    cat > ${APP}.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://$IP:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    pct push $ID_GATEWAY ${APP}.conf /etc/nginx/http.d/${APP}.conf
    rm ${APP}.conf
    pct exec $ID_GATEWAY -- rc-service nginx reload
}

# --- INSTALACJA ---

# GATEWAY
create_ct $ID_GATEWAY "easylife-gateway" $IP_GATEWAY
pct exec $ID_GATEWAY -- apk add nginx
pct exec $ID_GATEWAY -- rc-update add nginx default
pct exec $ID_GATEWAY -- rm -f /etc/nginx/http.d/default.conf
pct exec $ID_GATEWAY -- rc-service nginx start

# DATABASE
create_ct $ID_DB "easylife-db" $IP_DB
pct exec $ID_DB -- apk add postgresql postgresql-contrib
pct exec $ID_DB -- mkdir -p /run/postgresql && chown postgres:postgres /run/postgresql
pct exec $ID_DB -- su - postgres -c "initdb -D /var/lib/postgresql/data" > /dev/null
pct exec $ID_DB -- sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/postgresql/data/postgresql.conf
pct exec $ID_DB -- bash -c "echo \"host all all ${SUBNET_PREFIX}.0/24 md5\" >> /var/lib/postgresql/data/pg_hba.conf"
pct exec $ID_DB -- rc-service postgresql start
sleep 3
pct exec $ID_DB -- su - postgres -c "psql -c \"CREATE USER postgres_root WITH PASSWORD '$PASSWORD';\""
pct exec $ID_DB -- su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$PASSWORD';\""
pct exec $ID_DB -- su - postgres -c "createdb easylife_db"

# Uruchom migrator
chmod +x "$(dirname "$0")/db_migrator.sh"
"$(dirname "$0")/db_migrator.sh"

# HUB
create_ct $ID_HUB "easylife-hub" $IP_HUB
pct exec $ID_HUB -- apk add nodejs npm git openssh-client
# SSH Trust
pct exec $ID_HUB -- mkdir -p /root/.ssh
if ! pct exec $ID_HUB -- ls /root/.ssh/id_rsa >/dev/null 2>&1; then
    pct exec $ID_HUB -- ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
fi
pct exec $ID_HUB -- cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys

# Pliki Huba
pct exec $ID_HUB -- mkdir -p /opt/easylife/hub
pct push $ID_HUB ../hub/package.json /opt/easylife/hub/package.json
pct push $ID_HUB ../hub/server.js /opt/easylife/hub/server.js
cat > .env.temp <<EOF
PORT=80
DB_HOST=$IP_DB
DB_USER=postgres
DB_PASS=$PASSWORD
DB_NAME=easylife_db
JWT_SECRET=secret_$(date +%s)
EOF
pct push $ID_HUB .env.temp /opt/easylife/hub/.env; rm .env.temp
tar -cf v.tar -C ../hub views; pct push $ID_HUB v.tar /opt/easylife/hub/v.tar; pct exec $ID_HUB -- tar -xf /opt/easylife/hub/v.tar -C /opt/easylife/hub/; rm v.tar
tar -cf p.tar -C ../hub public; pct push $ID_HUB p.tar /opt/easylife/hub/p.tar; pct exec $ID_HUB -- tar -xf /opt/easylife/hub/p.tar -C /opt/easylife/hub/; rm p.tar

pct exec $ID_HUB -- bash -c "cd /opt/easylife/hub && npm install && npm install -g pm2"
pct exec $ID_HUB -- bash -c "cd /opt/easylife/hub && pm2 start server.js --name hub"
pct exec $ID_HUB -- rc-update add pm2-root default
add_nginx_proxy "hub" $IP_HUB 80

# GOLDTRACK
if [ "$INSTALL_GOLDTRACK" = true ]; then
    create_ct $ID_GOLDTRACK "goldtrack" $IP_GOLDTRACK
    pct exec $ID_GOLDTRACK -- apk add python3 py3-pip py3-virtualenv
    pct exec $ID_GOLDTRACK -- mkdir -p /opt/goldtrack
    pct push $ID_GOLDTRACK ../apps/goldtrack/requirements.txt /opt/goldtrack/requirements.txt
    pct push $ID_GOLDTRACK ../apps/goldtrack/app.py /opt/goldtrack/app.py
    
    cat > .env.gt <<EOF
DB_HOST=$IP_DB
DB_NAME=easylife_db
DB_USER=postgres
DB_PASS=$PASSWORD
SHARED_SECRET=$(pct exec $ID_HUB -- cat /opt/easylife/hub/.env | grep JWT_SECRET | cut -d'=' -f2)
EOF
    pct push $ID_GOLDTRACK .env.gt /opt/goldtrack/.env; rm .env.gt
    tar -cf t.tar -C ../apps/goldtrack templates; pct push $ID_GOLDTRACK t.tar /opt/goldtrack/t.tar; pct exec $ID_GOLDTRACK -- tar -xf /opt/goldtrack/t.tar -C /opt/goldtrack/; rm t.tar
    
    pct exec $ID_GOLDTRACK -- bash -c "cd /opt/goldtrack && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    
    # Init script
    cat > gt.init <<EOF
#!/sbin/openrc-run
name="goldtrack"
command="/opt/goldtrack/venv/bin/gunicorn"
command_args="-w 2 -b 0.0.0.0:3000 app:app"
directory="/opt/goldtrack"
command_background=true
pidfile="/run/goldtrack.pid"
EOF
    pct push $ID_GOLDTRACK gt.init /etc/init.d/goldtrack
    pct exec $ID_GOLDTRACK -- chmod +x /etc/init.d/goldtrack
    pct exec $ID_GOLDTRACK -- rc-update add goldtrack default
    pct exec $ID_GOLDTRACK -- rc-service goldtrack start
    add_nginx_proxy "goldtrack" $IP_GOLDTRACK 3000
fi

echo ""
echo -e "${GREEN}INSTALACJA ZAKOŃCZONA!${NC}"
echo "Gateway IP: $IP_GATEWAY -> Ustaw DNS/Hosts na: hub.local, goldtrack.local"