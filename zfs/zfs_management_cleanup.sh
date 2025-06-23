#!/bin/bash
#
# Pulizia degli snapshots vari
BASELINE="@baseline"

set -e

echo "🧹 PULIZIA SNAPSHOT ZFS"
echo "======================="

# Backup di sicurezza
#echo "📸 Creazione snapshot di sicurezza..."
#sudo zfs snapshot zcalvuz/ROOT/calvuz@emergency-backup-$(date +%Y%m%d-%H%M)

# Lista snapshot da rimuovere
echo "📋 Snapshot baseline da rimuovere:"
zfs list -t snapshot -H -o name | grep "$BASELINE"

echo
read -p "🤔 Procedere con la rimozione? (s/N): " confirm

if [[ "$confirm" =~ ^[Ss]$ ]]; then
    echo "🗑️  Rimozione in corso..."
    
    zfs list -t snapshot -H -o name | grep "@baseline-" | while read snap; do
        echo "   Removing: $snap"
        sudo zfs destroy "$snap" 2>/dev/null || echo "   ⚠️ Errore: $snap"
    done
    
    echo "✅ Pulizia completata!"
    echo "📊 Stato finale:"
#    zfs list -t snapshot | grep -v "@emergency-backup"
else
    echo "❌ Operazione annullata"
fi
