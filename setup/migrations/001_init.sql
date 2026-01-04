-- Tabela techniczna do śledzenia wersji (NIE USUWAĆ!)
CREATE TABLE IF NOT EXISTS _schema_version (
    version_id INT PRIMARY KEY,
    script_name VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 1. Użytkownicy (Wspólna tabela)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Aplikacje (Zarządzane przez Hub)
CREATE TABLE IF NOT EXISTS apps (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    url VARCHAR(255) NOT NULL,
    icon VARCHAR(50) DEFAULT 'box',
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE
);

-- 3. GoldTrack (Finanse)
CREATE TABLE IF NOT EXISTS gold_items (
    id SERIAL PRIMARY KEY,
    typ VARCHAR(50),
    producent VARCHAR(100),
    waga_g NUMERIC(10, 2),
    data_zakupu DATE,
    cena_zakupu NUMERIC(10, 2),
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE
);

-- Dodaj GoldTrack do listy aplikacji
INSERT INTO apps (name, url, icon, description) 
VALUES ('GoldTrack', 'http://goldtrack.local', 'gold', 'Finanse i Metale Szlachetne')
ON CONFLICT DO NOTHING;

-- Zarejestruj wykonanie migracji nr 1
INSERT INTO _schema_version (version_id, script_name) VALUES (1, '001_init.sql') ON CONFLICT DO NOTHING;