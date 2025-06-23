#!/usr/bin/env zsh

# ==================== BATCH STOPS GENERATOR WITH SHIFTS ====================
# Genera pacchetti di fermate ricorrenti ottimizzate per turni continui
# Perfetto per pianificazione manutenzioni e fermate programmate

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_help() {
    echo "${YELLOW}Batch Stops Generator - Shift Optimized${NC}"
    echo "Genera pacchetti di fermate ricorrenti ottimizzate per turni continui"
    echo ""
    echo "${YELLOW}Usage:${NC}"
    echo "  $0 <pattern> <start_date> <count> [output.json]"
    echo ""
    echo "${YELLOW}Patterns Ottimizzati per Turni:${NC}"
    echo "  ${BLUE}weekly-maintenance${NC}    - Manutenzione ogni lunedì notte (22:00)"
    echo "  ${BLUE}monthly-shutdown${NC}      - Fermata mensile weekend (sabato)"
    echo "  ${BLUE}shift-cleaning${NC}        - Pulizie tra turni (3x/settimana)"
    echo "  ${BLUE}night-maintenance${NC}     - Manutenzione solo turni notte"
    echo "  ${BLUE}weekend-deep-clean${NC}    - Pulizie weekend approfondite"
    echo "  ${BLUE}minimal-impact${NC}        - Fermate con impatto minimo"
    echo "  ${BLUE}emergency-drills${NC}      - Simulazioni emergenza (mensili)"
    echo ""
    echo "${YELLOW}Configurazione Turni:${NC}"
    echo "  🌅 Mattino:    06:00-14:00 (12 operatori)"
    echo "  🌇 Pomeriggio: 14:00-22:00 (12 operatori)"
    echo "  🌙 Notte:      22:00-06:00 (12 operatori)"
    echo ""
    echo "${YELLOW}Examples:${NC}"
    echo "  $0 weekly-maintenance 2025-06-16 12"
    echo "  $0 monthly-shutdown 2025-06-01 6 shutdown_2025.json"
    echo "  $0 shift-cleaning 2025-06-15 20 pulizie_turni.json"
    echo "  $0 night-maintenance 2025-06-01 24 maint_notte_anno.json"
}

# Utility functions
log_info() { echo "${BLUE}[INFO]${NC} $1"; }
log_success() { echo "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo "${RED}[ERROR]${NC} $1"; }
log_warning() { echo "${YELLOW}[WARNING]${NC} $1"; }

# UTC timestamp
generate_utc_timestamp() {
    if command -v gdate >/dev/null 2>&1; then
        gdate -u '+%Y-%m-%dT%H:%M:%SZ'
    else
        date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -Iseconds | sed 's/+00:00/Z/'
    fi
}

# Date calculations (cross-platform)
add_days() {
    local base_date="$1"
    local days="$2"
    date -d "$base_date + $days days" +%Y-%m-%d 2>/dev/null || \
    date -j -v+${days}d -f "%Y-%m-%d" "$base_date" +%Y-%m-%d 2>/dev/null
}

add_weeks() {
    local base_date="$1"
    local weeks="$2"
    add_days "$base_date" $((weeks * 7))
}

next_monday() {
    local base_date="$1"
    local dow=$(date -d "$base_date" +%w 2>/dev/null || date -j -f "%Y-%m-%d" "$base_date" +%w 2>/dev/null)
    local days_to_monday=$(((8 - dow) % 7))
    if [[ $days_to_monday -eq 0 ]]; then days_to_monday=7; fi
    add_days "$base_date" $days_to_monday
}

next_saturday() {
    local base_date="$1"
    local dow=$(date -d "$base_date" +%w 2>/dev/null || date -j -f "%Y-%m-%d" "$base_date" +%w 2>/dev/null)
    local days_to_saturday=$(((6 - dow + 7) % 7))
    if [[ $days_to_saturday -eq 0 ]]; then days_to_saturday=7; fi
    add_days "$base_date" $days_to_saturday
}

first_monday_of_month() {
    local year_month="$1"  # Format: YYYY-MM
    local first_day="${year_month}-01"
    local dow=$(date -d "$first_day" +%w 2>/dev/null || date -j -f "%Y-%m-%d" "$first_day" +%w 2>/dev/null)
    local days_to_monday=$(((8 - dow) % 7))
    add_days "$first_day" $days_to_monday
}

# Calculate end time and date
calculate_end_time() {
    local start_time="$1"
    local duration="$2"
    local start_date="$3"

    local start_minutes=$((${start_time%:*} * 60 + ${start_time#*:}))
    local duration_minutes=0

    if [[ "$duration" =~ ^([0-9]+)h$ ]]; then
        duration_minutes=$((${BASH_REMATCH[1]} * 60))
    elif [[ "$duration" =~ ^([0-9]+)m$ ]]; then
        duration_minutes=${BASH_REMATCH[1]}
    elif [[ "$duration" =~ ^([0-9]+)d$ ]]; then
        duration_minutes=$((${BASH_REMATCH[1]} * 24 * 60))
    else
        duration_minutes=240  # Default 4 hours
    fi

    local end_minutes=$((start_minutes + duration_minutes))
    local end_date="$start_date"

    # Handle day overflow
    if [[ $end_minutes -ge 1440 ]]; then
        local days_to_add=$((end_minutes / 1440))
        end_minutes=$((end_minutes % 1440))
        end_date=$(add_days "$start_date" $days_to_add)
    fi

    local end_hours=$((end_minutes / 60))
    local end_mins=$((end_minutes % 60))
    local end_time=$(printf "%02d:%02d" $end_hours $end_mins)

    echo "$end_time $end_date"
}

# Get affected shifts for reporting
get_affected_shifts() {
    local start_time="$1"
    local end_time="$2"

    local start_minutes=$((${start_time%:*} * 60 + ${start_time#*:}))
    local end_minutes=$((${end_time%:*} * 60 + ${end_time#*:}))

    if [[ $end_minutes -lt $start_minutes ]]; then
        end_minutes=$((end_minutes + 1440))
    fi

    local shifts=()

    # Morning: 06:00-14:00 (360-840 minutes)
    if [[ ($start_minutes -lt 840 && $end_minutes -gt 360) ]]; then
        shifts+=("mattino")
    fi

    # Afternoon: 14:00-22:00 (840-1320 minutes)
    if [[ ($start_minutes -lt 1320 && $end_minutes -gt 840) ]]; then
        shifts+=("pomeriggio")
    fi

    # Night: 22:00-06:00 (1320+ minutes)
    if [[ ($start_minutes -ge 1320 || $end_minutes -gt 1320) ]]; then
        shifts+=("notte")
    fi

    echo "${shifts[@]}"
}

# ==================== PATTERN GENERATORS ====================

generate_weekly_maintenance() {
    local start_date="$1"
    local occurrence="$2"

    # Always on Monday night to minimize impact
    local event_date=$(next_monday "$start_date")
    if [[ $occurrence -gt 1 ]]; then
        event_date=$(add_weeks "$event_date" $((occurrence - 1)))
    fi

    local start_time="22:00"  # Night shift
    local duration="6h"
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    local affected_shifts=($(get_affected_shifts "$start_time" "$end_time"))

    cat << EOF
    {
      "id": "weekly_maint_$(echo $event_date | tr -d -)",
      "title": "🔧 Manutenzione Settimanale #$occurrence",
      "description": "Manutenzione preventiva settimanale - lunedì notte per impatto minimo",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "MAINTENANCE",
      "priority": "NORMAL",
      "location": "Tutte le linee produzione",
      "tags": ["manutenzione", "settimanale", "notte", "impatto_minimo"],
      "custom_properties": {
        "department": "Manutenzione",
        "pattern": "weekly-maintenance",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Lunedì notte - impatto minimo turni",
        "affected_shifts": "$(IFS=,; echo "${affected_shifts[*]}")",
        "shift_impact_level": "LOW",
        "workers_affected": "12",
        "optimal_day": "lunedi",
        "maintenance_type": "preventiva_settimanale"
      }
    }
EOF
}

generate_monthly_shutdown() {
    local start_date="$1"
    local occurrence="$2"

    # First Saturday of each month
    local year=$(date -d "$start_date" +%Y 2>/dev/null || date -j -f "%Y-%m-%d" "$start_date" +%Y)
    local month=$(date -d "$start_date" +%m 2>/dev/null || date -j -f "%Y-%m-%d" "$start_date" +%m)

    local target_month=$((month + occurrence - 1))
    local target_year=$year

    while [[ $target_month -gt 12 ]]; do
        target_month=$((target_month - 12))
        target_year=$((target_year + 1))
    done

    local first_day="$(printf "%04d-%02d-01" $target_year $target_month)"
    local event_date=$(next_saturday "$first_day")

    local start_time="08:00"
    local duration="12h"
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    cat << EOF
    {
      "id": "monthly_shutdown_$(echo $event_date | tr -d -)",
      "title": "🏭 Fermata Mensile $(printf "%02d/%04d" $target_month $target_year)",
      "description": "Fermata mensile programmata - weekend per zero impatto produzione",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "STOP_PLANNED",
      "priority": "HIGH",
      "location": "Tutto lo stabilimento",
      "tags": ["fermata_mensile", "weekend", "zero_impatto"],
      "custom_properties": {
        "department": "Produzione",
        "pattern": "monthly-shutdown",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Sabato - zero impatto turni produttivi",
        "affected_shifts": "",
        "shift_impact_level": "NONE",
        "workers_affected": "0",
        "optimal_day": "sabato",
        "shutdown_type": "mensile_programmata"
      }
    }
EOF
}

generate_shift_cleaning() {
    local start_date="$1"
    local occurrence="$2"

    # 3 times per week: Tuesday, Thursday, Saturday
    local days_pattern=(2 4 6)  # Day of week (0=Sunday)
    local pattern_index=$(( (occurrence - 1) % 3 ))
    local weeks_passed=$(( (occurrence - 1) / 3 ))

    local target_day=${days_pattern[$pattern_index]}
    local event_date="$start_date"

    # Find first occurrence of target day
    local current_dow=$(date -d "$start_date" +%w 2>/dev/null || date -j -f "%Y-%m-%d" "$start_date" +%w)
    local days_to_target=$(( (target_day - current_dow + 7) % 7 ))
    event_date=$(add_days "$start_date" $days_to_target)

    # Add weeks
    if [[ $weeks_passed -gt 0 ]]; then
        event_date=$(add_weeks "$event_date" $weeks_passed)
    fi

    local start_time="13:30"  # Between shifts
    local duration="30m"
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    local day_names=("domenica" "lunedì" "martedì" "mercoledì" "giovedì" "venerdì" "sabato")
    local day_name="${day_names[$target_day]}"

    cat << EOF
    {
      "id": "shift_cleaning_$(echo $event_date | tr -d -)",
      "title": "🧹 Pulizia Cambio Turno - $day_name",
      "description": "Pulizia rapida tra turni - impatto minimo su produzione",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "MAINTENANCE",
      "priority": "LOW",
      "location": "Aree produzione principali",
      "tags": ["pulizia", "cambio_turno", "rapida"],
      "custom_properties": {
        "department": "Facility_Management",
        "pattern": "shift-cleaning",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Tra turni - impatto minimo",
        "affected_shifts": "mattino,pomeriggio",
        "shift_impact_level": "MINIMAL",
        "workers_affected": "2",
        "optimal_time": "cambio_turno",
        "cleaning_type": "rapida_tra_turni"
      }
    }
EOF
}

generate_night_maintenance() {
    local start_date="$1"
    local occurrence="$2"

    # Every 2 weeks on Tuesday night
    local base_tuesday=$(next_monday "$start_date")
    base_tuesday=$(add_days "$base_tuesday" 1)  # Tuesday

    local event_date=$(add_weeks "$base_tuesday" $((2 * (occurrence - 1))))

    local start_time="23:00"
    local duration="4h"
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    cat << EOF
    {
      "id": "night_maint_$(echo $event_date | tr -d -)",
      "title": "🌙 Manutenzione Notturna #$occurrence",
      "description": "Manutenzione specializzata durante turno notte - team dedicato",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "MAINTENANCE",
      "priority": "NORMAL",
      "location": "Linee critiche",
      "tags": ["manutenzione", "notte", "specializzata"],
      "custom_properties": {
        "department": "Manutenzione",
        "pattern": "night-maintenance",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Turno notte - produzione ridotta",
        "affected_shifts": "notte",
        "shift_impact_level": "LOW",
        "workers_affected": "12",
        "optimal_time": "turno_notte",
        "maintenance_type": "specializzata_notturna"
      }
    }
EOF
}

generate_weekend_deep_clean() {
    local start_date="$1"
    local occurrence="$2"

    # Every Sunday
    local base_sunday="$start_date"
    local dow=$(date -d "$start_date" +%w 2>/dev/null || date -j -f "%Y-%m-%d" "$start_date" +%w)
    local days_to_sunday=$(( (7 - dow) % 7 ))
    base_sunday=$(add_days "$start_date" $days_to_sunday)

    local event_date=$(add_weeks "$base_sunday" $((occurrence - 1)))

    local start_time="09:00"
    local duration="8h"
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    cat << EOF
    {
      "id": "weekend_deep_$(echo $event_date | tr -d -)",
      "title": "🧽 Pulizia Approfondita Weekend #$occurrence",
      "description": "Pulizia approfondita domenicale - sanificazione completa",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "MAINTENANCE",
      "priority": "NORMAL",
      "location": "Intero stabilimento",
      "tags": ["pulizia", "weekend", "approfondita"],
      "custom_properties": {
        "department": "Facility_Management",
        "pattern": "weekend-deep-clean",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Domenica - zero impatto produzione",
        "affected_shifts": "",
        "shift_impact_level": "NONE",
        "workers_affected": "0",
        "optimal_day": "domenica",
        "cleaning_type": "approfondita_weekend"
      }
    }
EOF
}

generate_minimal_impact() {
    local start_date="$1"
    local occurrence="$2"

    # Various optimal times to truly minimize impact
    local strategies=("22:30" "13:45" "05:30")
    local durations=("2h" "30m" "1h")
    local strategy_index=$(( (occurrence - 1) % 3 ))

    local start_time="${strategies[$strategy_index]}"
    local duration="${durations[$strategy_index]}"

    local event_date=$(add_days "$start_date" $((occurrence - 1)))
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    local affected_shifts=($(get_affected_shifts "$start_time" "$end_time"))
    local workers_affected=$((${#affected_shifts[@]} * 4))  # Reduced impact

    cat << EOF
    {
      "id": "minimal_impact_$(echo $event_date | tr -d -)",
      "title": "⚙️ Fermata Impatto Minimo #$occurrence",
      "description": "Fermata con orario ottimizzato per ridurre al minimo l'impatto sui turni",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "STOP_PLANNED",
      "priority": "LOW",
      "location": "Aree selezionate",
      "tags": ["impatto_minimo", "ottimizzato", "efficiente"],
      "custom_properties": {
        "department": "Produzione",
        "pattern": "minimal-impact",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Orario ottimizzato per impatto minimo",
        "affected_shifts": "$(IFS=,; echo "${affected_shifts[*]}")",
        "shift_impact_level": "MINIMAL",
        "workers_affected": "$workers_affected",
        "optimization_level": "maximum",
        "impact_reduction": "85%"
      }
    }
EOF
}

generate_emergency_drills() {
    local start_date="$1"
    local occurrence="$2"

    # Last Friday of each month
    local year=$(date -d "$start_date" +%Y 2>/dev/null || date -j -f "%Y-%m-%d" "$start_date" +%Y)
    local month=$(date -d "$start_date" +%m 2>/dev/null || date -j -f "%Y-%m-%d" "$start_date" +%m)

    local target_month=$((month + occurrence - 1))
    local target_year=$year

    while [[ $target_month -gt 12 ]]; do
        target_month=$((target_month - 12))
        target_year=$((target_year + 1))
    done

    # Last day of month, then find last Friday
    local last_day="$(printf "%04d-%02d-28" $target_year $target_month)"
    local event_date=$(next_saturday "$last_day")  # Get Saturday, then subtract 1 for Friday
    event_date=$(add_days "$event_date" -1)

    local start_time="15:30"  # During afternoon shift change
    local duration="15m"
    local end_result=($(calculate_end_time "$start_time" "$duration" "$event_date"))
    local end_time="${end_result[1]}"
    local end_date="${end_result[2]}"

    cat << EOF
    {
      "id": "emergency_drill_$(echo $event_date | tr -d -)",
      "title": "🚨 Simulazione Emergenza #$occurrence",
      "description": "Esercitazione mensile emergenza - test procedure e tempi evacuazione",
      "start_date": "$event_date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "STOP_PLANNED",
      "priority": "HIGH",
      "location": "Tutto lo stabilimento",
      "tags": ["emergenza", "simulazione", "sicurezza"],
      "custom_properties": {
        "department": "Sicurezza",
        "pattern": "emergency-drills",
        "occurrence_number": "$occurrence",
        "duration": "$duration",
        "scheduling_strategy": "Venerdì pomeriggio - minor impatto weekend",
        "affected_shifts": "pomeriggio",
        "shift_impact_level": "LOW",
        "workers_affected": "36",
        "drill_type": "evacuazione_generale",
        "safety_priority": "maximum"
      }
    }
EOF
}

# ==================== MAIN GENERATION FUNCTION ====================
generate_batch_events() {
    local pattern="$1"
    local start_date="$2"
    local count="$3"
    local output_file="$4"

    local package_id="batch_$(echo $pattern | tr - _)_$(date +%Y%m%d)"
    local package_name="Batch $pattern Events"
    local description="Eventi ricorrenti ottimizzati per turni continui - pattern: $pattern"

    # Calculate end validity date
    local end_date=$(add_days "$start_date" $((count * 30)))  # Rough estimate

    # Start JSON
    cat > "$output_file" << EOF
{
  "package_info": {
    "id": "$package_id",
    "name": "$package_name",
    "version": "2.0.0",
    "description": "$description",
    "created_date": "$(generate_utc_timestamp)",
    "valid_from": "$start_date",
    "valid_to": "$end_date",
    "author": "Batch Stops Generator - Shift Optimized",
    "contact_email": "produzione@company.com"
  },
  "events": [
EOF

    # Generate events based on pattern
    for (( i=1; i<=count; i++ )); do
        case "$pattern" in
            "weekly-maintenance")
                generate_weekly_maintenance "$start_date" "$i" >> "$output_file"
                ;;
            "monthly-shutdown")
                generate_monthly_shutdown "$start_date" "$i" >> "$output_file"
                ;;
            "shift-cleaning")
                generate_shift_cleaning "$start_date" "$i" >> "$output_file"
                ;;
            "night-maintenance")
                generate_night_maintenance "$start_date" "$i" >> "$output_file"
                ;;
            "weekend-deep-clean")
                generate_weekend_deep_clean "$start_date" "$i" >> "$output_file"
                ;;
            "minimal-impact")
                generate_minimal_impact "$start_date" "$i" >> "$output_file"
                ;;
            "emergency-drills")
                generate_emergency_drills "$start_date" "$i" >> "$output_file"
                ;;
            *)
                log_error "Pattern non supportato: $pattern"
                rm -f "$output_file"
                exit 1
                ;;
        esac

        # Add comma except for last item
        if [[ $i -lt $count ]]; then
            echo "," >> "$output_file"
        fi
    done

    # Close JSON
    cat >> "$output_file" << EOF

  ]
}
EOF
}

# ==================== MAIN EXECUTION ====================
if [[ $# -lt 3 || "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

PATTERN="$1"
START_DATE="$2"
COUNT="$3"
OUTPUT_FILE="${4:-batch_${PATTERN}_$(date +%Y%m%d).json}"

# Validate inputs
if ! [[ "$START_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    log_error "Formato data non valido: $START_DATE (usa YYYY-MM-DD)"
    exit 1
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ $COUNT -lt 1 ]]; then
    log_error "Count deve essere un numero positivo: $COUNT"
    exit 1
fi

# Check if output file exists
if [[ -f "$OUTPUT_FILE" ]]; then
    echo "${YELLOW}[WARNING]${NC} Il file $OUTPUT_FILE esiste già"
    read "overwrite?Sovrascrivere? (y/N): "
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        log_info "Operazione annullata"
        exit 0
    fi
fi

# Generate batch events
log_info "Generando batch eventi ottimizzati per turni..."
log_info "Pattern: $PATTERN"
log_info "Data inizio: $START_DATE"
log_info "Numero eventi: $COUNT"
log_info "Output: $OUTPUT_FILE"

generate_batch_events "$PATTERN" "$START_DATE" "$COUNT" "$OUTPUT_FILE"

# Validate JSON
if command -v jq >/dev/null 2>&1; then
    if jq empty "$OUTPUT_FILE" 2>/dev/null; then
        log_success "JSON validato correttamente ✓"

        # Show impact summary
        echo ""
        echo "${YELLOW}📊 Riepilogo Batch - Impatto sui Turni:${NC}"
        local impact_summary=$(jq -r '.events[] | "• " + (.start_date | split("-") | .[1:3] | join("/")) + " " + .start_time + " - " + .title + " (" + .custom_properties.shift_impact_level + ")"' "$OUTPUT_FILE" 2>/dev/null)
        echo "$impact_summary"

        # Statistics
        local total_events=$(jq '.events | length' "$OUTPUT_FILE" 2>/dev/null)
        local no_impact=$(jq '[.events[] | select(.custom_properties.shift_impact_level == "NONE")] | length' "$OUTPUT_FILE" 2>/dev/null)
        local low_impact=$(jq '[.events[] | select(.custom_properties.shift_impact_level == "LOW" or .custom_properties.shift_impact_level == "MINIMAL")] | length' "$OUTPUT_FILE" 2>/dev/null)

        echo ""
        echo "${GREEN}✅ Ottimizzazione Turni:${NC}"
        echo "  📈 Eventi totali: $total_events"
        echo "  🎯 Zero impatto: $no_impact"
        echo "  📉 Basso impatto: $low_impact"
        echo "  💪 Efficienza: $(( (no_impact + low_impact) * 100 / total_events ))%"

    else
        log_error "JSON generato con errori"
        exit 1
    fi
else
    log_info "Installa 'jq' per validazione automatica"
fi

# Show summary
file_size=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
log_success "Batch generato: $OUTPUT_FILE ($file_size)"
log_success "$COUNT eventi di tipo '$PATTERN' ottimizzati per turni! 🎉"

# Pattern-specific recommendations
echo ""
case "$PATTERN" in
    "weekly-maintenance")
        echo "${BLUE}🔧 MANUTENZIONI SETTIMANALI:${NC}"
        echo "  • Pianificate per lunedì notte (22:00-04:00)"
        echo "  • Impatto minimo: solo turno notte coinvolto"
        echo "  • Coordinare team manutenzione per orario notturno"
        ;;
    "monthly-shutdown")
        echo "${RED}🏭 FERMATE MENSILI:${NC}"
        echo "  • Programmate nei weekend per zero impatto"
        echo "  • Utilizzare per manutenzioni straordinarie"
        echo "  • Pianificare recupero produzione settimana successiva"
        ;;
    "shift-cleaning")
        echo "${GREEN}🧹 PULIZIE TURNI:${NC}"
        echo "  • Ottimizzate per cambi turno (13:30-14:00)"
        echo "  • Impatto minimo: 30 minuti tra turni"
        echo "  • Ideal per pulizie rapide e sanificazione"
        ;;
    "night-maintenance")
        echo "${PURPLE}🌙 MANUTENZIONI NOTTURNE:${NC}"
        echo "  • Solo turno notte impattato"
        echo "  • Perfette per lavori specializzati"
        echo "  • Produzione ridotta ma non ferma"
        ;;
esac