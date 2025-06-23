# ZFS Management Script

Script bash avanzato per la gestione automatizzata di snapshot ZFS e Boot Environment con integrazione rEFInd per sistemi Arch Linux.

## 🎯 Caratteristiche Principali

### 📸 Snapshot Automation
- **Creazione automatica** di snapshot con retention policy configurabile
- **Pulizia intelligente** degli snapshot vecchi mantenendo quelli di sistema
- **Protezione snapshot** critici (beta, produzione, recovery)
- **Logging dettagliato** di tutte le operazioni

### 🧪 Sistema Beta/Testing
- **Clonazione sicura** dei dataset di produzione
- **Test isolato** delle modifiche senza impatto sulla produzione  
- **Promozione controllata** delle modifiche testate
- **Rollback rapido** in caso di problemi

### 🚀 Boot Environment (rEFInd)
- **Creazione automatica** di Boot Environment da snapshot
- **Integrazione nativa** con bootloader rEFInd
- **Recovery automatico** con modalità rescue
- **Aggiornamenti sicuri** del sistema con rollback automatico

## 📋 Requisiti

- **Sistema Operativo**: Arch Linux con root su ZFS
- **Bootloader**: rEFInd configurato e funzionante
- **ZFS**: Moduli ZFS installati e caricati
- **Privilegi**: Accesso root (sudo)
- **Spazio**: Sufficiente spazio libero nel pool ZFS per snapshot e cloni

## 🛠️ Installazione

1. **Scarica lo script**
   ```bash
   wget https://example.com/zfs_management.sh
   chmod +x zfs_management.sh
   ```

2. **Configura le variabili** (se necessario)
   ```bash
   # Modifica le impostazioni all'inizio dello script
   POOL="zcalvuz"                    # Nome del pool ZFS
   DATASETS=("ROOT/calvuz" "data/home" "data/srv" "data/docker" "data/media")
   RETENTION_DAYS=30                 # Giorni di retention snapshot
   MAX_SNAPSHOTS=10                  # Numero massimo snapshot per dataset
   ```

3. **Test iniziale**
   ```bash
   sudo ./zfs_management.sh -h
   sudo ./zfs_management.sh s    # Verifica stato
   ```

## 🎮 Utilizzo

### Modalità Interattiva (Raccomandata)
```bash
sudo ./zfs_management.sh
```
Avvia il menu interattivo completo con tutte le funzioni disponibili.

### Modalità Command Line
```bash
# Automazione completa (ideale per cron)
sudo ./zfs_management.sh auto

# Solo creazione snapshot
sudo ./zfs_management.sh create

# Solo pulizia snapshot vecchi
sudo ./zfs_management.sh cleanup

# Modalità verbose
sudo ./zfs_management.sh -v auto
```

### Automazione con Cron
```bash
# Aggiungi a crontab per esecuzione automatica
crontab -e

# Esempio: automazione quotidiana alle 2:00
0 2 * * * /path/to/zfs_management.sh auto

# Esempio: pulizia settimanale domenica alle 3:00
0 3 * * 0 /path/to/zfs_management.sh cleanup
```

## 📁 Struttura del Sistema

### Dataset Organization
```
zcalvuz/
├── ROOT/
│   ├── calvuz              # Sistema principale
│   ├── BE-*               # Boot Environment
│   ├── betacalvuz         # Sistema beta (testing)
│   ├── legacycalvuz       # Sistema legacy (pre-update)
│   └── backup-*           # Backup automatici
└── data/
    ├── home               # Home directory
    ├── srv                # Server data
    ├── docker             # Container data
    ├── media              # Media files
    ├── betahome           # Beta versions
    └── legacy*            # Legacy versions
```

### Snapshot Naming Convention
- **Automatici**: `dataset@auto-YYYY-MM-DD_HH-MM-SS`
- **Sistema**: `dataset@snapshot-YYYYMMDD`
- **Pre-update**: `dataset@pre-update-YYYYMMDD-HHMMSS`
- **Recovery**: `dataset@pre-recovery-YYYYMMDD-HHMMSS`

## 🔧 Configurazione rEFInd

Lo script configura automaticamente rEFInd per gestire i Boot Environment:

### File Modificati
- **`/boot/EFI/BOOT/refind.conf`**: Configurazione principale
- **`/boot/EFI/BOOT/refind-bootenvs.conf`**: Entry Boot Environment (auto-gestito)
- **`/boot/EFI/BOOT/refind.conf.backup`**: Backup configurazione originale

### Entry Automatiche
- **Sistema principale**: Entry standard di Arch Linux
- **Boot Environment**: Entry per ogni BE creato  
- **Recovery**: Modalità rescue con opzioni di debug
- **Rollback**: Sistemi di backup precedenti

## 🔄 Workflow Tipico

### 1. Preparazione Aggiornamento
```bash
sudo ./zfs_management.sh
# Opzione U: Prepara aggiornamento sicuro
```

### 2. Aggiornamento Sistema
```bash
sudo pacman -Syu
sudo reboot
```

### 3. Verifica e Cleanup
```bash
sudo ./zfs_management.sh
# Opzione 7: Verifica post-aggiornamento
# Opzione 8: Pulizia ambienti temporanei (se tutto OK)
```

## 🛡️ Sicurezza e Recovery

### Protezioni Implementate
- **Snapshot di sicurezza** automatici prima di operazioni critiche
- **Backup configurazione** rEFInd prima di modifiche
- **Verifica integrità** dataset prima di operazioni distruttive
- **Conferma utente** per operazioni irreversibili

### Opzioni di Recovery
1. **Menu rEFInd**: Selezione BE di recovery al boot
2. **Rollback automatico**: Attivazione BE precedente
3. **Recovery mode**: Boot in modalità rescue con debug
4. **Live USB rescue**: Importazione pool e chroot

## 📊 Logging e Monitoraggio

### File di Log
- **Posizione**: `/var/log/zfs-management.log`
- **Rotazione**: Automatica quando supera 10MB
- **Formato**: Timestamp + operazione + risultato

### Modalità Verbose
```bash
# Attiva output dettagliato
sudo ./zfs_management.sh -v

# Toggle verbose nel menu interattivo
# Opzione 'v' per attivare/disattivare
```

## ⚙️ Opzioni del Menu

### Snapshot Automation
- **1**: Crea snapshot automatici
- **2**: Pulisci snapshot automatici vecchi  
- **3**: Automazione completa (crea + pulisci)
- **P**: PURGE - Elimina TUTTI gli snapshot automatici

### Beta System
- **4**: Crea snapshot di produzione
- **5**: Popola dataset beta
- **6**: Promuovi beta
- **7**: Sposta beta in produzione
- **8**: Elimina dataset legacy
- **9**: Elimina dataset beta

### Boot Environment
- **B**: Lista Boot Environment
- **N**: Crea nuovo Boot Environment
- **A**: Attiva Boot Environment
- **D**: Elimina Boot Environment

### rEFInd Management
- **E**: Gestione completa Boot Environment rEFInd
- **U**: Aggiornamento sicuro (procedura guidata)

### Utility
- **s**: Stato dataset e snapshot
- **l**: Visualizza ultimi log
- **v**: Toggle modalità verbose
- **0**: Esci

## 🚨 Avvertenze

### ⚠️ Operazioni Distruttive
- **PURGE**: Elimina TUTTI gli snapshot automatici (irreversibile)
- **Destroy Legacy/Beta**: Rimozione definitiva dei dataset
- **Promote BE**: Modifica la struttura di boot (richiede riavvio)

### 🔍 Verifiche Pre-Operazione
- **Spazio disponibile** nel pool ZFS
- **Backup configurazione** rEFInd funzionante
- **Snapshot di sicurezza** esistenti e accessibili

## 📈 Note per Futuri Aggiornamenti

### 🔧 Migliorie Suggerite

#### Funzionalità
- [ ] **Compressione snapshot**: Implementare compressione automatica per snapshot di archivio
- [ ] **Sync remoto**: Funzione di sincronizzazione snapshot su storage remoto (cloud/NAS)
- [ ] **Notifiche**: Sistema di notifiche email/telegram per operazioni critiche
- [ ] **GUI**: Interfaccia grafica opzionale per operazioni comuni
- [ ] **Metrics**: Dashboard web per monitoraggio stato ZFS e snapshot

#### Sicurezza
- [ ] **Checksums**: Verifica integrità snapshot prima del restore
- [ ] **Encryption**: Supporto per snapshot cifrati
- [ ] **Access Control**: Gestione permessi granulari per operazioni
- [ ] **Audit Log**: Log dettagliato delle modifiche per compliance

#### Automazione
- [ ] **Smart Scheduling**: Scheduling intelligente basato sull'utilizzo sistema
- [ ] **Pre/Post Hooks**: Script personalizzati da eseguire prima/dopo operazioni
- [ ] **Integration**: Integrazione con systemd timers e servizi
- [ ] **Health Monitoring**: Controlli automatici di salute del pool ZFS

#### Compatibilità
- [ ] **Multi-Pool**: Supporto per gestione di pool ZFS multipli
- [ ] **Other Distros**: Compatibilità con Ubuntu, CentOS, ecc.
- [ ] **GRUB Support**: Supporto alternativo per bootloader GRUB
- [ ] **Container Integration**: Integrazione con Docker/Podman per snapshot container

### 🐛 Bug Report e Contributi

Per segnalare bug o proporre migliorie:
1. Attivare modalità verbose (`-v`) per log dettagliati
2. Verificare il file di log `/var/log/zfs-management.log`
3. Includere configurazione ZFS (`zpool status`, `zfs list`)
4. Dettagliare la procedura che causa il problema

### 📝 Changelog

#### v1.0.0 (Current)
- Implementazione completa snapshot automation
- Sistema beta/testing integrato
- Boot Environment con rEFInd
- Menu interattivo completo
- Logging avanzato
- Protezioni sicurezza
- Documentazione completa

### 🏗️ Architettura

#### Moduli Principali
1. **Snapshot Manager**: Gestione ciclo di vita snapshot
2. **Beta System**: Clonazione e test modifiche
3. **Boot Environment**: Gestione BE con rEFInd
4. **Safety Layer**: Verifiche e protezioni
5. **UI/UX**: Menu interattivo e CLI

#### Dipendenze
- **ZFS Utils**: Comandi ZFS core
- **rEFInd**: Bootloader configurato
- **Bash 4+**: Shell avanzate features
- **coreutils**: Comandi Unix standard
- **util-linux**: mount, umount, ecc.

### 💡 Design Patterns

- **Fail-Safe**: Tutte le operazioni critiche hanno rollback
- **Idempotent**: Le operazioni possono essere ripetute senza effetti collaterali  
- **Atomic**: Operazioni complesse sono transazionali
- **Defensive**: Validazione estensiva degli input
- **Logging**: Tracciabilità completa delle operazioni
