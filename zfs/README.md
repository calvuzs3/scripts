# ZFS + ZFSBootMenu Setup Guide

Lascio questa sezione introduttiva perchè hoa avuto non pochi problemi a settare un ambiente sicuro di test con zfs, e non vorrei incorrere negli stessi problemi.
La situazione iniziale vedeva la EFI partition, montata in /boot, e chiaramente popolata da tutto l'albero tipico del boot, compresi il kernel e la ramfs. Questo perchè era una cosa sicura da fare, per la fase boot, giacchè refind non legge nativamente da zfs. Lo svantaggio era che si necessitava di una partizione sufficientemente grande per poter contenere diversi kernel e diverse ram, ciascuna da nomnclare, ciascuna da caricare a seconda del boot necessario.
Durante questa avventura, ho ristrutturato il mio albero, ponendo /boot nel rootfs, cosicche un solo volume viene montato, non serve una nomenclatura dedicata, non serve una configurazione ad hoc per ogni nome kernel. La partizione efi montata in /boot/efi. Per precauzione iniziale (ed ha funzionato, salvando il sistema), una copia del kernel e della ram e dell'intel ucode, posti nella root della partizione EFI; questo ha permesso di bootare da una configurazione refind funzionante.

## Transizione a ZFSBootMenu

   Il sistema è stato migrato da rEFInd + Boot Environments a **ZFSBootMenu** per una gestione più nativa e potente del boot da ZFS.

### Vantaggi ZFSBootMenu
   - **Boot ibrido rEFInd+ZBM** - Setup transitorio con rEFInd che chiama ZBM (doppio passaggio ma funzionale)
   - **Snapshot browsing** - Visualizza e boot da qualsiasi snapshot
   - **Kernel negli snapshot** - Sistema completamente atomico
   - **Clone automatico** - Crea BE da snapshot al volo
   - **Recovery integrata** - Shell di emergenza sempre disponibile

## Installazione ZFSBootMenu

### Requisiti
   - **ESP in `/boot/efi`** - ZBM richiede partizione EFI accessibile
   - **Kernel in snapshot** - Migrazione da `/boot` separato a `/boot` nel root ZFS

### Setup Iniziale

   ```bash
# 1. Installa ZFSBootMenu (manuale per verifica file)
# Scaricare pacchetto AUR e scompattare manualmente
# Verificare presenza file in /boot/efi/EFI/zbm

# 2. Configurazione base
   sudo tee /etc/zfsbootmenu/config.yaml > /dev/null << 'EOF'
   Global:
     ManageImages: true
     BootMountPoint: /boot/efi
     ImageDir: /EFI/zbm
   Components:
     Enabled: false
EFI:
  ImageDir: /EFI/zbm
  Versions: 3
  Enabled: true
Kernel:
  CommandLine: rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1 intel_iommu=on iommu=pt
EOF

# 3. Genera immagini ZBM
sudo generate-zbm

# 4. Crea entry UEFI
sudo efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "ZFSBootMenu" --loader '\EFI\zbm\vmlinuz.EFI'
```

### Migrazione Kernel negli Snapshot

**IMPORTANTE:** Il kernel deve essere incluso negli snapshot per garantire coerenza sistema-kernel. La configurazione iniziale aveva ESP montata in `/boot` (non `/boot/efi`).

```bash
# Rimonta ESP in /boot/efi per ZBM
sudo umount /boot
sudo mkdir -p /boot/efi
sudo mount /dev/nvme0n1p1 /boot/efi

# Aggiorna fstab
sudo sed -i 's|/boot|/boot/efi|g' /etc/fstab

# Installa kernel nel root ZFS
sudo pacman -S linux linux-headers
```

## Configurazione ZFS Properties

### Property Essenziali per ZBM

```bash
# Abilita dataset come bootable
sudo zfs set org.zfsbootmenu:commandline="rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1 intel_iommu=on iommu=pt" zcalvuz/ROOT/calvuz

# Per BE con mountpoint=legacy (se necessario)
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/be-name
```

### Property Opzionali

```bash
# Titolo personalizzato nel menu
sudo zfs set org.zfsbootmenu:title="Sistema Principale" zcalvuz/ROOT/calvuz

# Timeout kernel specifico
sudo zfs set org.zfsbootmenu:keysource="file:///etc/zfs/keys/dataset" zcalvuz/ROOT/calvuz
```

## Gestione Boot Environments

### Creazione BE da Snapshot

```bash
# Metodo 1: Via ZBM (automatico)
# 1. Boot in ZBM
# 2. Seleziona snapshot
# 3. ZBM crea clone automaticamente

# Metodo 2: Manuale
sudo zfs clone zcalvuz/ROOT/calvuz@snapshot-name zcalvuz/ROOT/new-be-name
sudo zfs set mountpoint=legacy zcalvuz/ROOT/new-be-name
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/new-be-name
sudo zfs set org.zfsbootmenu:commandline="rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1" zcalvuz/ROOT/new-be-name
```

### Configurazione Mountpoint per BE

**Solo un BE alla volta può avere `mountpoint=/`:**

```bash
# BE attivo
sudo zfs set mountpoint=/ zcalvuz/ROOT/calvuz
sudo zfs set canmount=on zcalvuz/ROOT/calvuz

# BE alternative
sudo zfs set mountpoint=legacy zcalvuz/ROOT/alternative-be
sudo zfs set canmount=noauto zcalvuz/ROOT/alternative-be
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/alternative-be
```

### Switch tra Boot Environments

⚠️ **ATTENZIONE:** Switch mountpoint può causare freeze se fatto dal sistema live. Raccomandato farlo da rescue shell ZBM.

```bash
# Metodo 1: Da rescue shell ZBM (raccomandato e sicuro)
# 1. Boot ZBM → rescue shell
# 2. Switch mountpoint in ambiente non montato
zfs set mountpoint=legacy zcalvuz/ROOT/calvuz
zfs set canmount=noauto zcalvuz/ROOT/calvuz
zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/calvuz

zfs set mountpoint=/ zcalvuz/ROOT/new-main-be
zfs set canmount=on zcalvuz/ROOT/new-main-be

# Metodo 2: Sistema live (SPERIMENTALE - rischio freeze)
# ⚠️ ORDINE CRITICO: mai due BE con mountpoint=/ contemporaneamente
sudo zfs set mountpoint=legacy zcalvuz/ROOT/calvuz  # PRIMA disattiva
sudo zfs set canmount=noauto zcalvuz/ROOT/calvuz
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/calvuz

sudo zfs set mountpoint=/ zcalvuz/ROOT/new-main-be  # POI attiva
sudo zfs set canmount=on zcalvuz/ROOT/new-main-be

# Metodo 3: Cambio bootfs pool
sudo zpool set bootfs=zcalvuz/ROOT/new-main-be zcalvuz
```

## Workflow Aggiornamenti Sicuri

### Snapshot Pre-Aggiornamento

```bash
# Snapshot coordinato sistema + home
sudo zfs snapshot -r zcalvuz@pre-update-$(date +%Y%m%d-%H%M)
```

### Test su Clone (Opzionale)

```bash
# 1. Crea clone per test
sudo zfs clone zcalvuz/ROOT/calvuz@pre-update-XXXXXX zcalvuz/ROOT/test-updates

# 2. Configura clone per boot
sudo zfs set mountpoint=legacy zcalvuz/ROOT/test-updates
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/test-updates
sudo zfs set org.zfsbootmenu:commandline="rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1" zcalvuz/ROOT/test-updates

# 3. Test aggiornamenti su clone
# 4. Se OK → applica su sistema principale
# 5. Se NOK → destroy clone
```

## Finalizzazione Clone di Successo

### Quando un aggiornamento testato su clone funziona perfettamente:

```bash
# 1. Disattiva BE principale
sudo zfs set mountpoint=legacy zcalvuz/ROOT/calvuz
sudo zfs set canmount=noauto zcalvuz/ROOT/calvuz
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/calvuz

# 2. Promuovi clone a principale
sudo zfs set mountpoint=/ zcalvuz/ROOT/test-updates
sudo zfs set canmount=on zcalvuz/ROOT/test-updates

# 3. Rinomina per chiarezza
sudo zfs rename zcalvuz/ROOT/calvuz zcalvuz/ROOT/calvuz-old-$(date +%Y%m%d)
sudo zfs rename zcalvuz/ROOT/test-updates zcalvuz/ROOT/calvuz

# 4. Cleanup BE vecchio (se sicuro)
sudo zfs destroy -r zcalvuz/ROOT/calvuz-old-XXXXXX
```

## Recovery di Emergenza

### Boot da Snapshot (Temporaneo)

1. Boot in ZBM
2. Seleziona snapshot desiderato
3. Boot temporaneo (non permanente)

### Rollback Home (se necessario)

```bash
# Se aggiornamento modifica configurazioni in /home
sudo zfs rollback zcalvuz/data/home@pre-update-XXXXXX
```

## Note Importanti

- **ESP obbligatoria in `/boot/efi`** - ZBM non funziona con `/boot` ZFS
- **Kernel negli snapshot** - Garantisce coerenza kernel-sistema
- **Un solo BE con `mountpoint=/`** - Evita conflitti
- **Property ZBM** - Necessarie per BE con mountpoint=legacy
- **Snapshot coordinati** - Sistema e home sincronizzati per recovery completa

## Troubleshooting

### BE non appare in ZBM
```bash
# Verifica property
zfs get org.zfsbootmenu:active,org.zfsbootmenu:commandline zcalvuz/ROOT/be-name

# Per mountpoint=legacy
sudo zfs set org.zfsbootmenu:active=on zcalvuz/ROOT/be-name
```

### "Nessun pool da importare"
- Conflitto mountpoint `/` tra più BE
- Verificare un solo BE con `mountpoint=/` e `canmount=on`

### Freeze con Plymouth
Se il sistema si blocca con Plymouth abilitato:
```bash
# Disabilita Plymouth temporaneamente nei parametri kernel
plymouth.enable=0 disablehooks=plymouth

# Assicurati di avere il framebuffer corretto per Plymouth
# Nel caso di NVIDIA, aggiungi ai parametri kernel:
org.zfsbootmenu:commandline="rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1 ..."
```



# ZFS Management Script v.1

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
