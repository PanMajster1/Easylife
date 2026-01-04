#!/bin/bash
# SKRYPT WEWNĘTRZNY - URUCHAMIANY PRZEZ INSTALATOR LUB UPDATER

ID_DB=101
DB_NAME="easylife_db"
# Ścieżka względna do folderu migrations
MIGRATIONS_DIR="$(dirname "$0")/../setup/migrations"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 [DB] Weryfikacja migracji bazy danych...${NC}"

# Upewnij się, że tabela wersji istnieje
pct exec $ID_DB -- su - postgres -c "psql -d $DB_NAME -c 'CREATE TABLE IF NOT EXISTS _schema_version (version_id INT PRIMARY KEY, script_name VARCHAR(255), applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);'" > /dev/null 2>&1

# Pobierz listę już wykonanych migracji
APPLIED=$(pct exec $ID_DB -- su - postgres -c "psql -d $DB_NAME -t -c 'SELECT script_name FROM _schema_version'")

# Pętla po plikach SQL
for file in $(ls $MIGRATIONS_DIR | sort); do
    if echo "$APPLIED" | grep -q "$file"; then
        continue # Już zrobione
    else
        echo -e "${GREEN}🚀 Wykonuję migrację: $file ${NC}"
        pct push $ID_DB $MIGRATIONS_DIR/$file /tmp/migration.sql
        
        # Wykonaj SQL
        pct exec $ID_DB -- su - postgres -c "psql -d $DB_NAME -f /tmp/migration.sql"
        
        if [ $? -eq 0 ]; then
            # Zapisz sukces
            VER_ID=$(echo $file | grep -oE '^[0-9]+' | sed 's/^0*//')
            pct exec $ID_DB -- su - postgres -c "psql -d $DB_NAME -c \"INSERT INTO _schema_version (version_id, script_name) VALUES ($VER_ID, '$file');\""
            echo "   ✅ Sukces."
        else
            echo "   ❌ BŁĄD KRYTYCZNY MIGRACJI. Stop."
            exit 1
        fi
    fi
done
echo -e "${BLUE}🏁 Baza danych jest zsynchronizowana.${NC}"