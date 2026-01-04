# Easylife OS ☁️

**Easylife** to prywatny, modułowy system operacyjny ("Home Cloud") działający na platformie wirtualizacji Proxmox VE. System automatyzuje zarządzanie domowymi aplikacjami przy użyciu architektury mikroserwisów (LXC) i centralnego panelu zarządzania.

> **Cel:** Jedno miejsce do zarządzania finansami, domem i usługami, dostępne z każdego urządzenia w sieci, bez konieczności logowania się do każdej aplikacji osobno.

---

## 🏗 Architektura Systemu

System nie jest jedną wielką aplikacją, lecz zbiorem lekkich, niezależnych kontenerów (Alpine Linux), które komunikują się ze sobą.

### Elementy Rdzenia (Core)

| ID | Usługa | Opis Funkcji | Technologie |
| :--- | :--- | :--- | :--- |
| **100** | **Gateway** | **Brama Wejściowa.** Przyjmuje ruch z przeglądarki (np. `hub.local`, `goldtrack.local`) i kieruje go do odpowiedniego kontenera. | Nginx Proxy |
| **101** | **Database** | **Centralny Magazyn.** Przechowuje dane użytkowników, konfigurację systemu oraz dane wszystkich zainstalowanych aplikacji. | PostgreSQL 15 |
| **102** | **Hub** | **Panel Sterowania (Mózg).** To tutaj się logujesz. Zarządza aplikacjami, wyświetla Dashboard i pełni rolę serwera autoryzacji (SSO). Posiada uprawnienia do tworzenia nowych kontenerów na Proxmoxie. | Node.js, Express |

### Dostępne Aplikacje (Modules)

#### 💰 GoldTrack (ID: 105)
Zaawansowany system do śledzenia wartości majątku w metalach szlachetnych.
* **Wycena Live:** Pobiera kursy XAU/USD (giełda) i USD/PLN (NBP) w czasie rzeczywistym.
* **Portfel:** Pozwala dodawać posiadane sztabki/monety i oblicza ich aktualną wartość skupu w mennicy.
* **Analityka:** Algorytm SMA-50 (średnia krocząca) sugeruje, czy to dobry moment na kupno ("OKAZJA"), czy sprzedaż.
* **Wykresy:** Zintegrowany wykres TradingView.

---

## 🛡 Bezpieczeństwo i Sieć (Ważne!)

System operuje na **statycznych adresach IP**, aby zapewnić stabilną komunikację między kontenerami. Domyślna konfiguracja zajmuje blok adresów (zazwyczaj od `.100` w górę).

### ⚠️ Zapobieganie Konfliktom IP
Przed instalacją upewnij się, że adresy, które system chce zająć (np. `192.168.1.100` - `192.168.1.105`) są **WOLNE** w Twojej sieci domowej.

**Skrypt instalacyjny posiada wbudowany bezpiecznik:** Przed utworzeniem kontenera wykonuje test (ping). Jeśli wykryje, że adres jest zajęty przez inne urządzenie (np. TV, Telefon), **przerwie instalację**, aby nie zepsuć Twojej sieci.

---

## 🚀 Instrukcja Instalacji (Krok po Kroku)

### 1. Wymagania
* Serwer z zainstalowanym **Proxmox VE (8.x)**.
* Dostęp do powłoki (Shell) użytkownika `root`.
* Router z możliwością ustawienia "Static DHCP" (Rezerwacji adresów) - zalecane.

### 2. Pobranie Systemu
Zaloguj się przez SSH na Proxmox i pobierz repozytorium:
```bash
git clone [https://github.com/PanMajster1/Easylife.git](https://github.com/PanMajster1/Easylife.git)
cd Easylife/infrastructure
./install_full.sh

🔄 Jak aktualizować?

Aby pobrać nową wersję z GitHub i zaktualizować system bez utraty danych:
Bash

cd Easylife
./infrastructure/update_system.sh