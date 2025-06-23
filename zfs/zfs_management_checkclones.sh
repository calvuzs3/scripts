#!/bin/bash
# save as: check_zfs_clones.sh

set -e

echo "🔍 ZFS CLONE DEPENDENCY CHECKER"
echo "================================"

# Funzione per controllare se uno snapshot ha cloni
check_snapshot_clones() {
    local snapshot="$1"
    local clones=$(zfs get -H -o value clones "$snapshot" 2>/dev/null || echo "-")
    echo "$clones"
}

# Funzione per controllare se un dataset è un clone
check_dataset_origin() {
    local dataset="$1"
    local origin=$(zfs get -H -o value origin "$dataset" 2>/dev/null || echo "-")
    echo "$origin"
}

echo -e "\n📊 ANALISI COMPLETA SISTEMA:"

# Controlla tutti i tuoi snapshot specifici
SNAPSHOTS=($(zfs list -t snapshot -o name | grep -v "^NAME"))

echo "🎯 SNAPSHOT ANALYSIS:"
safe_to_delete=()
has_clones=()

for snapshot in "${SNAPSHOTS[@]}"; do
    if zfs list "$snapshot" >/dev/null 2>&1; then
        clones=$(check_snapshot_clones "$snapshot")
        if [[ "$clones" == "-" ]]; then
            echo "  ✅ $snapshot (safe to delete)"
            safe_to_delete+=("$snapshot")
        else
            echo "  ⚠️  $snapshot (has clones: $clones)"
            has_clones+=("$snapshot")
        fi
    else
        echo "  ❌ $snapshot (not found)"
    fi
done

# Controlla dataset backup
echo -e "\n🗂️  BACKUP DATASET ANALYSIS:"
DATASETS=($(zfs list -t snapshot -o name | grep -v "^NAME" | grep "backup"))

for dataset in "${DATASETS[@]}"; do
    if zfs list "$dataset" >/dev/null 2>&1; then
        origin=$(check_dataset_origin "$dataset")
        if [[ "$origin" == "-" ]]; then
            echo "  ✅ $dataset (independent dataset, safe to delete)"
        else
            echo "  📎 $dataset (clone of: $origin)"
        fi
    else
        echo "  ❌ $dataset (not found)"
    fi
done

# Riassunto
echo -e "\n📋 SUMMARY:"
echo "Safe to delete snapshots: ${#safe_to_delete[@]}"
echo "Snapshots with clones: ${#has_clones[@]}"

if [[ ${#has_clones[@]} -eq 0 ]]; then
    echo -e "\n🎉 ALL CLEAR! All snapshots are safe to delete."
    echo "You can proceed with cleanup."
else
    echo -e "\n⚠️  WARNING! Some snapshots have dependent clones."
    echo "You must handle the clones first."
fi

echo -e "\n💡 Next steps:"
echo "1. Run this script to verify"
echo "2. Create safety snapshot: zfs snapshot zcalvuz/ROOT/calvuz@safety-\$(date +%Y%m%d-%H%M%S)"
echo "3. Proceed with deletion of safe snapshots"
