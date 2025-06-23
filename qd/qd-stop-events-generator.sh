#!/bin/bash

# ==================== Q-DUE EVENTS JSON GENERATOR V2 - BASH ====================
# Utility Bash per generare file JSON di fermate con gestione orari turni continui
# Supporta: STOP_PLANNED, STOP_UNPLANNED, STOP_SHORTAGE, MAINTENANCE
# Author: Q-DUE Events System
# Version: 2.1.0 - Bash stable version with shift-aware scheduling

SCRIPT_VERSION="2.1.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
DEFAULT_PACKAGE_NAME="Eventi Fermate Produzione"
DEFAULT_AUTHOR="Sistema Produzione"
DEFAULT_EMAIL="produzione@company.com"

# Shift configuration (24h continuous production) - UPDATED TIMES
SHIFT_MORNING_START="05:00"
SHIFT_MORNING_END="13:00"
SHIFT_AFTERNOON_START="13:00"
SHIFT_AFTERNOON_END="21:00"
SHIFT_NIGHT_START="21:00"
SHIFT_NIGHT_END="05:00"

# ==================== HELP FUNCTION ====================
show_help() {
    echo -e "${CYAN}Q-DUE Events JSON Generator V${SCRIPT_VERSION} - JsonSchemaValidator Compatible${NC}"
        echo "Genera eventi fermate compatibili con Q-DUE JsonSchemaValidator"
        echo ""

    echo -e "${YELLOW}Validated Output:${NC}"
        echo "  ✓ Package ID: ^[a-z0-9_]{3,50}$ pattern"
        echo "  ✓ Event ID: ^[a-zA-Z0-9_-]{1,50}$ pattern"
        echo "  ✓ Dates: YYYY-MM-DD format strict"
        echo "  ✓ Times: HH:MM format strict"
        echo "  ✓ Timestamps: ISO 8601 with Z suffix"
        echo "  ✓ Event types: STOP_PLANNED, STOP_UNPLANNED, STOP_SHORTAGE, MAINTENANCE"
        echo "  ✓ Priorities: LOW, NORMAL, HIGH"
        echo ""
        echo -e "${YELLOW}Quick Examples (Validator Compatible):${NC}"
        echo "  $0 -q --duration 4h production_stop.json"
        echo "  $0 -t maintenance --duration 8h --start-at between-shifts maint.json"
        echo "  $0 --emergency-now --duration 2h emergency.json"
        echo ""
        echo -e "${GREEN}Validation Features:${NC}"
        echo "  • Automatic date/time format validation"
        echo "  • JsonSchemaValidator pattern compliance"
        echo "  • Cross-platform date calculation"
        echo "  • Fallback for invalid inputs"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
        echo "  $0 [OPTIONS] <output_file.json>"
        echo ""
        echo -e "${YELLOW}Options:${NC}"
    echo "  -h, --help              Mostra questo help"
    echo "  -i, --interactive       Modalità interattiva con pianificazione turni"
    echo "  -q, --quick             Modalità rapida con orari ottimizzati"
    echo "  -t, --template <type>   Template con orari realistici:"
    echo "                          planned|unplanned|shortage|maintenance"
    echo "  --shift-mode            Modalità pianificazione avanzata turni"
    echo "  --duration <time>       Durata fermata (es: 2h, 1d, 30m)"
    echo "  --start-at <strategy>   Strategia orario:"
    echo "                          shift-start|shift-end|between-shifts|minimal-impact"
    echo "  --emergency-now         Fermata emergenza immediata"
    echo ""
    echo -e "${YELLOW}Shift-Aware Examples:${NC}"
    echo "  $0 --emergency-now --duration 3h emergency.json"
    echo "  $0 -t maintenance --duration 8h --start-at between-shifts maint.json"
    echo "  $0 --shift-mode planned_weekend.json"
    echo "  $0 -q --duration 1d --start-at minimal-impact shortage_planned.json"
    echo ""
    echo -e "${YELLOW}Turni Configurati:${NC}"
    echo "  🌅 Mattino:    ${SHIFT_MORNING_START} - ${SHIFT_MORNING_END}"
    echo "  🌇 Pomeriggio: ${SHIFT_AFTERNOON_START} - ${SHIFT_AFTERNOON_END}"
    echo "  🌙 Notte:      ${SHIFT_NIGHT_START} - ${SHIFT_NIGHT_END} (+1 giorno)"
}

# ==================== UTILITY FUNCTIONS ====================
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# FIXED: Generate validator-compatible package ID
generate_package_id() {
    local package_name="$1"
    local timestamp="$2"

    # JsonSchemaValidator pattern: ^[a-z0-9_]{3,50}$
    # Must be lowercase, only letters, numbers, underscores, 3-50 chars
    local clean_name
    clean_name=$(echo "${package_name// /_}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]//g')

    # Ensure minimum length and add timestamp
    if [[ ${#clean_name} -lt 3 ]]; then
        clean_name="qdue_events"
    fi

    local package_id="${clean_name}_${timestamp}"

    # Truncate if too long (max 50 chars)
    if [[ ${#package_id} -gt 50 ]]; then
        local max_name_length=$((50 - ${#timestamp} - 1))  # -1 for underscore
        clean_name="${clean_name:0:$max_name_length}"
        package_id="${clean_name}_${timestamp}"
    fi

    echo "$package_id"
}

# FIXED: Generate validator-compatible event ID
generate_event_id() {
    local base_id="$1"
    local counter="$2"

    # JsonSchemaValidator pattern: ^[a-zA-Z0-9_-]{1,50}$
    # Letters, numbers, underscore, hyphen, 1-50 chars
    local clean_id
    clean_id=$(echo "$base_id" | sed 's/[^a-zA-Z0-9_-]//g')

    # Ensure valid ID
    if [[ -z "$clean_id" ]]; then
        clean_id="event"
    fi

    local event_id="${clean_id}_${counter}"

    # Truncate if too long (max 50 chars)
    if [[ ${#event_id} -gt 50 ]]; then
        local max_base_length=$((50 - ${#counter} - 1))  # -1 for underscore
        clean_id="${clean_id:0:$max_base_length}"
        event_id="${clean_id}_${counter}"
    fi

    echo "$event_id"
}

# Fixed UTC timestamp generation - VALIDATOR COMPATIBLE
generate_utc_timestamp() {
    # JsonSchemaValidator expects: YYYY-MM-DDTHH:mm:ssZ format
    if command -v gdate >/dev/null 2>&1; then
        # macOS with GNU coreutils
        gdate -u '+%Y-%m-%dT%H:%M:%SZ'
    elif command -v date >/dev/null 2>&1; then
        # Check if GNU date is available (supports -u and +%Y-%m-%dT%H:%M:%SZ)
        if date --version >/dev/null 2>&1; then
            # GNU date
            date -u '+%Y-%m-%dT%H:%M:%SZ'
        else
            # BSD date (macOS default) - need alternative approach
            date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
            python3 -c "import datetime; print(datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null || \
            echo "$(date -u '+%Y-%m-%d')T$(date -u '+%H:%M:%S')Z"
        fi
    else
        # Fallback
        echo "$(date '+%Y-%m-%d')T$(date '+%H:%M:%S')Z"
    fi
}

 FIXED: Cross-platform date calculation with validation
calculate_date_offset() {
    local base_date="$1"
    local offset_days="$2"

    # Validate input date first
    if ! validate_date "$base_date"; then
        echo "$base_date"  # Return original if invalid
        return 1
    fi

    local result_date
    if command -v gdate >/dev/null 2>&1; then
        # GNU date (Linux/macOS with coreutils)
        result_date=$(gdate -d "$base_date + $offset_days days" +%Y-%m-%d 2>/dev/null)
    elif date --version >/dev/null 2>&1; then
        # GNU date
        result_date=$(date -d "$base_date + $offset_days days" +%Y-%m-%d 2>/dev/null)
    else
        # BSD date (macOS default)
        if [[ "$offset_days" -ge 0 ]]; then
            result_date=$(date -j -v+"${offset_days}d" -f "%Y-%m-%d" "$base_date" +%Y-%m-%d 2>/dev/null)
        else
            local abs_days=$((offset_days * -1))
            result_date=$(date -j -v-"${abs_days}d" -f "%Y-%m-%d" "$base_date" +%Y-%m-%d 2>/dev/null)
        fi
    fi

    # Fallback if date calculation failed
    if [[ -z "$result_date" ]] || ! validate_date "$result_date"; then
        echo "$base_date"
        return 1
    fi

    echo "$result_date"
}

# FIXED: Strict date validation compatible with JsonSchemaValidator
validate_date() {
    local date_str="$1"
    # Validator expects exactly YYYY-MM-DD format
    if [[ "$date_str" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        # Additional validation: check if date is actually valid
        if command -v gdate >/dev/null 2>&1; then
            gdate -d "$date_str" >/dev/null 2>&1
        elif date --version >/dev/null 2>&1; then
            # GNU date
            date -d "$date_str" >/dev/null 2>&1
        else
            # BSD date - different syntax
            date -j -f "%Y-%m-%d" "$date_str" >/dev/null 2>&1
        fi
    else
        return 1
    fi
}

validate_time() {
    local time_str="$1"
    # Validator expects exactly HH:MM format (24h)
    if [[ "$time_str" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
        local hours minutes
        IFS=':' read -r hours minutes <<< "$time_str"

        # Remove leading zeros for arithmetic
        hours=$((10#$hours))
        minutes=$((10#$minutes))

        # Validate ranges
        [[ $hours -ge 0 && $hours -le 23 && $minutes -ge 0 && $minutes -le 59 ]]
    else
        return 1
    fi
}

# ==================== SHIFT CALCULATION FUNCTIONS ====================

# Convert time HH:MM to minutes from midnight
time_to_minutes() {
    local time="$1"
    local hours minutes
    
    # Extract hours and minutes
    IFS=':' read -r hours minutes <<< "$time"
    
    # Remove leading zeros for arithmetic
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    
    echo $((hours * 60 + minutes))
}

# Convert minutes to HH:MM
minutes_to_time() {
    local total_minutes="$1"
    local hours=$((total_minutes / 60))
    local minutes=$((total_minutes % 60))
    printf "%02d:%02d" $hours $minutes
}

 FIXED: Calculate end time with proper validation
calculate_end_time() {
    local start_time="$1"
    local duration="$2"
    local start_date="$3"

    # Validate inputs
    if ! validate_time "$start_time" || ! validate_date "$start_date"; then
        echo "12:00 $start_date"
        return 1
    fi

    local start_minutes
    start_minutes=$(time_to_minutes "$start_time")
    if [[ $? -ne 0 ]]; then
        echo "12:00 $start_date"
        return 1
    fi

    local duration_minutes=0

    # Parse duration with strict validation
    if [[ "$duration" =~ ^([0-9]+)h$ ]]; then
        duration_minutes=$((${BASH_REMATCH[1]} * 60))
    elif [[ "$duration" =~ ^([0-9]+)m$ ]]; then
        duration_minutes=${BASH_REMATCH[1]}
    elif [[ "$duration" =~ ^([0-9]+)d$ ]]; then
        duration_minutes=$((${BASH_REMATCH[1]} * 24 * 60))
    else
        log_warning "Invalid duration format: $duration, using 4h default"
        duration_minutes=240  # Default 4 hours
    fi

    local end_minutes=$((start_minutes + duration_minutes))
    local end_date="$start_date"
    local days_offset=0

    # Handle day overflow
    while [[ $end_minutes -ge 1440 ]]; do
        end_minutes=$((end_minutes - 1440))
        days_offset=$((days_offset + 1))
    done

    # Calculate end date if needed
    if [[ $days_offset -gt 0 ]]; then
        end_date=$(calculate_date_offset "$start_date" "$days_offset")
        if [[ $? -ne 0 ]]; then
            log_warning "Date calculation failed, using same day"
            end_date="$start_date"
            end_minutes=$((start_minutes + 240))  # Fallback to 4h same day
            if [[ $end_minutes -ge 1440 ]]; then
                end_minutes=1439  # Max time same day
            fi
        fi
    fi

    local end_time
    end_time=$(minutes_to_time $end_minutes)

    # Final validation
    if ! validate_time "$end_time" || ! validate_date "$end_date"; then
        log_warning "Calculated time/date invalid, using fallback"
        echo "23:59 $start_date"
        return 1
    fi

    echo "$end_time $end_date"
}


# Determine affected shifts
get_affected_shifts() {
    local start_time="$1"
    local end_time="$2"
    local start_date="$3"
    local end_date="$4"
    
    local start_minutes end_minutes
    start_minutes=$(time_to_minutes "$start_time")
    end_minutes=$(time_to_minutes "$end_time")
    
    # If crosses midnight, adjust end_minutes
    if [[ "$end_date" != "$start_date" ]]; then
        end_minutes=$((end_minutes + 1440))
    fi
    
    local affected_shifts=()
    
    # Check Morning shift (05:00-13:00) = 300-780 minutes
    local morning_start morning_end
    morning_start=$(time_to_minutes "$SHIFT_MORNING_START")
    morning_end=$(time_to_minutes "$SHIFT_MORNING_END")
    if [[ ($start_minutes -lt $morning_end && $end_minutes -gt $morning_start) ]]; then
        affected_shifts+=("mattino")
    fi
    
    # Check Afternoon shift (13:00-21:00) = 780-1260 minutes
    local afternoon_start afternoon_end
    afternoon_start=$(time_to_minutes "$SHIFT_AFTERNOON_START")
    afternoon_end=$(time_to_minutes "$SHIFT_AFTERNOON_END")
    if [[ ($start_minutes -lt $afternoon_end && $end_minutes -gt $afternoon_start) ]]; then
        affected_shifts+=("pomeriggio")
    fi
    
    # Check Night shift (21:00-05:00 next day) = 1260-1740 minutes (wrapping)
    local night_start night_end
    night_start=$(time_to_minutes "$SHIFT_NIGHT_START")
    night_end=$(($(time_to_minutes "$SHIFT_NIGHT_END") + 1440))  # Next day
    if [[ ($start_minutes -ge $night_start || $end_minutes -gt $night_start || 
           ($start_minutes -le 300 && $end_minutes -gt 0)) ]]; then
        affected_shifts+=("notte")
    fi
    
    echo "${affected_shifts[@]}"
}

# Calculate optimal times to minimize impact
calculate_optimal_times() {
    local stop_type="$1"
    local duration="$2"
    local strategy="$3"
    local reference_date="$4"
    
    local start_time=""
    local optimal_strategy=""
    
    case "$strategy" in
        "shift-start")
            start_time="$SHIFT_MORNING_START"
            optimal_strategy="Inizio turno mattino"
            ;;
        "shift-end")
            start_time="$SHIFT_AFTERNOON_END"
            optimal_strategy="Fine turno pomeriggio"
            ;;
        "between-shifts")
            case "$stop_type" in
                "maintenance"|"planned")
                    start_time="$SHIFT_NIGHT_START"  # Start night shift
                    optimal_strategy="Durante turno notte (minor impatto)"
                    ;;
                *)
                    start_time="12:30"  # Between morning and afternoon
                    optimal_strategy="Tra turno mattino e pomeriggio"
                    ;;
            esac
            ;;
        "minimal-impact")
            # Analyze duration and choose best time
            if [[ "$duration" =~ ^([0-9]+)h$ ]]; then
                local hours=${BASH_REMATCH[1]}
                if [[ $hours -le 2 ]]; then
                    start_time="12:30"  # Short stop between shifts
                    optimal_strategy="Fermata breve tra turni"
                elif [[ $hours -le 8 ]]; then
                    start_time="$SHIFT_NIGHT_START"  # Night shift
                    optimal_strategy="Durante turno notte"
                else
                    start_time="21:30"  # Start weekend or after shift
                    optimal_strategy="Fermata lunga, inizio fine settimana"
                fi
            elif [[ "$duration" =~ d$ ]]; then
                start_time="$SHIFT_NIGHT_END"  # End of night, start of weekend
                optimal_strategy="Fermata multi-giorno, weekend preferito"
            else
                start_time="$SHIFT_AFTERNOON_END"
                optimal_strategy="Orario standard fine turno"
            fi
            ;;
        "emergency-now")
            start_time="$(date +%H:%M)"
            optimal_strategy="Emergenza - orario attuale"
            ;;
        *)
            start_time="$SHIFT_AFTERNOON_END"
            optimal_strategy="Default: fine turno pomeriggio"
            ;;
    esac
    
    local time_result
    time_result=($(calculate_end_time "$start_time" "$duration" "$reference_date"))
    local end_time="${time_result[0]}"
    local end_date="${time_result[1]}"
    
    echo "$start_time $end_time $end_date $optimal_strategy"
}

# Estimate affected workers
estimate_workers_affected() {
    local affected_shifts=($1)
    local workers_per_shift=12  # Configurable
    local total_workers=$((${#affected_shifts[@]} * workers_per_shift))
    echo $total_workers
}

# Calculate impact level
calculate_impact_level() {
    local affected_shifts=($1)
    local shift_count=${#affected_shifts[@]}
    
    case $shift_count in
        0) echo "NONE" ;;
        1) echo "LOW" ;;
        2) echo "MEDIUM" ;;
        3) echo "HIGH" ;;
        *) echo "CRITICAL" ;;
    esac
}

# ==================== ENHANCED TEMPLATE GENERATORS ====================

# FIXED: Generate shift-aware event with full validation
generate_shift_aware_event() {
    local stop_type="$1"
    local duration="$2"
    local strategy="$3"
    local event_date="$4"
    local event_id="$5"
    local title="$6"
    local description="$7"

    # Validate all inputs
    if ! validate_date "$event_date"; then
        log_error "Invalid event date: $event_date"
        event_date=$(date +%Y-%m-%d)  # Fallback to today
    fi

    # Generate valid event ID
    local clean_event_id
    clean_event_id=$(generate_event_id "$event_id" "001")

    # Calculate optimal times with validation
    local timing
    timing=($(calculate_optimal_times "$stop_type" "$duration" "$strategy" "$event_date"))
    if [[ ${#timing[@]} -lt 3 ]]; then
        log_warning "Time calculation failed, using defaults"
        timing=("09:00" "13:00" "$event_date" "Default timing")
    fi

    local start_time="${timing[0]}"
    local end_time="${timing[1]}"
    local end_date="${timing[2]}"
    local strategy_desc="${timing[3]} ${timing[4]} ${timing[5]} ${timing[6]}"  # Join remaining

    # Validate calculated times and dates
    if ! validate_time "$start_time"; then
        log_warning "Invalid start_time: $start_time, using 09:00"
        start_time="09:00"
    fi

    if ! validate_time "$end_time"; then
        log_warning "Invalid end_time: $end_time, using 17:00"
        end_time="17:00"
    fi

    if ! validate_date "$end_date"; then
        log_warning "Invalid end_date: $end_date, using event_date"
        end_date="$event_date"
    fi

    # Calculate affected shifts
    local affected_shifts
    affected_shifts=($(get_affected_shifts "$start_time" "$end_time" "$event_date" "$end_date"))
    local workers_affected
    workers_affected=$(estimate_workers_affected "${affected_shifts[*]}")
    local impact_level
    impact_level=$(calculate_impact_level "${affected_shifts[*]}")

    # Map stop_type to valid event_type (JsonSchemaValidator compatible)
    local event_type priority
    case "$stop_type" in
        "emergency"|"unplanned")
            event_type="STOP_UNPLANNED"
            priority="HIGH"
            ;;
        "shortage")
            event_type="STOP_SHORTAGE"
            priority="NORMAL"
            ;;
        "maintenance")
            event_type="MAINTENANCE"
            priority="HIGH"
            ;;
        "planned")
            event_type="STOP_PLANNED"
            priority="NORMAL"
            ;;
        *)
            event_type="STOP_PLANNED"
            priority="NORMAL"
            ;;
    esac

    # Validate event_type and priority against JsonSchemaValidator
    local valid_types=("GENERAL" "STOP_PLANNED" "STOP_UNPLANNED" "STOP_SHORTAGE" "MAINTENANCE" "MEETING" "TRAINING")
    local valid_priorities=("LOW" "NORMAL" "HIGH")

    if ! printf '%s\n' "${valid_types[@]}" | grep -q "^$event_type$"; then
        log_warning "Invalid event_type: $event_type, using GENERAL"
        event_type="GENERAL"
    fi

    if ! printf '%s\n' "${valid_priorities[@]}" | grep -q "^$priority$"; then
        log_warning "Invalid priority: $priority, using NORMAL"
        priority="NORMAL"
    fi

    # Join affected shifts with comma (no spaces for JSON)
    local affected_shifts_str
    affected_shifts_str=$(IFS=,; echo "${affected_shifts[*]}")

    # Clean and validate all string fields for JSON
    title=$(echo "$title" | sed 's/"/\\"/g' | tr -d '\n\r')
    description=$(echo "$description" | sed 's/"/\\"/g' | tr -d '\n\r')
    strategy_desc=$(echo "$strategy_desc" | sed 's/"/\\"/g' | tr -d '\n\r')

    # Generate UTC timestamp
    local generation_time
    generation_time=$(generate_utc_timestamp)

    # Validate generation_time format
    if [[ ! "$generation_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        log_warning "Invalid timestamp format: $generation_time"
        generation_time="$(date +%Y-%m-%d)T$(date +%H:%M:%S)Z"
    fi

    cat << EOF
  {
    "id": "$clean_event_id",
    "title": "$title",
    "description": "$description",
    "start_date": "$event_date",
    "end_date": "$end_date",
    "start_time": "$start_time",
    "end_time": "$end_time",
    "all_day": false,
    "event_type": "$event_type",
    "priority": "$priority",
    "location": "Linee Produzione",
    "tags": ["$stop_type", "turni_impattati", "$impact_level"],
    "custom_properties": {
      "department": "Produzione",
      "stop_type": "$stop_type",
      "duration": "$duration",
      "scheduling_strategy": "$strategy_desc",
      "affected_shifts": "$affected_shifts_str",
      "shift_impact_level": "$impact_level",
      "workers_affected": "$workers_affected",
      "optimal_scheduling": "true",
      "created_by": "qdue_generator_v2_bash",
      "generation_time": "$generation_time"
    }
  }
EOF
}

# ==================== QUICK MODE ====================
quick_mode_enhanced() {
    local output_file="$1"
    local duration="${2:-4h}"
    local strategy="${3:-minimal-impact}"
    local package_name="${4:-$DEFAULT_PACKAGE_NAME}"
    local author="${5:-$DEFAULT_AUTHOR}"
    local email="${6:-$DEFAULT_EMAIL}"
    local valid_from="${7:-$(date +%Y-%m-%d)}"
    local valid_to="${8:-$(date -d "$valid_from + 1 week" +%Y-%m-%d 2>/dev/null || echo "2025-06-22")}"
    
    log_info "Generando pacchetto rapido con pianificazione turni..."
    log_info "Durata: $duration | Strategia: $strategy"
    
    # Calculate next day
    local next_day
    if command -v gdate >/dev/null 2>&1; then
        next_day=$(gdate -d "$valid_from + 1 day" +%Y-%m-%d)
    else
        next_day=$(date -d "$valid_from + 1 day" +%Y-%m-%d 2>/dev/null || \
                   date -j -v+1d -f "%Y-%m-%d" "$valid_from" +%Y-%m-%d 2>/dev/null)
    fi
    
    # Generate events array step by step to avoid empty elements
    local events=()
    
    # Generate first event
    local event1
    event1=$(generate_shift_aware_event "maintenance" "$duration" "$strategy" "$valid_from" "maint_001" "Manutenzione Programmata" "Manutenzione preventiva con orario ottimizzato per turni")
    if [[ -n "$event1" && "$event1" =~ "id" ]]; then
        events+=("$event1")
    fi
    
    # Generate second event
    local event2
    event2=$(generate_shift_aware_event "shortage" "2h" "between-shifts" "$next_day" "shortage_001" "Mancanza Materiale Prevista" "Shortage programmato con impatto minimo sui turni")
    if [[ -n "$event2" && "$event2" =~ "id" ]]; then
        events+=("$event2")
    fi
    
    # Fallback if no valid events
    if [[ ${#events[@]} -eq 0 ]]; then
        log_warning "Generando evento di fallback..."
        local fallback_event
        fallback_event=$(generate_shift_aware_event "maintenance" "1h" "minimal-impact" "$valid_from" "fallback_001" "Evento Fallback" "Evento generato automaticamente per validazione")
        events+=("$fallback_event")
    fi
    
    generate_json_file "$output_file" "$package_name" "$author" "$email" "Pacchetto rapido con pianificazione turni intelligente" "$valid_from" "$valid_to" "${events[@]}"
}

# ==================== TEMPLATE MODE ====================
template_mode_enhanced() {
    local template_type="$1"
    local output_file="$2"
    local duration="${3:-4h}"
    local strategy="${4:-minimal-impact}"
    
    log_info "Generando template '$template_type' con durata '$duration' e strategia '$strategy'"
    
    local event_date valid_from valid_to
    event_date=$(date +%Y-%m-%d)
    valid_from="$event_date"
    if command -v gdate >/dev/null 2>&1; then
        valid_to=$(gdate -d "$valid_from + 1 month" +%Y-%m-%d)
    else
        valid_to=$(date -d "$valid_from + 1 month" +%Y-%m-%d 2>/dev/null || echo "2025-07-15")
    fi
    
    local event_id="${template_type}_template_001"
    
    # Define titles and descriptions
    local title description
    case "$template_type" in
        "emergency")
            title="🚨 Template Emergenza"
            description="Template per fermate di emergenza con gestione turni"
            ;;
        "shortage")
            title="📦 Template Mancanza Materiale"
            description="Template per shortage con pianificazione ottimizzata"
            ;;
        "maintenance")
            title="🔧 Template Manutenzione"
            description="Template manutenzione con orari turni intelligenti"
            ;;
        "planned")
            title="⚙️ Template Fermata Programmata"
            description="Template fermata programmata shift-aware"
            ;;
        *)
            log_error "Tipo template non valido: $template_type"
            log_error "Tipi supportati: emergency, shortage, maintenance, planned"
            exit 1
            ;;
    esac
    
    local event
    event=$(generate_shift_aware_event "$template_type" "$duration" "$strategy" "$event_date" "$event_id" "$title" "$description")
    
    generate_json_file "$output_file" "Template $template_type" "$DEFAULT_AUTHOR" "$DEFAULT_EMAIL" "Template con gestione turni per $template_type" "$valid_from" "$valid_to" "$event"
}

# ==================== JSON GENERATION ====================
# FIXED: Generate JSON file with full validation
generate_json_file() {
    local output_file="$1"
    local package_name="$2"
    local author="$3"
    local email="$4"
    local description="$5"
    local valid_from="$6"
    local valid_to="$7"
    shift 7
    local events=("$@")

    # Validate dates
    if ! validate_date "$valid_from"; then
        log_warning "Invalid valid_from date: $valid_from, using today"
        valid_from=$(date +%Y-%m-%d)
    fi

    if ! validate_date "$valid_to"; then
        log_warning "Invalid valid_to date: $valid_to, calculating from valid_from"
        valid_to=$(calculate_date_offset "$valid_from" 30)
        if [[ $? -ne 0 ]]; then
            valid_to="2025-12-31"  # Fallback
        fi
    fi

    # Generate package ID with validation
    local timestamp
    timestamp=$(date +%Y%m%d)
    local package_id
    package_id=$(generate_package_id "$package_name" "$timestamp")

    # Generate and validate created_date
    local created_date
    created_date=$(generate_utc_timestamp)

    local version="2.1.0"  # JsonSchemaValidator expects semantic versioning

    # Clean strings for JSON
    package_name=$(echo "$package_name" | sed 's/"/\\"/g' | tr -d '\n\r')
    author=$(echo "$author" | sed 's/"/\\"/g' | tr -d '\n\r')
    email=$(echo "$email" | sed 's/"/\\"/g' | tr -d '\n\r')
    description=$(echo "$description" | sed 's/"/\\"/g' | tr -d '\n\r')

    # Validate email format if provided
    if [[ -n "$email" && ! "$email" =~ ^[A-Za-z0-9+_.-]+@(.+)$ ]]; then
        log_warning "Invalid email format: $email, using default"
        email="$DEFAULT_EMAIL"
    fi

    # Validate and filter events
    local valid_events=()
    for event in "${events[@]}"; do
        if [[ -n "$event" && "$event" =~ '"id"' && "$event" =~ '"title"' ]]; then
            valid_events+=("$event")
        else
            log_warning "Scartato evento non valido o vuoto"
        fi
    done

    # Ensure at least one event (JsonSchemaValidator will warn on empty array)
    if [[ ${#valid_events[@]} -eq 0 ]]; then
        log_warning "Generando evento di default per validazione..."
        local default_event
        default_event=$(generate_shift_aware_event "maintenance" "1h" "minimal-impact" "$valid_from" "default_001" "Evento Default" "Evento generato automaticamente per validazione")
        valid_events+=("$default_event")
    fi

    # Generate JSON with proper structure for JsonSchemaValidator
    cat > "$output_file" << EOF
{
  "package_info": {
    "id": "$package_id",
    "name": "$package_name",
    "version": "$version",
    "description": "$description",
    "created_date": "$created_date",
    "valid_from": "$valid_from",
    "valid_to": "$valid_to",
    "author": "$author",
    "contact_email": "$email"
  },
  "events": [
EOF

    # Add events with proper comma handling
    local event_count=${#valid_events[@]}
    for (( i=0; i<event_count; i++ )); do
        echo "${valid_events[i]}" >> "$output_file"
        if (( i < event_count - 1 )); then
            echo "," >> "$output_file"
        fi
    done

    # Close JSON structure
    cat >> "$output_file" << EOF

  ]
}
EOF

    log_success "File JSON generato: $output_file"
    log_info "Pacchetto: $package_name (ID: $package_id)"
    log_info "Eventi: $event_count"
    log_info "Validità: $valid_from → $valid_to"

    # Enhanced validation with JsonSchemaValidator compatibility check
    if command -v jq >/dev/null 2>&1; then
        if jq empty "$output_file" 2>/dev/null; then
            log_success "JSON sintatticamente valido ✓"

            # Check JsonSchemaValidator specific requirements
            local validation_issues=()

            # Check package_info.id format
            local pkg_id
            pkg_id=$(jq -r '.package_info.id' "$output_file")
            if [[ ! "$pkg_id" =~ ^[a-z0-9_]{3,50}$ ]]; then
                validation_issues+=("Package ID non conforme al pattern JsonSchemaValidator")
            fi

            # Check event IDs format
            local event_ids
            event_ids=($(jq -r '.events[].id' "$output_file"))
            for event_id in "${event_ids[@]}"; do
                if [[ ! "$event_id" =~ ^[a-zA-Z0-9_-]{1,50}$ ]]; then
                    validation_issues+=("Event ID '$event_id' non conforme al pattern JsonSchemaValidator")
                fi
            done

            # Check date formats
            local dates
            dates=($(jq -r '.package_info.valid_from, .package_info.valid_to, .events[].start_date, .events[].end_date' "$output_file" | grep -v null))
            for date_val in "${dates[@]}"; do
                if ! validate_date "$date_val"; then
                    validation_issues+=("Data '$date_val' non in formato YYYY-MM-DD")
                fi
            done

            # Check time formats
            local times
            times=($(jq -r '.events[].start_time, .events[].end_time' "$output_file" | grep -v null))
            for time_val in "${times[@]}"; do
                if ! validate_time "$time_val"; then
                    validation_issues+=("Orario '$time_val' non in formato HH:MM")
                fi
            done

            if [[ ${#validation_issues[@]} -eq 0 ]]; then
                log_success "Compatibile con JsonSchemaValidator ✓"
            else
                log_warning "Problemi di compatibilità con JsonSchemaValidator:"
                for issue in "${validation_issues[@]}"; do
                    log_warning "  • $issue"
                done
            fi

            # Show shift impact summary
            echo ""
            echo -e "${YELLOW}📊 Riepilogo Impatto Turni:${NC}"
            local impact_summary
            impact_summary=$(jq -r '.events[] | "• " + .title + " (" + .custom_properties.shift_impact_level + " impact, " + .custom_properties.workers_affected + " operatori)"' "$output_file" 2>/dev/null)
            echo "$impact_summary"
        else
            log_error "JSON ha errori di sintassi!"
            if command -v jq >/dev/null 2>&1; then
                jq . "$output_file" || log_error "Errore nel parsing JSON"
            fi
        fi
    else
        log_info "Installa 'jq' per validazione automatica JSON"
    fi
}

# ==================== MAIN SCRIPT ====================
main() {
  # V2.1.0 update info
  log_info "Script aggiornato per compatibilità JsonSchemaValidator:"
  log_info "✓ Date format: YYYY-MM-DD strict validation"
  log_info "✓ Time format: HH:MM strict validation"
  log_info "✓ Package ID: ^[a-z0-9_]{3,50}$ pattern compliance"
  log_info "✓ Event ID: ^[a-zA-Z0-9_-]{1,50}$ pattern compliance"
  log_info "✓ Timestamp: ISO 8601 format with Z suffix"
  log_info "✓ Event types: Only valid JsonSchemaValidator types"
  log_info "✓ Cross-platform date handling with fallbacks"
  log_info "✓ Enhanced validation with jq integration"

    local mode="interactive"
    local template_type=""
    local output_file=""
    local package_name="$DEFAULT_PACKAGE_NAME"
    local author="$DEFAULT_AUTHOR"
    local email="$DEFAULT_EMAIL"
    local valid_from=""
    local valid_to=""
    local duration="4h"
    local strategy="minimal-impact"
    local emergency_now=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--interactive)
                mode="interactive"
                shift
                ;;
            -q|--quick)
                mode="quick"
                shift
                ;;
            -t|--template)
                mode="template"
                template_type="$2"
                shift 2
                ;;
            --shift-mode)
                mode="shift-planning"
                shift
                ;;
            --duration)
                duration="$2"
                shift 2
                ;;
            --start-at)
                strategy="$2"
                shift 2
                ;;
            --emergency-now)
                emergency_now=true
                strategy="emergency-now"
                shift
                ;;
            -n|--package-name)
                package_name="$2"
                shift 2
                ;;
            -a|--author)
                author="$2"
                shift 2
                ;;
            -e|--email)
                email="$2"
                shift 2
                ;;
            --from)
                valid_from="$2"
                if ! validate_date "$valid_from"; then
                    log_error "Data inizio non valida: $valid_from"
                    exit 1
                fi
                shift 2
                ;;
            --to)
                valid_to="$2"
                if ! validate_date "$valid_to"; then
                    log_error "Data fine non valida: $valid_to"
                    exit 1
                fi
                shift 2
                ;;
            -*)
                log_error "Opzione sconosciuta: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$output_file" ]]; then
                    output_file="$1"
                else
                    log_error "Troppi argomenti posizionali"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate output file
    if [[ -z "$output_file" ]]; then
        log_error "File di output richiesto"
        show_help
        exit 1
    fi
    
    # Check if output file exists
    if [[ -f "$output_file" ]]; then
        log_warning "Il file $output_file esiste già"
        read -p "Sovrascrivere? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "Operazione annullata"
            exit 0
        fi
    fi
    
    # Special handling for emergency mode
    if [[ "$emergency_now" == true ]]; then
        log_info "🚨 Modalità EMERGENZA attivata - generando fermata immediata"
        mode="emergency"
    fi
    
    # Execute based on mode
    case "$mode" in
        "interactive"|"shift-planning")
            log_error "Modalità interattiva non implementata in questa versione"
            log_info "Usa modalità quick o template: $0 -q $output_file"
            exit 1
            ;;
        "quick")
            quick_mode_enhanced "$output_file" "$duration" "$strategy" "$package_name" "$author" "$email" "$valid_from" "$valid_to"
            ;;
        "template")
            template_mode_enhanced "$template_type" "$output_file" "$duration" "$strategy"
            ;;
        "emergency")
            # Emergency mode: generate immediate stop
            local event_date
            event_date=$(date +%Y-%m-%d)
            local event_id="emergency_$(date +%Y%m%d_%H%M%S)"
            local emergency_event
            emergency_event=$(generate_shift_aware_event "emergency" "$duration" "emergency-now" "$event_date" "$event_id" "🚨 FERMATA EMERGENZA" "Fermata di emergenza generata automaticamente - intervento immediato richiesto")
            
            valid_from=${valid_from:-$event_date}
            if command -v gdate >/dev/null 2>&1; then
                valid_to=${valid_to:-$(gdate -d "$event_date + 1 week" +%Y-%m-%d)}
            else
                valid_to=${valid_to:-$(date -d "$event_date + 1 week" +%Y-%m-%d 2>/dev/null || echo "2025-06-22")}
            fi
            
            generate_json_file "$output_file" "EMERGENZA - $package_name" "$author" "$email" "Pacchetto emergenza generato automaticamente" "$valid_from" "$valid_to" "$emergency_event"
            
            # Show immediate impact
            echo ""
            echo -e "${RED}🚨 ATTENZIONE - FERMATA EMERGENZA GENERATA 🚨${NC}"
            echo "📍 File: $output_file"
            echo "⏰ Orario: $(date +%H:%M) (ora attuale)"
            echo "⏱️  Durata: $duration"
            echo "📱 IMPORTARE IMMEDIATAMENTE in Q-DUE Events per notificare turni!"
            ;;
        *)
            log_error "Modalità non valida: $mode"
            exit 1
            ;;
    esac
    
    echo ""
    log_success "Generazione completata! 🎉"
    log_info "File pronto per import in Q-DUE Events System"
    
    # Show quick usage tips based on mode
    case "$mode" in
        "emergency")
            echo ""
            echo -e "${YELLOW}⚡ Prossimi passi per emergenza:${NC}"
            echo "  1. Importare immediatamente in Q-DUE Events"
            echo "  2. Notificare supervisori turni interessati"
            echo "  3. Aggiornare dashboard produzione"
            ;;
        *)
            echo ""
            echo -e "${YELLOW}💡 Suggerimenti:${NC}"
            echo "  • Verificare impatto turni mostrato sopra"
            echo "  • Coordinare con responsabili turni prima dell'import"
            echo "  • Considerare orari alternativi per ridurre impatto"
            ;;
    esac
}

# Run main function
main "$@"
