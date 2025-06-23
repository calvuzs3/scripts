# Q-DUE Events JSON Utilities

Collezione di utility ZSH per generare file JSON di eventi fermate compatibili con il sistema Q-DUE Events Android.

## 🚀 Utilities Disponibili

### 1. **qd-stop-events-generator.zsh** - Generator Completo
Utility principale per generazione interattiva e avanzata di eventi fermate.

### 2. **qd-qd-quick-stop.zsh** - Generator Rapido
Generazione veloce di fermate comuni con sintassi semplificata.

### 3. **qd-batch-stops.zsh** - Generator Batch
Generazione automatica di eventi ricorrenti (settimanali, mensili).

## 📋 Formato Eventi Supportati

### Tipi di Fermata
- **🚨 STOP_UNPLANNED** (`#D32F2F`) - Fermate non programmate/guasti
- **📦❌ STOP_SHORTAGE** (`#7B1FA2`) - Fermate per mancanza materiale
- **🔧 STOP_PLANNED** (`#1976D2`) - Fermate programmate/manutenzione
- **⚙️ MAINTENANCE** (`#388E3C`) - Manutenzione ordinaria

### Priorità
- **HIGH** - Priorità alta (rosso)
- **NORMAL** - Priorità normale (blu)
- **LOW** - Priorità bassa (grigio)

## 🛠️ Installazione

```bash
# Download delle utility
curl -O https://raw.githubusercontent.com/your-repo/qd-stop-events-generator.zsh
curl -O https://raw.githubusercontent.com/your-repo/qd-quick-stop.zsh  
curl -O https://raw.githubusercontent.com/your-repo/qd-batch-stops.zsh

# Rendi eseguibili
chmod +x *.zsh

# Opzionale: aggiungi al PATH
sudo ln -s $(pwd)/qd-stop-events-generator.sh /usr/local/bin/stop-events-generator
sudo ln -s $(pwd)/qd-quick-stop.sh /usr/local/bin/quick-stop
sudo ln -s $(pwd)/qd-batch-stops.zsh /usr/local/bin/batch-stops
```

### Dipendenze
- **ZSH** - Shell Zsh (macOS default, Linux: `sudo apt install zsh`)
- **jq** (opzionale) - Per validazione JSON (`brew install jq` / `sudo apt install jq`)

## 📖 Usage Guide

### 1. Generator Completo

#### Modalità Interattiva (Raccomandata)
```bash
./qd-stop-events-generator.sh fermate_settimana.json
```
Ti guida step-by-step nella creazione di eventi personalizzati.

#### Modalità Rapida
```bash
./qd-stop-events-generator.sh -q \
  --from 2025-06-15 --to 2025-06-21 \
  --package-name "Fermate Giugno" \
  --author "Team Manutenzione" \
  fermate_giugno.json
```

#### Templates Predefiniti
```bash
# Template fermata programmata
./qd-stop-events-generator.sh -t planned manutenzione_template.json

# Template emergenza  
./qd-stop-events-generator.sh -t unplanned emergenza_template.json

# Template shortage
./qd-stop-events-generator.sh -t shortage shortage_template.json

# Template manutenzione
./qd-stop-events-generator.sh -t maintenance manutenzione_template.json
```

### 2. Generator Rapido

#### Fermate di Emergenza
```bash
# Emergenza oggi, 4 ore
./qd-quick-stop.sh emergency 2025-06-15

# Emergenza con durata custom
./qd-quick-stop.sh emergency 2025-06-15 2h emergenza_breve.json
```

#### Mancanza Materiale
```bash
# Shortage di 2 giorni
./qd-quick-stop.sh shortage 2025-06-18 2d shortage_lungo.json

# Shortage di 6 ore
./qd-quick-stop.sh shortage 2025-06-17 6h
```

#### Manutenzioni
```bash
# Manutenzione 8 ore
./qd-quick-stop.sh maintenance 2025-06-20 8h

# Manutenzione settimanale standard
./qd-quick-stop.sh weekly 2025-06-16 4h manutenzione_settimanale.json
```

### 3. Generator Batch

#### Manutenzioni Settimanali
```bash
# 8 manutenzioni settimanali ogni lunedì
./qd-batch-stops.zsh weekly-maintenance 2025-06-16 8 manutenzioni_8sett.json
```

#### Manutenzioni Mensili
```bash
# 6 manutenzioni mensili (primo lunedì del mese)
./qd-batch-stops.zsh monthly-maintenance 2025-06-01 6 manutenzioni_mese.json
```

#### Cambi Turno Giornalieri
```bash
# 30 giorni di cambi turno
./qd-batch-stops.zsh shift-change 2025-06-15 30 cambi_turno_mese.json
```

#### Pulizie Weekend
```bash
# 12 pulizie weekend (ogni sabato)
./qd-batch-stops.zsh weekend-clean 2025-06-14 12 pulizie_weekend.json
```

#### Fermate Trimestrali
```bash
# 4 fermate trimestrali maggiori
./qd-batch-stops.zsh quarterly-stop 2025-06-01 4 fermate_trimestrali.json
```

## 📁 Esempi di Output

### Struttura JSON Generata
```json
{
  "package_info": {
    "id": "fermate_produzione_20250615",
    "name": "Eventi Fermate Produzione",
    "version": "1.0.0", 
    "description": "Pacchetto eventi fermate produzione",
    "created_date": "2025-06-15T14:30:22+02:00",
    "valid_from": "2025-06-15",
    "valid_to": "2025-06-30",
    "author": "Sistema Produzione",
    "contact_email": "produzione@company.com"
  },
  "events": [
    {
      "id": "stop_unplanned_001",
      "title": "🚨 Guasto Motore Principale",
      "description": "Fermata immediata per guasto al motore principale linea A",
      "start_date": "2025-06-15",
      "end_date": "2025-06-15",
      "start_time": "14:30",
      "end_time": "18:00", 
      "all_day": false,
      "event_type": "STOP_UNPLANNED",
      "priority": "HIGH",
      "location": "Stabilimento Nord - Linea A",
      "tags": ["guasto", "motore", "urgente"],
      "custom_properties": {
        "department": "Produzione",
        "affected_lines": "A",
        "estimated_cost": "5000",
        "repair_priority": "immediata"
      }
    }
  ]
}
```

## 🎯 Casos d'Uso Comuni

### Pianificazione Settimanale
```bash
# 1. Genera manutenzioni settimanali per 2 mesi
./qd-batch-stops.zsh weekly-maintenance 2025-06-16 8

# 2. Aggiungi fermate per shortage previste  
./qd-quick-stop.sh shortage 2025-06-18 1d
./qd-quick-stop.sh shortage 2025-06-25 6h

# 3. Crea evento manutenzione straordinaria
./qd-stop-events-generator.sh -t maintenance manutenzione_straordinaria.json
```

### Gestione Emergenze
```bash
# Fermata emergenza immediata
./qd-quick-stop.sh emergency $(date +%Y-%m-%d) 3h

# Con dettagli personalizzati via generator completo
./qd-stop-events-generator.sh -i emergenza_dettagliata.json
```

### Setup Nuovo Impianto
```bash
# Genera calendario completo primo anno
./qd-batch-stops.zsh weekly-maintenance 2025-01-06 52 manutenzioni_2025.json
./qd-batch-stops.zsh monthly-maintenance 2025-01-01 12 manutenzioni_mensili_2025.json
./qd-batch-stops.zsh quarterly-stop 2025-01-01 4 fermate_trimestrali_2025.json
```

## ⚙️ Configurazione Avanzata

### Personalizzazione Defaults
Modifica le variabili di default negli script:

```bash
# In qd-stop-events-generator.sh
DEFAULT_PACKAGE_NAME="La Tua Azienda - Eventi Fermate"
DEFAULT_AUTHOR="Team Produzione"
DEFAULT_EMAIL="produzione@tuaazienda.com"

# In qd-quick-stop.sh  
DEFAULT_DURATION="4h"
DEFAULT_START_TIME="08:00"
```

### Custom Properties
Ogni evento generato include proprietà personalizzate utili per tracking:

```json
"custom_properties": {
  "department": "Manutenzione",
  "generated_by": "stop_events_generator", 
  "generation_time": "2025-06-15T14:30:22+02:00",
  "estimated_duration": "4 ore",
  "cost_center": "MAINT_001",
  "technician_assigned": "Mario Rossi"
}
```

## 🔧 Troubleshooting

### Errore: "Formato data non valido"
```bash
# ❌ Sbagliato
./qd-quick-stop.sh emergency 15/06/2025

# ✅ Corretto  
./qd-quick-stop.sh emergency 2025-06-15
```

### Errore: "jq: command not found"
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# CentOS/RHEL
sudo yum install jq
```

### Problema Permessi
```bash
# Rendi eseguibile lo script
chmod +x qd-stop-events-generator.sh

# Se hai errori di shell
#!/usr/bin/env zsh
```

### Validazione JSON
```bash
# Verifica manualmente il JSON generato
jq empty fermate.json && echo "✅ JSON valido" || echo "❌ JSON non valido"

# Pretty print
jq . fermate.json
```

## 📱 Import in Q-DUE Android

### Via File Manager
1. Copia il file JSON generato su dispositivo Android
2. Apri Q-DUE Events app
3. Menu → Import Events
4. Seleziona il file JSON
5. Conferma import

### Via Intent
```bash
# Invia file via ADB per testing
adb push fermate.json /sdcard/Download/
adb shell am start -a android.intent.action.VIEW -d "file:///sdcard/Download/fermate.json" -t "application/json"
```

### Via Cloud Storage
1. Upload su Google Drive/Dropbox
2. Condividi link pubblico
3. Download diretto in app Q-DUE
4. Import automatico

## 🔄 Automazione

### Cron Jobs per Generazione Automatica
```bash
# Genera manutenzioni settimanali ogni domenica
0 20 * * 0 /path/to/qd-batch-stops.zsh weekly-maintenance $(date -d "next monday" +%Y-%m-%d) 4 /path/to/output/manutenzioni_$(date +%Y%m%d).json

# Backup degli eventi generati
0 1 * * * cp /path/to/generated/*.json /backup/events/
```

### Script di Deploy Automatico
```bash
#!/bin/bash
# auto-deploy-events.sh

DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="/events/generated"

# Genera eventi della settimana
./qd-batch-stops.zsh weekly-maintenance $DATE 1 $OUTPUT_DIR/weekly_$DATE.json

# Upload automatico a server
rsync -av $OUTPUT_DIR/ user@server:/events/incoming/

# Notifica via webhook
curl -X POST https://api.company.com/events/webhook \
  -H "Content-Type: application/json" \
  -d "{\"message\": \"New events generated for $DATE\"}"
```

## 📊 Statistiche e Monitoraggio

### Conteggio Eventi Generati
```bash
# Conta eventi in un file JSON
jq '.events | length' fermate.json

# Statistiche per tipo
jq '.events | group_by(.event_type) | map({type: .[0].event_type, count: length})' fermate.json
```

### Report Durata Fermate
```bash
# Estrai durate per analisi
jq -r '.events[] | [.title, .custom_properties.estimated_duration] | @csv' fermate.json
```

## 🚀 Best Practices

### Naming Convention
```bash
# Format raccomandato: tipo_YYYYMMDD_descrizione.json
weekly_20250615_manutenzioni.json
emergency_20250615_guasto_motore.json
batch_monthly_20250601_trimestre2.json
```

### Organizzazione File
```
events/
├── templates/           # Template predefiniti
├── generated/          # Eventi generati
│   ├── weekly/        # Manutenzioni settimanali
│   ├── monthly/       # Manutenzioni mensili  
│   ├── emergency/     # Emergenze
│   └── batch/         # Eventi batch
├── archive/           # Archivio eventi passati
└── scripts/           # Utility personalizzate
```

### Validazione Pre-Import
```bash
# Script di validazione custom
validate_events() {
    local file="$1"
    
    # Check JSON syntax
    jq empty "$file" || return 1
    
    # Check required fields
    jq -e '.package_info.id and .events[].id' "$file" >/dev/null || return 1
    
    # Check date formats
    jq -r '.events[].start_date' "$file" | while read date; do
        [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
    done
    
    echo "✅ Validation passed"
}

validate_events fermate.json
```

## 🎯 Roadmap Features

### Planned Enhancements
- [ ] **GUI Version** - Interfaccia grafica per non-tecnici
- [ ] **API Integration** - Connessione diretta con sistemi ERP
- [ ] **Template Editor** - Editor visuale per template custom
- [ ] **Calendar Import** - Import da Google Calendar/Outlook
- [ ] **Cost Calculator** - Calcolo automatico costi fermate
- [ ] **Notification System** - Alert automatici pre-fermata

### Advanced Features
- [ ] **Machine Learning** - Previsione fermate basata su storico
- [ ] **Integration SAP** - Connessione sistemi SAP
- [ ] **Mobile App** - App dedicata per supervisori
- [ ] **Dashboard Analytics** - Analytics avanzate fermate
- [ ] **Multi-language** - Supporto multilingua

---

## 📞 Support

### Bug Reports
Segnala problemi creando issue su GitHub con:
- Versione script utilizzata
- Comando eseguito
- Output di errore completo
- File JSON problematico (se applicabile)

### Feature Requests
Suggerisci nuove funzionalità descrivendo:
- Caso d'uso specifico
- Benefici attesi
- Esempi di utilizzo

### Community
- **Forum**: https://forum.qdue-events.com
- **Telegram**: @qdue_events_support
- **Email**: support@qdue-events.com

---

## 📄 Licenza

MIT License - Libero uso per progetti commerciali e open source.

## 🙏 Contributing

Contributi benvenuti! Fork del repository e pull request per miglioramenti.

**Happy Event Generation! 🎉**