# Guida per Aggiornamento Sicuro del Sistema

## 📋 Procedura Completa di Aggiornamento Sicuro

### Prerequisiti
- Sistema Arch Linux con ZFS Root
- rEFInd come bootloader
- Privilegi di root (sudo)
- Spazio sufficiente nel pool ZFS per snapshot e cloni

### Fase 0. Crea uno snapshot di sicurezza manuale  (opzionale)

```code
# Snapshot immediato del sistema attuale
sudo zfs snapshot -r zcalvuz/ROOT@baseline-$(date +%Y%m%d)
sudo zfs snapshot -r zcalvuz/data@baseline-$(date +%Y%m%d)
```

### 🚀 Fase 1: Preparazione Pre-Aggiornamento

1. **Avvia lo script**
   ```bash
   sudo ./zfs_management.sh
   ```

2. **Verifica stato del sistema**
   - Seleziona opzione `s` per verificare lo stato dei dataset
   - Controlla che ci sia spazio sufficiente nel pool ZFS

3. **Prepara l'aggiornamento sicuro**
   - Seleziona opzione `U` (Aggiornamento sicuro)
   - Lo script creerà automaticamente:
     - Snapshot pre-aggiornamento (`pre-update-YYYYMMDD-HHMMSS`)
     - Boot Environment di rollback (`BE-rollback-update-YYYYMMDD-HHMMSS`)
     - Ambiente di recovery accessibile da rEFInd

### 🔄 Fase 2: Esecuzione Aggiornamento

4. **Procedi con l'aggiornamento del sistema**
   ```bash
   # Aggiornamento completo
   sudo pacman -Syu
   
   # Ricompila moduli ZFS se necessario
   sudo dkms autoinstall
   
   # Aggiorna initramfs
   sudo mkinitcpio -P
   ```

5. **Riavvia il sistema**
   ```bash
   sudo reboot
   ```

### ✅ Fase 3: Verifica Post-Aggiornamento

6. **Verifica il boot**
   - Il sistema dovrebbe avviarsi normalmente
   - Nel menu rEFInd saranno visibili le opzioni di recovery

7. **Testa la stabilità del sistema**
   - Esegui nuovamente lo script: `sudo ./zfs_management.sh`
   - Seleziona opzione `7` (Verifica post-aggiornamento)
   - Lo script eseguirà test automatici di integrità

8. **Conferma il successo**
   - Se tutti i test passano, il sistema è stabile
   - Lo script proporrà di eliminare i Boot Environment temporanei

### 🛡️ Opzioni di Recovery

#### In caso di problemi durante il boot:

**Opzione A - Recovery dal menu rEFInd:**
1. All'avvio, seleziona l'opzione di recovery dal menu rEFInd
2. Sistema si avvierà in modalità rescue
3. Accedi come root e risolvi i problemi

**Opzione B - Rollback completo:**
1. Avvia da rEFInd selezionando il Boot Environment di rollback
2. Una volta avviato, esegui lo script
3. Seleziona opzione `A` per attivare permanentemente il rollback

#### In caso di sistema non avviabile:

**Rescue da Live USB:**
1. Avvia da Live USB di Arch Linux
2. Importa il pool ZFS:
   ```bash
   zpool import -f zcalvuz
   ```
3. Monta il dataset di rollback:
   ```bash
   zfs set mountpoint=/ zcalvuz/ROOT/BE-rollback-*
   zfs mount zcalvuz/ROOT/BE-rollback-*
   ```
4. Chroot e ripara il sistema

### 🧹 Fase 4: Pulizia Post-Aggiornamento

9. **Pulizia automatica** (se tutto funziona)
   - Lo script durante la verifica propone la pulizia automatica
   - Conferma per rimuovere snapshot e BE temporanei

10. **Pulizia manuale** (se necessario)
    - Avvia lo script: `sudo ./zfs_management.sh`
    - Opzione `E` → `8` per pulizia ambienti temporanei
    - Seleziona manualmente cosa rimuovere

### ⚠️ Note Importanti

- **Non eliminare mai** i Boot Environment di rollback se il sistema non è stabile
- **Mantieni sempre** almeno uno snapshot di sicurezza prima di aggiornamenti kernel
- **Verifica** che rEFInd sia configurato correttamente prima di procedere
- **Testa** le funzioni critiche del sistema dopo ogni aggiornamento

### 🔧 Troubleshooting Comune

**Problema: rEFInd non mostra le opzioni di recovery**
```bash
# Verifica configurazione include
sudo ./zfs_management.sh
# Opzione E → I per setup include
```

**Problema: Spazio insufficiente per snapshot**
```bash
# Pulisci snapshot automatici vecchi
sudo ./zfs_management.sh
# Opzione 2 (cleanup) o P (purge)
```

**Problema: Boot Environment non si attiva**
```bash
# Verifica proprietà ZFS
zfs get canmount,mountpoint zcalvuz/ROOT/calvuz
# Dovrebbero essere: on,/
```

### 📊 Monitoraggio

**Verifica regolare dello stato:**
```bash
# Status rapido
sudo ./zfs_management.sh
# Opzione 's' per stato completo

# Log di sistema
sudo ./zfs_management.sh  
# Opzione 'l' per ultimi log
```

**Automazione pulizia snapshot:**
```bash
# Aggiungi a crontab per pulizia settimanale
0 2 * * 0 /path/to/zfs_management.sh cleanup
```
