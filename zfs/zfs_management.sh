#!/bin/bash
#
# ZFS Management Script - Snapshot Automation & Beta System
# 
# CICLO DI VITA DEGLI SNAPSHOT:
# =============================
# 1. CREAZIONE AUTOMATICA: Gli snapshot vengono creati automaticamente con prefix "auto-" + timestamp
# 2. SNAPSHOT DI PRODUZIONE: Snapshot manuali per il sistema beta (senza prefix "auto-")
# 3. CLONING BETA: I dataset beta vengono creati clonando gli snapshot di produzione
# 4. TESTING: I dataset beta possono essere testati senza impatto sulla produzione
# 5. PROMOZIONE: Le beta vengono promosse e diventano i nuovi dataset principali
# 6. LEGACY: I vecchi dataset di produzione diventano "legacy" prima della rimozione
# 7. PULIZIA: Gli snapshot automatici vengono eliminati secondo retention policy
#             Gli snapshot di sistema (beta/produzione) vengono preservati
#
# PROTEZIONE DEGLI SNAPSHOT:
# - Snapshot automatici (auto-*): Soggetti a retention policy
# - Snapshot di sistema: Protetti dalla pulizia automatica
# - Snapshot legacy/beta: Preservati fino alla rimozione manuale
#

# ========== CONFIGURATION ==========
VERSION="1.0.0"
POOL="zcalvuz"
DATASETS=("ROOT/calvuz" "data/home" "data/srv" "data/docker" "data/media")
SNAPSHOT_PREFIX="auto"          # Prefix per snapshot automatici
BETA_PREFIX="beta"              # Prefix per dataset beta
LEGACY_PREFIX="legacy"          # Prefix per dataset legacy
RETENTION_DAYS=30               # Giorni di retention per snapshot automatici
MAX_SNAPSHOTS=10                # Numero massimo di snapshot automatici per dataset
DATE_FORMAT=$(date +%Y-%m-%d_%H-%M-%S)
SNAPSHOT_NAME="snapshot-$(date +%Y%m%d)"
LOG_FILE="/var/log/zfs-management.log"

# ========== CONFIGURAZIONE REFIND ==========
REFIND_CONF="/boot/EFI/BOOT/refind.conf"
REFIND_BACKUP="/boot/EFI/BOOT/refind.conf.backup"
REFIND_BE_CONF="/boot/EFI/BOOT/refind-bootenvs.conf"  # NUOVO FILE
ESP_PATH="/boot"
ARCH_VOLUME_LABEL="Arch Linux (zfs)"

# ========== CONFIGURAZIONE BOOT ENVIRONMENT ==========
ZFS_ROOT="$POOL/ROOT"           # Root path per Boot Environment
BE_PREFIX="BE"                  # Prefix per Boot Environment

# Configurazione esistente da preservare
CURRENT_MENUENTRY_NAME="It's Calvuz Arch Linux"
CURRENT_ICON="/EFI/BOOT/icons/os_arch.png"
CURRENT_LOADER="/vmlinuz-linux"
CURRENT_INITRD="/initramfs-linux.img"
CURRENT_OPTIONS="zfs=bootfs rw nvidia_drm.modeset=1 nvidia.drm.fbdev=1 intel_iommu=on iommu=pt"
#CURRENT_OPTIONS="zfs=bootfs rw quiet splash nvidia_drm.modeset=1 nvidia.drm.fbdev=1 intel_iommu=on iommu=pt"

# ========== GLOBAL VARIABLES ==========
VERBOSE=0                       # Modalità verbose (0=off, 1=on)

# ========== UTILITY FUNCTIONS ==========

# Controlla se lo script viene eseguito come root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERRORE: Questo script deve essere eseguito come root (sudo)."
        echo "Le operazioni ZFS richiedono privilegi amministrativi."
        echo "Utilizzare: sudo $0"
        exit 1
    fi
}

# Logging function con supporto verbose
log() {
    local message="[$(date +"%Y-%m-%d %H:%M:%S")] $1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Verbose logging - mostrato solo se VERBOSE=1
vlog() {
    if [[ $VERBOSE -eq 1 ]]; then
        local message="[VERBOSE] $1"
        echo "$message" | tee -a "$LOG_FILE"
    fi
}

# Inizializza il file di log se non esiste
init_logging() {
    # Crea la directory di log se non esiste
    local log_dir=$(dirname "$LOG_FILE")
    [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir"
    
    # Crea il file di log se non esiste
    [[ ! -f "$LOG_FILE" ]] && touch "$LOG_FILE"
    
    # Rotazione del log se supera 10MB
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        log "Log ruotato - file precedente salvato come ${LOG_FILE}.old"
    fi
}

# Controlla se un dataset esiste
dataset_exists() {
    local dataset="$1"
    zfs list "$dataset" >/dev/null 2>&1
    return $?
}

# Controlla se uno snapshot è protetto (non automatico)
is_protected_snapshot() {
    local snapshot="$1"
    # Gli snapshot protetti sono quelli che NON iniziano con il prefix automatico
    if [[ "$snapshot" =~ @${SNAPSHOT_PREFIX}- ]]; then
        return 1  # Non protetto (snapshot automatico)
    else
        return 0  # Protetto (snapshot di sistema/manuale)
    fi
}

# ========== FUNZIONI BOOT ENVIRONMENT MANCANTI ==========

# Configura mountpoint in modo sicuro per Boot Environment
configure_safe_mountpoints() {
    local old_dataset="$1"
    local new_dataset="$2"
    
    log "🔧 Configurazione mountpoint per Boot Environment switch..."
    
    # Configura il dataset corrente come non-auto
    if ! zfs set canmount=noauto "$old_dataset" 2>/dev/null; then
        log "❌ Errore: impossibile configurare canmount per $old_dataset"
        return 1
    fi
    
    if ! zfs set mountpoint=none "$old_dataset" 2>/dev/null; then
        log "❌ Errore: impossibile configurare mountpoint per $old_dataset"
        return 1
    fi
    
    # Configura il nuovo dataset come principale
    if ! zfs set canmount=on "$new_dataset" 2>/dev/null; then
        log "❌ Errore: impossibile configurare canmount per $new_dataset"
        return 1
    fi
    
    if ! zfs set mountpoint=/ "$new_dataset" 2>/dev/null; then
        log "❌ Errore: impossibile configurare mountpoint per $new_dataset"
        return 1
    fi
    
    log "✅ Mountpoint configurati correttamente"
    return 0
}

# Verifica il successo del boot dopo riavvio
verify_boot_success() {
    local expected_dataset="$1"
    local current_root=$(mount | grep " on / type zfs" | cut -d' ' -f1)
    
    if [[ "$current_root" == "$expected_dataset" ]]; then
        log "✅ Boot Environment promosso con successo!"
        log "📍 Sistema attivo: $current_root"
        return 0
    else
        log "⚠️  Boot Environment parzialmente promosso"
        log "📍 Sistema attivo: $current_root"
        log "📍 Atteso: $expected_dataset"
        return 1
    fi
}

# Lista tutti i Boot Environment (sia rEFInd che generici)
list_boot_environments() {
    log "=== Boot Environment Disponibili ==="
    
    echo "SISTEMA PRINCIPALE:"
    if dataset_exists "$ZFS_ROOT/calvuz"; then
        local used=$(zfs get -H -o value used "$ZFS_ROOT/calvuz")
        local creation=$(zfs get -H -o value creation "$ZFS_ROOT/calvuz")
        local current_root=$(mount | grep " on / type zfs" | cut -d' ' -f1)
        local status="INATTIVO"
        [[ "$current_root" == "$ZFS_ROOT/calvuz" ]] && status="ATTIVO"
        echo "  ✓ calvuz ($status) - $used - Creato: $creation"
    fi
    
    echo -e "\nBOOT ENVIRONMENTS:"
    local be_found=false
    while read -r dataset; do
        if [[ "$dataset" =~ ^${ZFS_ROOT}/${BE_PREFIX}- ]] || [[ "$dataset" =~ ^${ZFS_ROOT}/backup- ]] || [[ "$dataset" =~ ^${ZFS_ROOT}/rollback- ]]; then
            local be_name="${dataset#$ZFS_ROOT/}"
            local used=$(zfs get -H -o value used "$dataset")
            local creation=$(zfs get -H -o value creation "$dataset")
            local canmount=$(zfs get -H -o value canmount "$dataset")
            local mountpoint=$(zfs get -H -o value mountpoint "$dataset")
            
            # Determina il tipo
            local be_type="Standard"
            [[ "$be_name" =~ ^${BE_PREFIX}-recovery- ]] && be_type="Recovery"
            [[ "$be_name" =~ ^${BE_PREFIX}-rollback- ]] && be_type="Rollback"
            [[ "$be_name" =~ ^backup- ]] && be_type="Backup"
            
            # Status
            local status="📦"
            [[ "$canmount" == "on" && "$mountpoint" == "/" ]] && status="🔄"
            
            echo "  $status $be_name ($be_type) - $used - $creation"
            be_found=true
        fi
    done < <(zfs list -H -o name -s creation | grep "^$ZFS_ROOT/")
    
    [[ "$be_found" == "false" ]] && echo "  Nessun Boot Environment trovato"
    
    echo -e "\nSNAPSHOT DISPONIBILI PER BOOT ENVIRONMENT:"
    local snap_found=false
    while read -r snapshot; do
        if [[ "$snapshot" =~ ^${ZFS_ROOT}/calvuz@ ]]; then
            local snap_name="${snapshot#$ZFS_ROOT/calvuz@}"
            local used=$(zfs get -H -o value used "$snapshot" 2>/dev/null || echo "N/A")
            local creation=$(zfs get -H -o value creation "$snapshot" 2>/dev/null || echo "N/A")
            
            # Determina il tipo di snapshot
            local snap_type="Sistema"
            [[ "$snap_name" =~ ^${SNAPSHOT_PREFIX}- ]] && snap_type="Automatico"
            [[ "$snap_name" =~ ^(pre-|baseline-|rollback-) ]] && snap_type="Sicurezza"
            
            echo "  📸 $snap_name ($snap_type) - $used - $creation"
            snap_found=true
        fi
    done < <(zfs list -H -o name -t snapshot -s creation | grep "^$ZFS_ROOT/calvuz@")
    
    [[ "$snap_found" == "false" ]] && echo "  Nessuno snapshot disponibile"
}

# ========== SNAPSHOT AUTOMATION FUNCTIONS ==========

# Crea snapshot automatici per tutti i dataset configurati
create_automated_snapshots() {
    log "=== Inizio creazione snapshot automatici ==="
    local success_count=0
    local error_count=0
    
    for dataset in "${DATASETS[@]}"; do
        local full_dataset="$POOL/$dataset"
        vlog "Controllo esistenza dataset: $full_dataset"
        
        if dataset_exists "$full_dataset"; then
            local snapshot_name="${full_dataset}@${SNAPSHOT_PREFIX}-${DATE_FORMAT}"
            log "Creazione snapshot automatico: $snapshot_name"
            
            if zfs snapshot "$snapshot_name" 2>/dev/null; then
                log "✓ Snapshot creato con successo: $snapshot_name"
                ((success_count++))
            else
                log "✗ ERRORE: Impossibile creare snapshot: $snapshot_name"
                ((error_count++))
            fi
        else
            log "✗ ERRORE: Dataset non trovato: $full_dataset"
            ((error_count++))
        fi
    done
    
    log "=== Creazione snapshot completata: $success_count successi, $error_count errori ==="
}

# Pulisce gli snapshot automatici vecchi secondo la retention policy
cleanup_old_snapshots() {
    log "=== Inizio pulizia snapshot automatici vecchi ==="
    local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%s)
    local total_removed=0
    
    vlog "Data di cutoff per retention: $(date -d "$RETENTION_DAYS days ago")"
    
    for dataset in "${DATASETS[@]}"; do
        local full_dataset="$POOL/$dataset"
        vlog "Analisi snapshot per dataset: $full_dataset"
        
        if ! dataset_exists "$full_dataset"; then
            vlog "Dataset $full_dataset non esiste, salto"
            continue
        fi
        
        # Ottieni solo gli snapshot automatici per il dataset corrente
        local snapshots=$(zfs list -H -t snapshot -o name,creation -S creation 2>/dev/null | \
                         grep "^${full_dataset}@${SNAPSHOT_PREFIX}-" | \
                         head -n 100)
        
        if [[ -z "$snapshots" ]]; then
            vlog "Nessuno snapshot automatico trovato per $full_dataset"
            continue
        fi
        
        local count=0
        local removed_count=0
        
        while IFS=$'\t' read -r snapshot creation; do
            ((count++))
            vlog "Analisi snapshot #$count: $snapshot (creato: $creation)"
            
            # Converti la data di creazione in timestamp
            local creation_timestamp=$(date -d "$creation" +%s 2>/dev/null || echo 0)
            
            # Rimuovi se troppo vecchio O se supera il numero massimo
            local should_remove=false
            local reason=""
            
            if [[ "$creation_timestamp" -lt "$cutoff_date" ]]; then
                should_remove=true
                reason="più vecchio di $RETENTION_DAYS giorni"
            elif [[ "$count" -gt "$MAX_SNAPSHOTS" ]]; then
                should_remove=true
                reason="supera il limite di $MAX_SNAPSHOTS snapshot"
            fi
            
            if [[ "$should_remove" == "true" ]]; then
                vlog "Rimozione snapshot: $snapshot ($reason)"
                
                if zfs destroy "$snapshot" 2>/dev/null; then
                    log "✓ Snapshot rimosso: $snapshot ($reason)"
                    ((removed_count++))
                    ((total_removed++))
                else
                    log "✗ ERRORE: Impossibile rimuovere snapshot: $snapshot"
                fi
            else
                vlog "Snapshot conservato: $snapshot"
            fi
            
        done <<< "$snapshots"
        
        [[ $removed_count -gt 0 ]] && log "Dataset $full_dataset: $removed_count snapshot rimossi"
    done
    
    log "=== Pulizia completata: $total_removed snapshot automatici rimossi ==="
}

# Rimuove TUTTI gli snapshot automatici (ATTENZIONE: operazione irreversibile)
purge_all_auto_snapshots() {
    log "=== INIZIO PURGE COMPLETO SNAPSHOT AUTOMATICI ==="
    log "ATTENZIONE: Rimozione di TUTTI gli snapshot automatici in corso..."
    
    local total_removed=0
    local total_protected=0
    
    # Ottieni tutti gli snapshot del pool
    local all_snapshots=$(zfs list -H -t snapshot -o name 2>/dev/null | grep "^$POOL/")
    
    while read -r snapshot; do
        [[ -z "$snapshot" ]] && continue
        
        if is_protected_snapshot "$snapshot"; then
            vlog "Snapshot protetto (preservato): $snapshot"
            ((total_protected++))
        else
            vlog "Rimozione snapshot automatico: $snapshot"
            
            if zfs destroy "$snapshot" 2>/dev/null; then
                log "✓ Rimosso: $snapshot"
                ((total_removed++))
            else
                log "✗ ERRORE rimozione: $snapshot"
            fi
        fi
    done <<< "$all_snapshots"
    
    log "=== PURGE COMPLETATO: $total_removed automatici rimossi, $total_protected protetti preservati ==="
}

# ========== BETA SYSTEM FUNCTIONS ==========

# Crea snapshot di produzione per il sistema beta
create_production_snapshots() {
    local name=${1:-$SNAPSHOT_NAME}
    log "=== Creazione snapshot di produzione: $name ==="
    
    vlog "Creazione snapshot ricorsivo per ROOT: $POOL/ROOT@$name"
    vlog "Creazione snapshot ricorsivo per data: $POOL/data@$name"
    
    local success=true
    
    # Crea snapshot ricorsivi per ROOT e data
    if ! zfs snapshot -r "$POOL/ROOT@$name" 2>/dev/null; then
        log "✗ ERRORE: Impossibile creare snapshot per $POOL/ROOT@$name"
        success=false
    else
        log "✓ Snapshot ROOT creato: $POOL/ROOT@$name"
    fi
    
    if ! zfs snapshot -r "$POOL/data@$name" 2>/dev/null; then
        log "✗ ERRORE: Impossibile creare snapshot per $POOL/data@$name"
        success=false
    else
        log "✓ Snapshot data creato: $POOL/data@$name"
    fi
    
    if [[ "$success" == "true" ]]; then
        log "=== Snapshot di produzione creati con successo ==="
        return 0
    else
        log "=== Errori durante la creazione degli snapshot di produzione ==="
        return 1
    fi
}

# Popola i dataset beta clonando dagli snapshot di produzione
populate_betas() {
    local name=${1:-$SNAPSHOT_NAME}
    log "=== Popolamento dataset beta da snapshot: $name ==="
    
    local clones_created=0
    local clones_failed=0
    
    # Array di mappature source->destination per i cloni
    local -A clone_map=(
        ["$POOL/ROOT/calvuz@$name"]="$POOL/ROOT/${BETA_PREFIX}calvuz"
        ["$POOL/data/home@$name"]="$POOL/data/${BETA_PREFIX}home"
        ["$POOL/data/srv@$name"]="$POOL/data/${BETA_PREFIX}srv"
        ["$POOL/data/docker@$name"]="$POOL/data/${BETA_PREFIX}docker"
        ["$POOL/data/media@$name"]="$POOL/data/${BETA_PREFIX}media"
    )
    
    for source in "${!clone_map[@]}"; do
        local destination="${clone_map[$source]}"
        vlog "Tentativo clone: $source -> $destination"
        
        # Controlla se lo snapshot di origine esiste
        if ! zfs list "$source" >/dev/null 2>&1; then
            log "✗ Snapshot sorgente non trovato: $source"
            ((clones_failed++))
            continue
        fi
        
        # Controlla se la destinazione esiste già
        if dataset_exists "$destination"; then
            log "⚠ Clone già esistente: $destination"
            continue
        fi
        
        # Crea il clone
        if zfs clone "$source" "$destination" 2>/dev/null; then
            log "✓ Clone creato: $destination"
            ((clones_created++))
        else
            log "✗ ERRORE clone: $source -> $destination"
            ((clones_failed++))
        fi
    done
    
    log "=== Popolamento beta completato: $clones_created creati, $clones_failed falliti ==="
}

# Promuove i dataset beta (li rende indipendenti dagli snapshot originali)
promote_betas() {
    log "=== Promozione dataset beta ==="
    
    local beta_datasets=(
        "$POOL/ROOT/${BETA_PREFIX}calvuz"
        "$POOL/data/${BETA_PREFIX}home"
        "$POOL/data/${BETA_PREFIX}srv"
        "$POOL/data/${BETA_PREFIX}docker"
        "$POOL/data/${BETA_PREFIX}media"
    )
    
    local promoted=0
    local failed=0
    
    for dataset in "${beta_datasets[@]}"; do
        vlog "Tentativo promozione: $dataset"
        
        if ! dataset_exists "$dataset"; then
            log "⚠ Dataset beta non trovato: $dataset"
            continue
        fi
        
        if zfs promote "$dataset" 2>/dev/null; then
            log "✓ Promosso: $dataset"
            ((promoted++))
        else
            log "✗ ERRORE promozione: $dataset"
            ((failed++))
        fi
    done
    
    log "=== Promozione completata: $promoted promossi, $failed falliti ==="
}

# Ripristina la promozione (demote) dei dataset beta
demote_betas() {
    log "=== Ripristino promozione dataset originali ==="
    
    local original_datasets=(
        "$POOL/ROOT/calvuz"
        "$POOL/data/home"
        "$POOL/data/srv"
        "$POOL/data/docker"
        "$POOL/data/media"
    )
    
    for dataset in "${original_datasets[@]}"; do
        vlog "Tentativo demote: $dataset"
        
        if dataset_exists "$dataset"; then
            zfs promote "$dataset" 2>/dev/null && vlog "Demote eseguito: $dataset"
        fi
    done
    
    log "=== Ripristino promozione completato ==="
}

# Sposta i dataset beta in produzione e quelli attuali in legacy
rename_to_production() {
    log "=== Spostamento beta in produzione ==="
    
    # Array di mappature per i rename
    local -A production_to_legacy=(
        ["$POOL/ROOT/calvuz"]="$POOL/ROOT/${LEGACY_PREFIX}calvuz"
        ["$POOL/data/home"]="$POOL/data/${LEGACY_PREFIX}home"
        ["$POOL/data/srv"]="$POOL/data/${LEGACY_PREFIX}srv"
        ["$POOL/data/docker"]="$POOL/data/${LEGACY_PREFIX}docker"
        ["$POOL/data/media"]="$POOL/data/${LEGACY_PREFIX}media"
    )
    
    local -A beta_to_production=(
        ["$POOL/ROOT/${BETA_PREFIX}calvuz"]="$POOL/ROOT/calvuz"
        ["$POOL/data/${BETA_PREFIX}home"]="$POOL/data/home"
        ["$POOL/data/${BETA_PREFIX}srv"]="$POOL/data/srv"
        ["$POOL/data/${BETA_PREFIX}docker"]="$POOL/data/docker"
        ["$POOL/data/${BETA_PREFIX}media"]="$POOL/data/media"
    )
    
    # Fase 1: Sposta produzione attuale in legacy
    log "Fase 1: Spostamento produzione -> legacy"
    for prod in "${!production_to_legacy[@]}"; do
        local legacy="${production_to_legacy[$prod]}"
        vlog "Rename: $prod -> $legacy"
        
        if dataset_exists "$prod"; then
            if zfs rename "$prod" "$legacy" 2>/dev/null; then
                log "✓ $prod -> $legacy"
            else
                log "✗ ERRORE rename: $prod -> $legacy"
            fi
        else
            log "⚠ Dataset produzione non trovato: $prod"
        fi
    done
    
    # Fase 2: Sposta beta in produzione
    log "Fase 2: Spostamento beta -> produzione"
    for beta in "${!beta_to_production[@]}"; do
        local prod="${beta_to_production[$beta]}"
        vlog "Rename: $beta -> $prod"
        
        if dataset_exists "$beta"; then
            if zfs rename "$beta" "$prod" 2>/dev/null; then
                log "✓ $beta -> $prod"
            else
                log "✗ ERRORE rename: $beta -> $prod"
            fi
        else
            log "⚠ Dataset beta non trovato: $beta"
        fi
    done
    
    log "=== Spostamento in produzione completato ==="
}

# Elimina tutti i dataset legacy
destroy_legacy() {
    log "=== Eliminazione dataset legacy ==="
    
    local legacy_datasets=(
        "$POOL/ROOT/${LEGACY_PREFIX}calvuz"
        "$POOL/data/${LEGACY_PREFIX}home"
        "$POOL/data/${LEGACY_PREFIX}srv"
        "$POOL/data/${LEGACY_PREFIX}docker"
        "$POOL/data/${LEGACY_PREFIX}media"
    )
    
    local destroyed=0
    
    for dataset in "${legacy_datasets[@]}"; do
        vlog "Tentativo eliminazione: $dataset"
        
        if dataset_exists "$dataset"; then
            if zfs destroy "$dataset" 2>/dev/null; then
                log "✓ Eliminato: $dataset"
                ((destroyed++))
            else
                log "✗ ERRORE eliminazione: $dataset"
            fi
        else
            vlog "Dataset legacy non trovato: $dataset"
        fi
    done
    
    log "=== Eliminazione legacy completata: $destroyed dataset rimossi ==="
}

# Elimina tutti i dataset beta (con demote preventivo)
destroy_betas() {
    log "=== Eliminazione dataset beta ==="
    
    # Prima esegui demote per sicurezza
    demote_betas
    
    local beta_datasets=(
        "$POOL/ROOT/${BETA_PREFIX}calvuz"
        "$POOL/data/${BETA_PREFIX}home"
        "$POOL/data/${BETA_PREFIX}srv"
        "$POOL/data/${BETA_PREFIX}docker"
        "$POOL/data/${BETA_PREFIX}media"
    )
    
    local destroyed=0
    
    for dataset in "${beta_datasets[@]}"; do
        vlog "Tentativo eliminazione: $dataset"
        
        if dataset_exists "$dataset"; then
            if zfs destroy "$dataset" 2>/dev/null; then
                log "✓ Eliminato: $dataset"
                ((destroyed++))
            else
                log "✗ ERRORE eliminazione: $dataset"
            fi
        else
            vlog "Dataset beta non trovato: $dataset"
        fi
    done
    
    log "=== Eliminazione beta completata: $destroyed dataset rimossi ==="
}

# ========== FUNZIONI REFIND SPECIFICHE ==========

# Backup della configurazione rEFInd corrente
backup_refind_config() {
    log "=== Backup configurazione rEFInd ==="
    
    if [[ -f "$REFIND_CONF" ]]; then
        cp "$REFIND_CONF" "$REFIND_BACKUP"
        log "✓ Backup salvato: $REFIND_BACKUP"
        return 0
    else
        log "✗ File configurazione rEFInd non trovato: $REFIND_CONF"
        return 1
    fi
}

# Setup della direttiva include in refind.conf
setup_refind_include() {
    log "=== Setup include Boot Environment in rEFInd ==="
    
    # Verifica se l'include è già presente
    if grep -q "include.*refind-bootenvs.conf" "$REFIND_CONF"; then
        log "✓ Include già configurato in rEFInd"
        return 0
    fi
    
    # Backup configurazione
    backup_refind_config
    
    # Aggiunge la direttiva include alla fine del file principale
    echo "" >> "$REFIND_CONF"
    echo "# Boot Environments - Auto-generated entries" >> "$REFIND_CONF"
    echo "include refind-bootenvs.conf" >> "$REFIND_CONF"
    
    log "✓ Direttiva include aggiunta a rEFInd"
    return 0
}

# Inizializza file configurazione Boot Environment
initialize_be_config() {
    log "=== Inizializzazione file configurazione BE ==="
    
    # Crea file vuoto con header
    cat > "$REFIND_BE_CONF" << 'EOF'
#
# refind-bootenvs.conf
# Boot Environment entries auto-generated by zfs_manager.sh
# DO NOT EDIT MANUALLY - This file is automatically managed
#
# Generated on: TIMESTAMP
#

EOF
    
    # Sostituisce timestamp
    sed -i "s/TIMESTAMP/$(date)/" "$REFIND_BE_CONF"
    
    log "✓ File configurazione BE inizializzato: $REFIND_BE_CONF"
    return 0
}

# Ripristina backup configurazione rEFInd
restore_refind_config() {
    log "=== Ripristino configurazione rEFInd ==="
    
    if [[ -f "$REFIND_BACKUP" ]]; then
        cp "$REFIND_BACKUP" "$REFIND_CONF"
        log "✓ Configurazione principale ripristinata da: $REFIND_BACKUP"
        
        # Rimuove anche il file delle BE se esiste
        if [[ -f "$REFIND_BE_CONF" ]]; then
            rm "$REFIND_BE_CONF"
            log "✓ File Boot Environment rimosso: $REFIND_BE_CONF"
        fi
        
        return 0
    else
        log "✗ File backup non trovato: $REFIND_BACKUP"
        return 1
    fi
}

# Pulisce le entry dei Boot Environment (ricrea file vuoto)
clean_be_entries() {
    log "=== Pulizia entry Boot Environment ==="
    
    # Setup include se non presente
    setup_refind_include
    
    # Ricrea file vuoto
    initialize_be_config
    
    log "✓ Tutte le entry Boot Environment rimosse"
}

# Aggiunge entry Boot Environment al file separato
add_be_entry_to_refind() {
    local be_name="$1"
    local be_dataset="$2"
    local description="$3"
    local is_recovery="${4:-false}"
    
    log "=== Aggiunta entry rEFInd per BE: $be_name ==="
    
    # Setup include se necessario
    setup_refind_include
    
    # Crea file se non esiste
    [[ ! -f "$REFIND_BE_CONF" ]] && initialize_be_config
    
    # Determina icona e opzioni basate sul tipo
    local icon="$CURRENT_ICON"
    local options="$CURRENT_OPTIONS"
    local menu_title="$description"
    
    if [[ "$is_recovery" == "true" ]]; then
        icon="/EFI/BOOT/icons/os_recovery.png"
        menu_title="🛡️ $description (Recovery)"
        # Per recovery: mantieni zfs=bootfs originale + modalità rescue
        options="$CURRENT_OPTIONS systemd.unit=rescue.target loglevel=7"
    else
        # Per BE normali: specifica il dataset ma mantieni TUTTE le opzioni originali
        options="root=ZFS=$be_dataset rw quiet splash nvidia_drm.modeset=1 nvidia.drm.fbdev=1 intel_iommu=on iommu=pt"
    fi
    
    # Aggiunge l'entry al file separato
    cat >> "$REFIND_BE_CONF" << EOF

# Boot Environment: $be_name ($(date))
menuentry "$menu_title" {
    icon     $icon
    volume   "$ARCH_VOLUME_LABEL"
    loader   $CURRENT_LOADER
    initrd   $CURRENT_INITRD
    options  "$options"
    submenuentry "Boot using fallback initramfs" {
        initrd /initramfs-linux-fallback.img
    }
    submenuentry "Boot to terminal" {
        add_options "systemd.unit=multi-user.target"
    }
    submenuentry "Boot with init=/bin/bash (Emergency)" {
        add_options "init=/bin/bash"
    }
}
EOF
    
    log "✓ Entry rEFInd aggiunta: $menu_title"
    log "  File: $REFIND_BE_CONF"
    log "  Dataset: $be_dataset"
    log "  Opzioni: $options"
}

# Aggiunge entry di recovery con zfs=bootfs
add_recovery_entry_to_refind() {
    local recovery_name="$1"
    local description="$2"
    
    log "=== Aggiunta entry Recovery rEFInd: $recovery_name ==="
    
    # Setup include se necessario
    setup_refind_include
    
    # Crea file se non esiste
    [[ ! -f "$REFIND_BE_CONF" ]] && initialize_be_config
    
    # Per recovery usiamo zfs=bootfs (dataset corrente) con opzioni di debug
    local recovery_options="$CURRENT_OPTIONS systemd.unit=rescue.target loglevel=7"
    
    cat >> "$REFIND_BE_CONF" << EOF

# Recovery Environment: $recovery_name ($(date))
menuentry "🛡️ $description (Recovery Mode)" {
    icon     /EFI/BOOT/icons/os_recovery.png
    volume   "$ARCH_VOLUME_LABEL"
    loader   $CURRENT_LOADER
    initrd   $CURRENT_INITRD
    options  "$recovery_options"
    submenuentry "Recovery with fallback initramfs" {
        initrd /initramfs-linux-fallback.img
    }
    submenuentry "Emergency shell (init=/bin/bash)" {
        add_options "init=/bin/bash"
    }
    submenuentry "Single user mode" {
        add_options "systemd.unit=rescue.target single"
    }
}
EOF
    
    log "✓ Entry Recovery aggiunta: $description"
    log "  File: $REFIND_BE_CONF"
    log "  Opzioni: $recovery_options"
}

# Crea Boot Environment da snapshot esistente
create_refind_boot_environment() {
    local be_name="$1"
    local snapshot_name="$2"
    local description="${3:-Boot Environment $be_name}"
    
    log "=== Creazione Boot Environment: $be_name ==="
    
    local be_dataset="$ZFS_ROOT/${BE_PREFIX}-$be_name"
    local source_snapshot="$ZFS_ROOT/calvuz@$snapshot_name"
    
    # Verifica che lo snapshot sorgente esista
    if ! zfs list "$source_snapshot" >/dev/null 2>&1; then
        log "✗ Snapshot sorgente non trovato: $source_snapshot"
        return 1
    fi
    
    # Verifica che il BE non esista già
    if dataset_exists "$be_dataset"; then
        log "✗ Boot Environment già esistente: $be_name"
        return 1
    fi
    
    # 1. Crea clone dal snapshot
    if ! zfs clone "$source_snapshot" "$be_dataset"; then
        log "✗ Errore creazione clone per BE: $be_name"
        return 1
    fi
    
    # 2. Configura proprietà del BE
    zfs set canmount=noauto "$be_dataset"
    zfs set mountpoint=none "$be_dataset"
    
    # 3. Backup configurazione rEFInd
    backup_refind_config
    
    # 4. Aggiunge entry al menu rEFInd
    add_be_entry_to_refind "$be_name" "$be_dataset" "$description" false
    
    log "✓ Boot Environment creato con successo: $be_name"
    log "  Dataset: $be_dataset"
    log "  Sorgente: $source_snapshot"
    log "  Descrizione: $description"
    log "  Entry rEFInd aggiunta al menu"
    
    return 0
}

# ========== GESTIONE BOOT ENVIRONMENT ==========

# Crea Boot Environment di recovery
create_recovery_environment() {
    local recovery_name="recovery-$(date +%Y%m%d-%H%M%S)"
    local snapshot_name="pre-recovery-$(date +%Y%m%d-%H%M%S)"
    
    log "=== Creazione ambiente di recovery ==="
    
    # 1. Crea snapshot di sicurezza
    if ! zfs snapshot "$ZFS_ROOT/calvuz@$snapshot_name"; then
        log "✗ Errore creazione snapshot di recovery"
        return 1
    fi
    
    # 2. Backup configurazione rEFInd
    backup_refind_config
    
    # 3. Aggiunge solo entry di recovery (non crea dataset separato)
    add_recovery_entry_to_refind "$recovery_name" "Sistema di Recovery"
    
    log "✓ Ambiente di recovery creato: $recovery_name"
    log "  Usa il sistema corrente con modalità rescue"
    log "  Snapshot di sicurezza: $snapshot_name"
    return 0
}

# Lista tutti i Boot Environment
list_refind_boot_environments() {
    log "=== Boot Environment rEFInd Disponibili ==="
    
    echo "SISTEMA PRINCIPALE:"
    if dataset_exists "$ZFS_ROOT/calvuz"; then
        local used=$(zfs get -H -o value used "$ZFS_ROOT/calvuz")
        local creation=$(zfs get -H -o value creation "$ZFS_ROOT/calvuz")
        echo "  ✓ calvuz (ATTIVO) - $used - Creato: $creation"
    fi
    
    echo -e "\nBOOT ENVIRONMENTS:"
    local be_found=false
    while read -r dataset; do
        if [[ "$dataset" =~ ^${ZFS_ROOT}/${BE_PREFIX}- ]]; then
            local be_name="${dataset#$ZFS_ROOT/${BE_PREFIX}-}"
            local used=$(zfs get -H -o value used "$dataset")
            local creation=$(zfs get -H -o value creation "$dataset")
            local canmount=$(zfs get -H -o value canmount "$dataset")
            
            # Determina il tipo
            local be_type="Standard"
            [[ "$be_name" =~ ^recovery- ]] && be_type="Recovery"
            [[ "$be_name" =~ ^rollback- ]] && be_type="Rollback"
            
            echo "  ✓ $be_name ($be_type) - $used - $creation"
            be_found=true
        fi
    done < <(zfs list -H -o name -s creation | grep "^$ZFS_ROOT/")
    
    [[ "$be_found" == "false" ]] && echo "  Nessun Boot Environment trovato"
    
    echo -e "\nENTRY rEFInd CONFIGURATE:"
    if [[ -f "$REFIND_BE_CONF" ]]; then
        echo "  File: $REFIND_BE_CONF"
        grep -n "menuentry.*" "$REFIND_BE_CONF" | while read -r line; do
            echo "  → $line"
        done
        
        echo -e "\nDimensione file configurazione BE:"
        ls -lh "$REFIND_BE_CONF" | awk '{print "  " $5 " - " $9}'
    else
        echo "  Nessun file Boot Environment trovato"
        echo "  Eseguire prima 'Crea ambiente di recovery' per inizializzare"
    fi
    
    echo -e "\nSTATO INCLUDE in rEFInd:"
    if grep -q "include.*refind-bootenvs.conf" "$REFIND_CONF"; then
        echo "  ✓ Include configurato correttamente"
    else
        echo "  ⚠️  Include non configurato (verrà aggiunto automaticamente)"
    fi
}

# Attiva Boot Environment (sposta in produzione)
activate_refind_boot_environment() {
    local be_name="$1"
    local be_dataset="$ZFS_ROOT/${BE_PREFIX}-$be_name"
    
    log "=== Attivazione Boot Environment: $be_name ==="
    
    if ! dataset_exists "$be_dataset"; then
        log "✗ Boot Environment non trovato: $be_name"
        return 1
    fi
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="backup-$timestamp"
    
    # 1. Backup configurazione rEFInd
    backup_refind_config
    
    # 2. Sposta il sistema attuale in backup
    if dataset_exists "$ZFS_ROOT/calvuz"; then
        if ! zfs rename "$ZFS_ROOT/calvuz" "$ZFS_ROOT/$backup_name"; then
            log "✗ Errore backup sistema attuale"
            return 1
        fi
        log "✓ Sistema attuale salvato come: $backup_name"
    fi
    
    # 3. Promuovi il BE se necessario
    zfs promote "$be_dataset" 2>/dev/null || true
    
    # 4. Sposta BE in produzione
    if ! zfs rename "$be_dataset" "$ZFS_ROOT/calvuz"; then
        log "✗ Errore attivazione Boot Environment"
        # Tentativo di rollback
        zfs rename "$ZFS_ROOT/$backup_name" "$ZFS_ROOT/calvuz" 2>/dev/null
        return 1
    fi
    
    # 5. Configura proprietà del nuovo sistema principale
    zfs set canmount=on "$ZFS_ROOT/calvuz"
    zfs set mountpoint=/ "$ZFS_ROOT/calvuz"
    
    # 6. Pulisce e ricostruisce configurazione rEFInd
    clean_be_entries
    
    # 7. Aggiunge entry per il sistema di backup
    add_be_entry_to_refind "$backup_name" "$ZFS_ROOT/$backup_name" "Sistema Precedente (Backup)" true
    
    log "✓ Boot Environment attivato con successo: $be_name"
    log "  Sistema precedente disponibile come: $backup_name"
    log "  Riavviare per utilizzare il nuovo sistema"
    
    return 0
}

# Elimina Boot Environment
destroy_refind_boot_environment() {
    local be_name="$1"
    local be_dataset="$ZFS_ROOT/${BE_PREFIX}-$be_name"
    
    log "=== Eliminazione Boot Environment: $be_name ==="
    
    if ! dataset_exists "$be_dataset"; then
        log "✗ Boot Environment non trovato: $be_name"
        return 1
    fi
    
    # 1. Backup configurazione rEFInd
    backup_refind_config
    
    # 2. Elimina dataset ZFS
    if zfs destroy "$be_dataset"; then
        log "✓ Dataset eliminato: $be_dataset"
    else
        log "✗ Errore eliminazione dataset: $be_dataset"
        return 1
    fi
    
    # 3. Rimuove entry da rEFInd
    clean_be_entries
    
    # 4. Ricostruisce entry per i BE rimanenti
    while read -r dataset; do
        if [[ "$dataset" =~ ^${ZFS_ROOT}/${BE_PREFIX}- ]]; then
            local remaining_be="${dataset#$ZFS_ROOT/${BE_PREFIX}-}"
            local desc="Boot Environment $remaining_be"
            [[ "$remaining_be" =~ ^recovery- ]] && desc="Sistema di Recovery"
            [[ "$remaining_be" =~ ^rollback- ]] && desc="Sistema di Rollback"
            
            add_be_entry_to_refind "$remaining_be" "$dataset" "$desc" false
        elif [[ "$dataset" =~ ^${ZFS_ROOT}/backup- ]]; then
            local backup_name="${dataset#$ZFS_ROOT/}"
            add_be_entry_to_refind "$backup_name" "$dataset" "Sistema di Backup" true
        fi
    done < <(zfs list -H -o name | grep "^$ZFS_ROOT/" | grep -v "^$ZFS_ROOT/calvuz$")
    
    log "✓ Boot Environment eliminato: $be_name"
    return 0
}

# ========== WORKFLOW SICURO ==========

# Prepara aggiornamento sicuro del sistema
prepare_safe_update() {
    local update_name="update-$(date +%Y%m%d-%H%M%S)"
    local snapshot_name="pre-$update_name"
    
    log "=== Preparazione aggiornamento sicuro ==="
    
    # 1. Crea snapshot pre-aggiornamento
    if ! zfs snapshot "$ZFS_ROOT/calvuz@$snapshot_name"; then
        log "✗ Errore creazione snapshot pre-aggiornamento"
        return 1
    fi
    
    # 2. Crea Boot Environment di rollback
    if ! create_refind_boot_environment "rollback-$update_name" "$snapshot_name" "Sistema di Rollback"; then
        log "✗ Errore creazione Boot Environment di rollback"
        return 1
    fi
    
    # 3. Crea ambiente di recovery
    create_recovery_environment
    
    log "✓ Sistema preparato per aggiornamento sicuro"
    log "  Snapshot: $snapshot_name"
    log "  BE Rollback: rollback-$update_name"
    log "  Procedere con l'aggiornamento del sistema"
    log "  Al riavvio saranno disponibili le opzioni di recovery nel menu rEFInd"
    
    return 0
}

# Verifica post-aggiornamento
verify_post_update() {
    log "=== Verifica post-aggiornamento ==="
    
    # Test di integrità di base
    local tests=(
        "test -d /bin"
        "test -d /usr"
        "test -d /etc"
        "systemctl --version >/dev/null 2>&1"
        "which bash >/dev/null 2>&1"
        "zfs version >/dev/null 2>&1"
        "nvidia-smi >/dev/null 2>&1 || true"  # Test GPU se presente
    )
    
    local failed_tests=0
    local total_tests=${#tests[@]}
    
    for test_cmd in "${tests[@]}"; do
        if eval "$test_cmd"; then
            vlog "✓ Test superato: $test_cmd"
        else
            log "✗ Test fallito: $test_cmd"
            ((failed_tests++))
        fi
    done
    
    if [[ $failed_tests -eq 0 ]]; then
        log "✓ Sistema aggiornato correttamente ($total_tests/$total_tests test superati)"
        
        # Pulizia BE temporanei se tutto ok
        echo
        read -p "Eliminare i Boot Environment temporanei? (s/N): " cleanup
        if [[ "$cleanup" =~ ^[Ss]$ ]]; then
            cleanup_temporary_environments
        fi
        
        return 0
    else
        log "✗ Sistema instabile ($failed_tests/$total_tests test falliti)"
        log "  Utilizzare il menu rEFInd per tornare al sistema precedente"
        return 1
    fi
}

# Pulisce ambienti temporanei
cleanup_temporary_environments() {
    log "=== Pulizia ambienti temporanei ==="
    
    local cleaned=0
    local current_timestamp=$(date +%s)
    
    # Trova e rimuove BE temporanei
    while read -r dataset; do
        if [[ "$dataset" =~ ^${ZFS_ROOT}/(${BE_PREFIX}-rollback-|${BE_PREFIX}-recovery-|backup-) ]]; then
            local be_name="${dataset#$ZFS_ROOT/${BE_PREFIX}-}"
            [[ "$dataset" =~ ^${ZFS_ROOT}/backup- ]] && be_name="${dataset#$ZFS_ROOT/}"
            
            local creation=$(zfs get -H -o value creation "$dataset")
            
            # Conversione sicura della data ZFS al timestamp Unix
            local creation_timestamp=""
            
            # ZFS può restituire diversi formati di data, gestiamoli tutti
            if [[ "$creation" =~ ^[A-Za-z]{3}\ [A-Za-z]{3}\ [0-9]{1,2}\ [0-9]{1,2}:[0-9]{2}\ [0-9]{4}$ ]]; then
                # Formato: "Mon Jan 21 14:30 2025"
                creation_timestamp=$(date -d "$creation" +%s 2>/dev/null)
            elif [[ "$creation" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{1,2}:[0-9]{2}:[0-9]{2}$ ]]; then
                # Formato: "2025-01-21 14:30:45"
                creation_timestamp=$(date -d "$creation" +%s 2>/dev/null)
            elif [[ "$creation" =~ ^[A-Za-z]{3}\ [A-Za-z]{3}\ [0-9]{1,2}\ [0-9]{1,2}:[0-9]{2}:[0-9]{2}\ [0-9]{4}$ ]]; then
                # Formato: "Mon Jan 21 14:30:45 2025"
                creation_timestamp=$(date -d "$creation" +%s 2>/dev/null)
            else
                # Prova conversione diretta per altri formati
                creation_timestamp=$(date -d "$creation" +%s 2>/dev/null)
            fi
            
            # Se la conversione fallisce, salta questo dataset
            if [[ -z "$creation_timestamp" || "$creation_timestamp" == "" ]]; then
                vlog "⚠️  Impossibile determinare l'età di $dataset (creazione: $creation)"
                continue
            fi
            
            # Calcola l'età in giorni
            local age_seconds=$((current_timestamp - creation_timestamp))
            local age_days=$((age_seconds / 86400))
            
            # Debug info
            vlog "Dataset: $dataset"
            vlog "  Creazione: $creation"
            vlog "  Timestamp: $creation_timestamp"
            vlog "  Età: $age_days giorni"
            
            # Rimuove BE più vecchi di 7 giorni
            if [[ $age_days -gt 7 ]]; then
                echo "Rimozione $dataset (età: $age_days giorni)"
                read -p "Confermi rimozione di $be_name? (s/N): " confirm
                if [[ "$confirm" =~ ^[Ss]$ ]]; then
                    if [[ "$dataset" =~ ^${ZFS_ROOT}/${BE_PREFIX}- ]]; then
                        destroy_refind_boot_environment "$be_name"
                    else
                        if zfs destroy "$dataset"; then
                            ((cleaned++))
                            log "✓ Rimosso: $dataset"
                        else
                            log "✗ Errore rimozione: $dataset"
                        fi
                    fi
                else
                    log "Saltato: $dataset"
                fi
            else
                vlog "Mantenuto: $dataset (troppo recente: $age_days giorni)"
            fi
        fi
    done < <(zfs list -H -o name | grep "^$ZFS_ROOT/")
    
    log "✓ Pulizia completata: $cleaned ambienti rimossi"
}

# ========== FUNZIONI BOOT ENVIRONMENT GENERICHE ==========

# Funzione per il countdown del riavvio
countdown_reboot() {
    local seconds=10
    echo ""
    echo "🚀 RIAVVIO AUTOMATICO TRA $seconds SECONDI..."
    echo "   (Premi Ctrl+C per annullare)"
    echo ""
    
    for ((i=seconds; i>0; i--)); do
        printf "\r⏱️  Riavvio in: %2d secondi" $i
        sleep 1
    done
    
    echo ""
    echo "🔄 Riavvio in corso..."
    reboot
}

# Funzione principale per la promozione Boot Environment
promote_boot_environment() {
    local be_name="$1"
    
    if [[ -z "$be_name" ]]; then
        list_boot_environments
        echo ""
        read -p "📝 Inserisci il nome del Boot Environment da promuovere: " be_name
    fi
    
    local be_dataset="$ZFS_ROOT/${BE_PREFIX}-$be_name"
    local current_dataset=$(mount | grep " on / type zfs" | cut -d' ' -f1)
    
    # Verifica esistenza del Boot Environment
    if ! zfs list "$be_dataset" &>/dev/null; then
        echo "❌ Boot Environment '$be_name' non trovato"
        return 1
    fi
    
    # Controlla se è già attivo
    if [[ "$current_dataset" == "$be_dataset" ]]; then
        echo "ℹ️  Boot Environment '$be_name' è già attivo"
        return 0
    fi
    
    echo ""
    echo "🔄 PROMOZIONE BOOT ENVIRONMENT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Sistema attuale: $current_dataset"
    echo "📍 Nuovo sistema:   $be_dataset"
    echo ""
    
    # Crea snapshot di sicurezza del sistema attuale
    local safety_snapshot="${current_dataset}@pre-promotion-$(date +%Y%m%d-%H%M%S)"
    echo "📸 Creazione snapshot di sicurezza..."
    if ! zfs snapshot "$safety_snapshot"; then
        echo "❌ Errore nella creazione dello snapshot di sicurezza"
        return 1
    fi
    echo "✅ Snapshot creato: $safety_snapshot"
    
    # Verifica che l'utente sia sicuro
    echo ""
    echo "⚠️  ATTENZIONE: Questa operazione richiede un riavvio del sistema"
    echo "   - Il sistema attuale diventerà non-bootabile automaticamente"
    echo "   - Il nuovo Boot Environment diventerà il sistema principale"
    echo "   - Uno snapshot di sicurezza è stato creato: $(basename $safety_snapshot)"
    echo ""
    
    read -p "🤔 Continuare con la promozione? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        echo "⏹️  Operazione annullata"
        zfs destroy "$safety_snapshot" 2>/dev/null || true
        return 1
    fi
    
    # Strategia migliorata: Configura mountpoint e riavvia
    echo ""
    echo "🔧 CONFIGURAZIONE SISTEMA..."
    
    # Prima rinomina per evitare conflitti (se necessario)
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="backup-current-${timestamp}"
    
    if [[ "$current_dataset" == "$ZFS_ROOT/calvuz" ]]; then
        echo "🔄 Rinomina dataset attuale in backup..."
        if ! zfs rename "$current_dataset" "$ZFS_ROOT/${backup_name}"; then
            echo "❌ Errore nella rinomina del dataset corrente"
            return 1
        fi
        current_dataset="$ZFS_ROOT/${backup_name}"
        echo "✅ Dataset rinominato: $current_dataset"
    fi
    
    # Configura mountpoint in modo sicuro
    if ! configure_safe_mountpoints "$current_dataset" "$be_dataset"; then
        echo "❌ Errore nella configurazione dei mountpoint"
        return 1
    fi
    
    # Rinomina il Boot Environment promosso al nome standard
    echo "🔄 Rinomina Boot Environment al nome standard..."
    if ! zfs rename "$be_dataset" "$ZFS_ROOT/calvuz"; then
        echo "❌ Errore nella rinomina del Boot Environment"
        return 1
    fi
    be_dataset="$ZFS_ROOT/calvuz"
    echo "✅ Boot Environment rinominato: $be_dataset"
    
    echo ""
    echo "✅ CONFIGURAZIONE COMPLETATA"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 Sistema backup:  $current_dataset"
    echo "📍 Sistema nuovo:   $be_dataset"
    echo "📸 Snapshot:        $safety_snapshot"
    echo ""
    echo "🔄 RIAVVIO NECESSARIO per completare la promozione"
    echo ""
    
    read -p "🚀 Riavviare ora? (S/n): " reboot_confirm
    if [[ ! "$reboot_confirm" =~ ^[Nn]$ ]]; then
        countdown_reboot
    else
        echo ""
        echo "⏸️  Riavvio posticipato"
        echo "💡 Per completare la promozione esegui: sudo reboot"
        echo ""
    fi
}

# Funzione per verificare se siamo dopo un riavvio di promozione
check_promotion_status() {
    local expected_dataset="$ZFS_ROOT/calvuz"
    local current_root=$(mount | grep " on / type zfs" | cut -d' ' -f1)
    
    # Se il root corrente è diverso dal dataset standard, potremmo essere in post-promozione
    if [[ "$current_root" != "$expected_dataset" ]] && zfs list "$expected_dataset" &>/dev/null; then
        local expected_mountpoint=$(zfs get -H -o value mountpoint "$expected_dataset")
        if [[ "$expected_mountpoint" == "/" ]]; then
            echo ""
            echo "🔍 VERIFICA POST-PROMOZIONE"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            verify_boot_success "$expected_dataset"
            echo ""
        fi
    fi
}

# ========== MENU REFIND FUNCTIONS ==========

# Menu specifico per gestione Boot Environment rEFInd
show_refind_menu() {
    clear
    if command -v figlet >/dev/null 2>&1; then
        figlet "rEFInd BE Manager"
    else
        echo "=============== rEFInd BOOT ENVIRONMENT MANAGER ==============="
    fi
    
    echo
    echo "GESTIONE BOOT ENVIRONMENT:"
    echo " 1) Lista Boot Environment"
    echo " 2) Crea Boot Environment da snapshot"
    echo " 3) Attiva Boot Environment"
    echo " 4) Elimina Boot Environment"
    echo " 5) Crea ambiente di recovery"
    echo
    echo "AGGIORNAMENTO SICURO:"
    echo " 6) Prepara aggiornamento sicuro"
    echo " 7) Verifica post-aggiornamento"
    echo " 8) Pulisci ambienti temporanei"
    echo
    echo "CONFIGURAZIONE rEFInd:"
    echo " 9) Backup configurazione rEFInd"
    echo " R) Ripristina configurazione rEFInd"
    echo " C) Pulisci entry Boot Environment"
    echo " I) Setup/Verifica include Boot Environment"
    echo " V) Visualizza file configurazione BE"
    echo
    echo " 0) Torna al menu principale"
    echo
}

# ========== INTEGRAZIONE CON MENU PRINCIPALE ==========

# Aggiunge le opzioni rEFInd al menu principale esistente
add_refind_options_to_main_menu() {
    # Questa funzione dovrebbe essere chiamata dal menu principale
    echo "rEFInd BOOT ENVIRONMENTS:"
    echo " E) Gestione Boot Environment rEFInd"
    echo " U) Aggiornamento sicuro (rEFInd)"
}

# Handler per il menu rEFInd
handle_refind_menu() {
    while true; do
        show_refind_menu
        read -n 1 -r -p "Scegli un'opzione: " choice
        echo
        
        case $choice in
            1)
                list_refind_boot_environments
                ;;
            2)
                echo
                read -p "Nome Boot Environment: " be_name
                read -p "Nome snapshot sorgente: " snapshot_name
                read -p "Descrizione (opzionale): " description
                create_refind_boot_environment "$be_name" "$snapshot_name" "$description"
                ;;
            3)
                echo
                echo "Boot Environment disponibili:"
                list_refind_boot_environments | grep "✓.*${BE_PREFIX}-" | head -10
                echo
                read -p "Nome Boot Environment da attivare: " be_name
                echo "ATTENZIONE: Il sistema attuale sarà spostato in backup!"
                read -p "Confermi? (s/N): " confirm
                [[ "$confirm" =~ ^[Ss]$ ]] && activate_refind_boot_environment "$be_name"
                ;;
            4)
                echo
                list_refind_boot_environments | grep "✓.*${BE_PREFIX}-" | head -10
                echo
                read -p "Nome Boot Environment da eliminare: " be_name
                echo "ATTENZIONE: Questa operazione è irreversibile!"
                read -p "Confermi eliminazione di '$be_name'? (s/N): " confirm
                [[ "$confirm" =~ ^[Ss]$ ]] && destroy_refind_boot_environment "$be_name"
                ;;
            5)
                create_recovery_environment
                ;;
            6)
                prepare_safe_update
                ;;
            7)
                verify_post_update
                ;;
            8)
                cleanup_temporary_environments
                ;;
            9)
                backup_refind_config
                ;;
            [Rr])
                echo
                read -p "Ripristinare configurazione rEFInd dal backup? (s/N): " confirm
                [[ "$confirm" =~ ^[Ss]$ ]] && restore_refind_config
                ;;
            [Cc])
                echo
                read -p "Rimuovere tutte le entry Boot Environment da rEFInd? (s/N): " confirm
                [[ "$confirm" =~ ^[Ss]$ ]] && clean_be_entries
                ;;
            [Ii])
                setup_refind_include
                ;;
            [Vv])
                echo
                if [[ -f "$REFIND_BE_CONF" ]]; then
                    echo "=== Contenuto $REFIND_BE_CONF ==="
                    cat "$REFIND_BE_CONF"
                else
                    echo "File Boot Environment non trovato: $REFIND_BE_CONF"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                echo "Opzione non valida! Riprova."
                ;;
        esac
        
        # Pausa dopo le operazioni
        if [[ ! "$choice" =~ ^[0]$ ]]; then
            echo -e "\nPremere Enter per continuare..."
            read
        fi
    done
}

# ========== MENU FUNCTIONS ==========

# Mostra il menu principale
show_menu() {
    clear
    if command -v figlet >/dev/null 2>&1; then
        figlet "ZFS Management"
    else
        echo "==================== ZFS MANAGEMENT ===================="
    fi
    
    echo
    echo "SNAPSHOT AUTOMATION:"
    echo " 1) Crea snapshot automatici"
    echo " 2) Pulisci snapshot automatici vecchi"
    echo " 3) Esegui automazione completa (crea + pulisci)"
    echo " P) PURGE: Elimina TUTTI gli snapshot automatici"
    echo
    echo "BETA SYSTEM:"
    echo " 4) Crea snapshot di produzione"
    echo " 5) Popola dataset beta"
    echo " 6) Promuovi beta"
    echo " 7) Sposta beta in produzione"
    echo " 8) Elimina dataset legacy"
    echo " 9) ELIMINA dataset beta"
    echo
    echo "BOOT ENVIRONMENT:"
    echo " B) Lista Boot Environment"
    echo " N) Crea nuovo Boot Environment"
    echo " A) Attiva Boot Environment"
    echo " D) Elimina Boot Environment"
    echo
    echo "UTILITY:"
    echo " s) Mostra stato dei dataset"
    echo " l) Mostra ultimi log"
    echo " v) Toggle modalità verbose [$([[ $VERBOSE -eq 1 ]] && echo "ON" || echo "OFF")]"
    echo " 0) Esci"
    echo
    echo "rEFInd BOOT ENVIRONMENTS:"
    echo " E) Gestione Boot Environment rEFInd"
    echo " U) Aggiornamento sicuro (rEFInd)"
    echo
}

# Mostra lo stato corrente di tutti i dataset
show_status() {
    echo "==================== STATO DATASET ===================="
    
    echo "PRODUZIONE:"
    for dataset in "${DATASETS[@]}"; do
        local full_dataset="$POOL/$dataset"
        if dataset_exists "$full_dataset"; then
            local used=$(zfs get -H -o value used "$full_dataset" 2>/dev/null || echo "N/A")
            echo "  ✓ $full_dataset (utilizzato: $used)"
        else
            echo "  ✗ $full_dataset"
        fi
    done
    
    echo -e "\nBETA:"
    local beta_exists=false
    for dataset in "${DATASETS[@]}"; do
        local beta_name
        case "$dataset" in
            "ROOT/"*)
                beta_name="$POOL/ROOT/${BETA_PREFIX}${dataset#ROOT/}"
                ;;
            "data/"*)
                beta_name="$POOL/data/${BETA_PREFIX}${dataset#data/}"
                ;;
            *)
                beta_name="$POOL/${BETA_PREFIX}$dataset"
                ;;
        esac
        
        if dataset_exists "$beta_name"; then
            local used=$(zfs get -H -o value used "$beta_name" 2>/dev/null || echo "N/A")
            echo "  ✓ $beta_name (utilizzato: $used)"
            beta_exists=true
        fi
    done
    [[ "$beta_exists" == "false" ]] && echo "  Nessun dataset beta trovato"
    
    echo -e "\nLEGACY:"
    local legacy_exists=false
    for dataset in "${DATASETS[@]}"; do
        local legacy_name
        case "$dataset" in
            "ROOT/"*)
                legacy_name="$POOL/ROOT/${LEGACY_PREFIX}${dataset#ROOT/}"
                ;;
            "data/"*)
                legacy_name="$POOL/data/${LEGACY_PREFIX}${dataset#data/}"
                ;;
            *)
                legacy_name="$POOL/${LEGACY_PREFIX}$dataset"
                ;;
        esac
        
        if dataset_exists "$legacy_name"; then
            local used=$(zfs get -H -o value used "$legacy_name" 2>/dev/null || echo "N/A")
            echo "  ✓ $legacy_name (utilizzato: $used)"
            legacy_exists=true
        fi
    done
    [[ "$legacy_exists" == "false" ]] && echo "  Nessun dataset legacy trovato"
    
    echo -e "\nBOOT ENVIRONMENT:"
    local be_exists=false
    while read -r dataset; do
        if [[ "$dataset" =~ ^${ZFS_ROOT}/${BE_PREFIX}- ]] || [[ "$dataset" =~ ^${ZFS_ROOT}/backup- ]]; then
            local used=$(zfs get -H -o value used "$dataset" 2>/dev/null || echo "N/A")
            local be_name="${dataset#$ZFS_ROOT/}"
            echo "  ✓ $be_name (utilizzato: $used)"
            be_exists=true
        fi
    done < <(zfs list -H -o name | grep "^$ZFS_ROOT/")
    [[ "$be_exists" == "false" ]] && echo "  Nessun Boot Environment trovato"
    
    echo -e "\nSNAPSHOT AUTOMATICI RECENTI:"
    local recent_auto=$(zfs list -t snapshot -o name,creation,used -s creation 2>/dev/null | \
                       grep "@${SNAPSHOT_PREFIX}-" | tail -5)
    if [[ -n "$recent_auto" ]]; then
        echo "$recent_auto"
    else
        echo "  Nessuno snapshot automatico trovato"
    fi
    
    echo -e "\nSNAPSHOT DI SISTEMA:"
    local system_snaps=$(zfs list -t snapshot -o name,creation,used -s creation 2>/dev/null | \
                         grep -v "@${SNAPSHOT_PREFIX}-" | grep "^$POOL/" | tail -5)
    if [[ -n "$system_snaps" ]]; then
        echo "$system_snaps"
    else
        echo "  Nessuno snapshot di sistema trovato"
    fi
    
    echo -e "\nPremere Enter per continuare..."
    read
}

# Mostra gli ultimi log
show_logs() {
    echo "==================== ULTIMI LOG ===================="
    if [[ -f "$LOG_FILE" ]]; then
        tail -30 "$LOG_FILE"
    else
        echo "Nessun file di log trovato in: $LOG_FILE"
    fi
    echo -e "\nPremere Enter per continuare..."
    read
}

# Toggle della modalità verbose
toggle_verbose() {
    if [[ $VERBOSE -eq 0 ]]; then
        VERBOSE=1
        echo "Modalità verbose ATTIVATA"
        log "Modalità verbose attivata dall'utente"
    else
        VERBOSE=0
        echo "Modalità verbose DISATTIVATA"
        log "Modalità verbose disattivata dall'utente"
    fi
    sleep 1
}

# ========== FUNZIONI BOOT ENVIRONMENT GENERICHE PER MENU ==========

# Crea nuovo Boot Environment generico
create_new_boot_environment() {
    echo
    echo "=== Creazione nuovo Boot Environment ==="
    
    # Mostra snapshot disponibili
    echo "Snapshot disponibili:"
    zfs list -t snapshot -H -o name | grep "^$ZFS_ROOT/calvuz@" | while read -r snap; do
        local snap_name="${snap#$ZFS_ROOT/calvuz@}"
        local creation=$(zfs get -H -o value creation "$snap" 2>/dev/null || echo "N/A")
        echo "  📸 $snap_name - $creation"
    done
    
    echo
    read -p "Nome del nuovo Boot Environment: " be_name
    read -p "Nome snapshot sorgente: " snapshot_name
    read -p "Descrizione (opzionale): " description
    
    if [[ -z "$be_name" || -z "$snapshot_name" ]]; then
        echo "❌ Nome Boot Environment e snapshot sono obbligatori"
        return 1
    fi
    
    local be_dataset="$ZFS_ROOT/${BE_PREFIX}-$be_name"
    local source_snapshot="$ZFS_ROOT/calvuz@$snapshot_name"
    
    # Verifica che lo snapshot sorgente esista
    if ! zfs list "$source_snapshot" >/dev/null 2>&1; then
        echo "❌ Snapshot sorgente non trovato: $source_snapshot"
        return 1
    fi
    
    # Verifica che il BE non esista già
    if dataset_exists "$be_dataset"; then
        echo "❌ Boot Environment già esistente: $be_name"
        return 1
    fi
    
    # Crea clone dal snapshot
    if ! zfs clone "$source_snapshot" "$be_dataset"; then
        echo "❌ Errore creazione clone per BE: $be_name"
        return 1
    fi
    
    # Configura proprietà del BE
    zfs set canmount=noauto "$be_dataset"
    zfs set mountpoint=none "$be_dataset"
    
    echo "✅ Boot Environment creato con successo: $be_name"
    echo "  Dataset: $be_dataset"
    echo "  Sorgente: $source_snapshot"
    echo "  Descrizione: ${description:-N/A}"
    
    return 0
}

# Attiva Boot Environment generico
activate_boot_environment() {
    echo
    echo "=== Attivazione Boot Environment ==="
    
    # Mostra BE disponibili
    echo "Boot Environment disponibili:"
    list_boot_environments | grep "✓.*${BE_PREFIX}-" | head -10
    
    echo
    read -p "Nome Boot Environment da attivare: " be_name
    
    if [[ -z "$be_name" ]]; then
        echo "❌ Nome Boot Environment obbligatorio"
        return 1
    fi
    
    echo "ATTENZIONE: Il sistema attuale sarà spostato in backup!"
    echo "Questa operazione richiede un riavvio del sistema."
    read -p "Confermi l'attivazione di '$be_name'? (s/N): " confirm
    
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        promote_boot_environment "$be_name"
    else
        echo "Operazione annullata"
    fi
}

# Elimina Boot Environment generico
destroy_boot_environment() {
    echo
    echo "=== Eliminazione Boot Environment ==="
    
    # Mostra BE disponibili
    echo "Boot Environment disponibili:"
    list_boot_environments | grep "✓.*${BE_PREFIX}-" | head -10
    
    echo
    read -p "Nome Boot Environment da eliminare: " be_name
    
    if [[ -z "$be_name" ]]; then
        echo "❌ Nome Boot Environment obbligatorio"
        return 1
    fi
    
    local be_dataset="$ZFS_ROOT/${BE_PREFIX}-$be_name"
    
    if ! dataset_exists "$be_dataset"; then
        echo "❌ Boot Environment non trovato: $be_name"
        return 1
    fi
    
    echo "ATTENZIONE: Questa operazione è irreversibile!"
    echo "Dataset da eliminare: $be_dataset"
    read -p "Confermi eliminazione di '$be_name'? (s/N): " confirm
    
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        if zfs destroy "$be_dataset"; then
            echo "✅ Boot Environment eliminato: $be_name"
        else
            echo "❌ Errore eliminazione Boot Environment: $be_name"
        fi
    else
        echo "Operazione annullata"
    fi
}

# ========== MAIN EXECUTION ==========

# Automazione completa (snapshot + pulizia)
run_automation() {
    log "==================== AVVIO AUTOMAZIONE COMPLETA ZFS ===================="
    create_automated_snapshots
    cleanup_old_snapshots
    log "==================== AUTOMAZIONE COMPLETA TERMINATA ===================="
}

# Mostra l'aiuto
show_help() {
    cat << EOF
ZFS Management Script v$VERSION - Aiuto

UTILIZZO:
  $0 [opzioni] [comando]

OPZIONI:
  -v, --verbose    Abilita output dettagliato
  -h, --help       Mostra questo aiuto

COMANDI:
  auto             Esegue automazione completa (crea snapshot + pulizia)
  create           Crea solo snapshot automatici
  cleanup          Esegue solo pulizia snapshot vecchi
  purge            Rimuove TUTTI gli snapshot automatici (ATTENZIONE!)
  interactive      Avvia menu interattivo (default)

ESEMPI:
  $0 auto                    # Automazione per cron
  $0 -v create              # Crea snapshot con output verbose
  $0 --verbose interactive  # Menu interattivo con modalità verbose

CONFIGURAZIONE:
  Pool ZFS: $POOL
  Dataset: ${DATASETS[*]}
  Retention: $RETENTION_DAYS giorni
  Max snapshot: $MAX_SNAPSHOTS per dataset
  Log file: $LOG_FILE

Per maggiori dettagli, consultare i commenti nel codice sorgente.
EOF
}

# Parsing degli argomenti della riga di comando
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            auto|automation)
                run_automation
                exit 0
                ;;
            create)
                create_automated_snapshots
                exit 0
                ;;
            cleanup)
                cleanup_old_snapshots
                exit 0
                ;;
            purge)
                echo "ATTENZIONE: Questa operazione rimuoverà TUTTI gli snapshot automatici!"
                read -p "Confermi l'operazione? (scrivi 'CONFERMA'): " confirm
                if [[ "$confirm" == "CONFERMA" ]]; then
                    purge_all_auto_snapshots
                else
                    echo "Operazione annullata."
                fi
                exit 0
                ;;
            interactive)
                # Modalità interattiva (default), continua con il menu
                break
                ;;
            *)
                echo "Argomento sconosciuto: $1"
                echo "Usa $0 --help per l'aiuto"
                exit 1
                ;;
        esac
    done
}

# ========== MAIN PROGRAM ==========

# Controlli preliminari
check_root
init_logging

# Log di avvio
log "==================== AVVIO ZFS MANAGEMENT SCRIPT ===================="
log "Versione script: $VERSION"
log "Pool ZFS: $POOL"
log "ZFS Root: $ZFS_ROOT"
log "Modalità verbose: $([[ $VERBOSE -eq 1 ]] && echo "ATTIVA" || echo "DISATTIVA")"

# Parsing argomenti
parse_arguments "$@"

# Check promotion status
check_promotion_status

# Menu interattivo (default)
while true; do
    show_menu
    read -n 1 -r -p "Scegli un'opzione: " choice
    echo
    
    case $choice in
        1)
            create_automated_snapshots
            ;;
        2)
            cleanup_old_snapshots
            ;;
        3)
            run_automation
            ;;
        [Pp])
            echo
            echo "ATTENZIONE: Questa operazione eliminerà TUTTI gli snapshot automatici!"
            echo "Gli snapshot di sistema (beta/produzione/legacy) saranno preservati."
            read -p "Confermi l'operazione? (scrivi 'PURGE'): " confirm
            if [[ "$confirm" == "PURGE" ]]; then
                purge_all_auto_snapshots
            else
                echo "Operazione annullata."
            fi
            ;;
        4)
            echo
            read -p "Nome snapshot (default: $SNAPSHOT_NAME): " input_name
            create_production_snapshots "${input_name:-$SNAPSHOT_NAME}"
            ;;
        5)
            echo
            read -p "Nome snapshot da clonare (default: $SNAPSHOT_NAME): " input_name
            populate_betas "${input_name:-$SNAPSHOT_NAME}"
            ;;
        6)
            promote_betas
            ;;
        7)
            echo
            echo "ATTENZIONE: Questa operazione sposterà i dataset beta in produzione!"
            read -p "Confermi? (s/N): " confirm
            [[ "$confirm" =~ ^[Ss]$ ]] && rename_to_production
            ;;
        8)
            echo
            echo "ATTENZIONE: Questa operazione eliminerà tutti i dataset legacy!"
            read -p "Confermi? (s/N): " confirm
            [[ "$confirm" =~ ^[Ss]$ ]] && destroy_legacy
            ;;
        9)
            echo
            echo "ATTENZIONE: Questa operazione eliminerà tutti i dataset beta!"
            read -p "Confermi? (s/N): " confirm
            [[ "$confirm" =~ ^[Ss]$ ]] && destroy_betas
            ;;
        [Bb])
            list_boot_environments
            ;;
        [Nn])
            create_new_boot_environment
            ;;
        [Aa])
            activate_boot_environment
            ;;
        [Dd])
            destroy_boot_environment
            ;;
        [sS])
            show_status
            ;;
        [lL])
            show_logs
            ;;
        [vV])
            toggle_verbose
            ;;
        [Ee])
            handle_refind_menu
            ;;
        [Uu])
            prepare_safe_update
            ;;
        0)
            log "Script terminato dall'utente"
            echo "Arrivederci!"
            exit 0
            ;;
        *)
            echo "Opzione non valida! Riprova."
            ;;
    esac
    
    # Pausa dopo le operazioni (eccetto per status, logs e verbose toggle)
    if [[ ! "$choice" =~ ^[sSlLvV]$ ]]; then
        echo -e "\nPremere Enter per continuare..."
        read
    fi
done
