#!/bin/bash

# ==================== QUICK STOP GENERATOR - BASH ====================
# Versione rapida per scenari comuni con gestione turni
# Usage: ./quick-stop.bash <scenario> [date] [duration] [output.json]

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Updated shift times: 05-13, 13-21, 21-05
MORNING="05:00-13:00"
AFTERNOON="13:00-21:00"
NIGHT="21:00-05:00"

# Quick help
if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
    echo -e "${YELLOW}Quick Stop Generator - Bash Stable${NC}"
    echo "Genera rapidamente fermate ottimizzate per turni continui"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 <scenario> [date] [duration] [output.json]"
    echo ""
    echo -e "${YELLOW}Scenari Comuni:${NC}"
    echo -e "  ${RED}emergency-now${NC}        Emergenza immediata (orario attuale)"
    echo -e "  ${PURPLE}shortage-morning${NC}     Shortage inizio turno mattino"
    echo -e "  ${BLUE}maintenance-night${NC}    Manutenzione durante turno notte"
    echo -e "  ${GREEN}cleaning-weekend${NC}     Pulizia weekend tra turni"
    echo -e "  ${YELLOW}shift-handover${NC}       Fermata cambio turno"
    echo -e "  ${CYAN}minimal-impact${NC}        Fermata con impatto minimo"
    echo ""
    echo -e "${YELLOW}Configurazione Turni:${NC}"
    echo "  🌅 Mattino:    $MORNING"
    echo "  🌇 Pomeriggio: $AFTERNOON"
    echo "  🌙 Notte:      $NIGHT"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 emergency-now"
    echo "  $0 maintenance-night 2025-06-21 8h"
    echo "  $0 shortage-morning 2025-06-18 4h shortage_june.json"
    echo "  $0 cleaning-weekend 2025-06-22 6h weekend_clean.json"
    exit 0
fi

# Parameters
SCENARIO="$1"
EVENT_DATE="${2:-$(date +%Y-%m-%d)}"
DURATION="${3:-4h}"
OUTPUT_FILE="${4:-stop_${SCENARIO}_$(date +%Y%m%d).json}"

# Validate date
if ! [[ "$EVENT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo -e "${RED}[ERROR]${NC} Formato data non valido: $EVENT_DATE (usa YYYY-MM-DD)"
    exit 1
fi

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# UTC timestamp
generate_utc_timestamp() {
    if command -v gdate >/dev/null 2>&1; then
        gdate -u '+%Y-%m-%dT%H:%M:%SZ'
    else
        date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -Iseconds | sed 's/+00:00/Z/'
    fi
}

# Calculate end time from duration
calculate_end_time() {
    local start_time="$1"
    local duration="$2"
    local start_date="$3"

    # Convert time to minutes
    local hours minutes
    IFS=':' read -r hours minutes <<< "$start_time"
    hours=$((10#$hours))
    minutes=$((10#$minutes))
    local start_minutes=$((hours * 60 + minutes))

    # Parse duration
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
        if command -v gdate >/dev/null 2>&1; then
            end_date=$(gdate -d "$start_date + $days_to_add days" +%Y-%m-%d)
        else
            end_date=$(date -d "$start_date + $days_to_add days" +%Y-%m-%d 2>/dev/null || \
                       date -j -v+${days_to_add}d -f "%Y-%m-%d" "$start_date" +%Y-%m-%d 2>/dev/null)
        fi
    fi

    # Convert back to time
    local end_hours=$((end_minutes / 60))
    local end_mins=$((end_minutes % 60))
    local end_time=$(printf "%02d:%02d" $end_hours $end_mins)

    echo "$end_time $end_date"
}

# Get affected shifts with new times
get_affected_shifts() {
    local start_time="$1"
    local end_time="$2"

    # Simple logic - convert to minutes and check overlaps
    local start_hours start_mins end_hours end_mins
    IFS=':' read -r start_hours start_mins <<< "$start_time"
    IFS=':' read -r end_hours end_mins <<< "$end_time"

    start_hours=$((10#$start_hours))
    start_mins=$((10#$start_mins))
    end_hours=$((10#$end_hours))
    end_mins=$((10#$end_mins))

    local start_minutes=$((start_hours * 60 + start_mins))
    local end_minutes=$((end_hours * 60 + end_mins))

    # Handle overnight
    if [[ $end_minutes -lt $start_minutes ]]; then
        end_minutes=$((end_minutes + 1440))
    fi

    local shifts=()

    # Morning: 05:00-13:00 (300-780 minutes)
    if [[ ($start_minutes -lt 780 && $end_minutes -gt 300) ]]; then
        shifts+=("mattino")
    fi

    # Afternoon: 13:00-21:00 (780-1260 minutes)
    if [[ ($start_minutes -lt 1260 && $end_minutes -gt 780) ]]; then
        shifts+=("pomeriggio")
    fi

    # Night: 21:00-05:00 (1260-1740 minutes, wrapping)
    if [[ ($start_minutes -ge 1260 || $end_minutes -gt 1260 ||
           ($start_minutes -le 300 && $end_minutes -gt 0)) ]]; then
        shifts+=("notte")
    fi

    echo "${shifts[@]}"
}

# Generate scenario-specific event
generate_scenario_event() {
    local scenario="$1"
    local date="$2"
    local duration="$3"

    local start_time end_time end_date title description event_type priority
    local strategy workers_affected impact_level

    case "$scenario" in
        "emergency-now")
            start_time="$(date +%H:%M)"
            local end_result
            end_result=($(calculate_end_time "$start_time" "$duration" "$date"))
            end_time="${end_result[0]}"
            end_date="${end_result[1]}"
            title="🚨 FERMATA EMERGENZA"
            description="Fermata di emergenza immediata - intervento urgente richiesto"
            event_type="STOP_UNPLANNED"
            priority="HIGH"
            strategy="Emergenza - orario attuale"
            workers_affected="36"  # All shifts potentially
            impact_level="CRITICAL"
            ;;
        "shortage-morning")
            start_time="05:00"
            local end_result
            end_result=($(calculate_end_time "$start_time" "$duration" "$date"))
            end_time="${end_result[0]}"
            end_date="${end_result[1]}"
            title="📦 Mancanza Materiale - Turno Mattino"
            description="Shortage materiale prime - turno mattino non può iniziare produzione"
            event_type="STOP_SHORTAGE"
            priority="HIGH"
            strategy="Inizio turno mattino - operatori restano a casa"
            workers_affected="12"
            impact_level="HIGH"
            ;;
        "maintenance-night")
            start_time="21:00"
            local end_result
            end_result=($(calculate_end_time "$start_time" "$duration" "$date"))
            end_time="${end_result[0]}"
            end_date="${end_result[1]}"
            title="🔧 Manutenzione Turno Notte"
            description="Manutenzione programmata durante turno notte - impatto minimo"
            event_type="MAINTENANCE"
            priority="NORMAL"
            strategy="Turno notte - impatto minimo produzione"
            workers_affected="12"
            impact_level="LOW"
            ;;
        "cleaning-weekend")
            start_time="08:00"
            local end_result
            end_result=($(calculate_end_time "$start_time" "$duration" "$date"))
            end_time="${end_result[0]}"
            end_date="${end_result[1]}"
            title="🧹 Pulizie Weekend"
            description="Pulizie approfondite weekend - sanificazione completa impianti"
            event_type="MAINTENANCE"
            priority="NORMAL"
            strategy="Weekend - nessun impatto turni produzione"
            workers_affected="0"
            impact_level="NONE"
            ;;
        "shift-handover")
            start_time="12:45"
            local end_result
            end_result=($(calculate_end_time "$start_time" "30m" "$date"))
            end_time="${end_result[0]}"
            end_date="${end_result[1]}"
            title="🔄 Fermata Cambio Turno"
            description="Fermata tecnica per cambio turno e passaggio consegne"
            event_type="STOP_PLANNED"
            priority="LOW"
            strategy="Cambio turno - fermata tecnica standard"
            workers_affected="24"  # Two shifts
            impact_level="LOW"
            ;;
        "minimal-impact")
            start_time="21:30"
            local end_result
            end_result=($(calculate_end_time "$start_time" "$duration" "$date"))
            end_time="${end_result[0]}"
            end_date="${end_result[1]}"
            title="⚙️ Fermata Impatto Minimo"
            description="Fermata pianificata con orario ottimizzato per ridurre impatto turni"
            event_type="STOP_PLANNED"
            priority="NORMAL"
            strategy="Orario ottimizzato - impatto turni minimizzato"
            workers_affected="6"
            impact_level="LOW"
            ;;
        *)
            log_error "Scenario non supportato: $scenario"
            echo "Scenari disponibili: emergency-now, shortage-morning, maintenance-night, cleaning-weekend, shift-handover, minimal-impact"
            exit 1
            ;;
    esac

    # Calculate actual affected shifts
    local affected_shifts
    affected_shifts=($(get_affected_shifts "$start_time" "$end_time"))
    local affected_shifts_str
    IFS=,; affected_shifts_str="${affected_shifts[*]}"; IFS=' '

    cat << EOF
{
  "package_info": {
    "id": "quick_${scenario}_$(date +%Y%m%d_%H%M%S)",
    "name": "Quick Stop - $title",
    "version": "2.1.0",
    "description": "Fermata rapida generata per scenario: $scenario",
    "created_date": "$(generate_utc_timestamp)",
    "valid_from": "$date",
    "valid_to": "$end_date",
    "author": "Quick Stop Generator",
    "contact_email": "produzione@company.com"
  },
  "events": [
    {
      "id": "${scenario}_$(date +%Y%m%d_%H%M%S)",
      "title": "$title",
      "description": "$description",
      "start_date": "$date",
      "end_date": "$end_date",
      "start_time": "$start_time",
      "end_time": "$end_time",
      "all_day": false,
      "event_type": "$event_type",
      "priority": "$priority",
      "location": "Linee Produzione",
      "tags": ["$scenario", "quick_generated", "shift_optimized"],
      "custom_properties": {
        "department": "Produzione",
        "scenario": "$scenario",
        "duration": "$duration",
        "scheduling_strategy": "$strategy",
        "affected_shifts": "$affected_shifts_str",
        "shift_impact_level": "$impact_level",
        "workers_affected": "$workers_affected",
        "optimal_scheduling": "true",
        "quick_generated": "true",
        "generation_time": "$(generate_utc_timestamp)"
      }
    }
  ]
}
EOF
}

# Main execution
log_info "Generando scenario: ${YELLOW}$SCENARIO${NC}"
log_info "Data: ${YELLOW}$EVENT_DATE${NC}"
log_info "Durata: ${YELLOW}$DURATION${NC}"
log_info "Output: ${YELLOW}$OUTPUT_FILE${NC}"

# Check if output file exists
if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${YELLOW}[WARNING]${NC} Il file $OUTPUT_FILE esiste già"
    read -p "Sovrascrivere? (y/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        log_info "Operazione annullata"
        exit 0
    fi
fi

# Generate the JSON
generate_scenario_event "$SCENARIO" "$EVENT_DATE" "$DURATION" > "$OUTPUT_FILE"

# Validate JSON if jq is available
if command -v jq >/dev/null 2>&1; then
    if jq empty "$OUTPUT_FILE" 2>/dev/null; then
        log_success "File JSON generato e validato: $OUTPUT_FILE ✓"

        # Show impact summary
        echo ""
        echo -e "${YELLOW}📊 Riepilogo Impatto:${NC}"
        local impact_info
        impact_info=$(jq -r '.events[0] | "⏰ Orario: " + .start_time + " - " + .end_time + "\n👥 Turni: " + .custom_properties.affected_shifts + "\n👷 Operatori: " + .custom_properties.workers_affected + "\n📈 Impatto: " + .custom_properties.shift_impact_level' "$OUTPUT_FILE" 2>/dev/null)
        echo "$impact_info"

        # Special warnings for high impact scenarios
        local impact_level
        impact_level=$(jq -r '.events[0].custom_properties.shift_impact_level' "$OUTPUT_FILE" 2>/dev/null)
        case "$impact_level" in
            "HIGH"|"CRITICAL")
                echo ""
                echo -e "${RED}⚠️  ATTENZIONE: Impatto elevato sui turni!${NC}"
                echo "   Verificare disponibilità team e comunicare tempestivamente"
                ;;
            "NONE")
                echo ""
                echo -e "${GREEN}✅ Ottimo: Nessun impatto sui turni produttivi${NC}"
                ;;
        esac

    else
        log_error "JSON generato con errori di sintassi"
        exit 1
    fi
else
    log_success "File JSON generato: $OUTPUT_FILE"
    echo -e "${YELLOW}[INFO]${NC} Installa 'jq' per validazione automatica"
fi

# Show file info
file_size=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
log_info "Dimensione file: $file_size"
log_success "Pronto per import in Q-DUE Events System 🎉"

# Scenario-specific next steps
case "$SCENARIO" in
    "emergency-now")
        echo ""
        echo -e "${RED}🚨 EMERGENZA - AZIONI IMMEDIATE:${NC}"
        echo "  1. Importare SUBITO in Q-DUE Events"
        echo "  2. Notificare supervisori e operatori"
        echo "  3. Aggiornare dashboard produzione"
        ;;
    "shortage-morning")
        echo ""
        echo -e "${PURPLE}📦 SHORTAGE - COMUNICAZIONI:${NC}"
        echo "  1. Avvisare turno mattino di NON presentarsi"
        echo "  2. Coordinare con logistica per rifornimenti"
        echo "  3. Pianificare recupero produzione"
        ;;
    "maintenance-night")
        echo ""
        echo -e "${BLUE}🔧 MANUTENZIONE - COORDINAMENTO:${NC}"
        echo "  1. Confermare disponibilità team manutenzione"
        echo "  2. Preparare attrezzature necessarie"
        echo "  3. Verificare che turno notte sia informato"
        ;;
esac