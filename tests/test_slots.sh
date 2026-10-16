#!/usr/bin/env bash
# Testes de numeração de jogadores (ordem de conexão) com sysfs falso.
# Uso: tests/test_slots.sh   (status de saída = número de falhas)
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

A=AA:AA:AA:AA:AA:01 B=BB:BB:BB:BB:BB:02 C=CC:CC:CC:CC:CC:03 D=DD:DD:DD:DD:DD:04
fails=0

setup() {
    T=$(mktemp -d)
    export JOYMANAGER_RUNTIME_DIR="$T/run" JOYMANAGER_SYS_INPUT="$T/input"
    mkdir -p "$T/run" "$T/input" "$T/dev"
    # shellcheck source=../joystickmanager.sh
    source "$here/joystickmanager.sh"
}

# connect <evento> <mac> [nome]
connect() {
    local ev=$1 mac=$2 name=${3:-Pro Controller} d
    d="$T/dev/0005:057E:2009.$mac"
    mkdir -p "$d" "$sys_input/$ev"
    printf '%s\n' "$mac" >"$d/uniq"
    printf '%s\n' "$name" >"$d/name"
    ln -sfn "$d" "$sys_input/$ev/device"
    register_event "$ev"
}
disconnect() { rm -rf "${sys_input:?}/$1"; }
slot_of() { awk -F '\t' -v i="$1" '$1==i{print $2}' "$slots_file"; }

check() { # descrição esperado obtido
    if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"
    else printf 'FAIL - %s (esperado=%s obtido=%s)\n' "$1" "$2" "$3"; _f=$((_f+1)); fi
}

run() { # executa o cenário $1 num subshell isolado e soma as falhas
    local rc
    ( _f=0; setup; "$1"; exit "$_f" ); rc=$?
    fails=$((fails+rc))
}

t_ordem_de_chegada() {
    connect event1 $A; connect event2 $B; connect event3 $C
    check "A chega primeiro -> slot 1" 1 "$(slot_of $A)"
    check "B chega depois   -> slot 2" 2 "$(slot_of $B)"
    check "C chega por último -> slot 3" 3 "$(slot_of $C)"
}

t_slot_liberado_vai_para_quem_chega() {
    connect event1 $A; connect event2 $B; connect event3 $C
    disconnect event2; cleanup_missing
    connect event4 $D
    check "D ocupa o slot liberado por B" 2 "$(slot_of $D)"
    check "A e C não mudam de slot" "1 3" "$(slot_of $A) $(slot_of $C)"
}

t_reconexao_com_linha_antiga_nao_limpa() {
    # A e B caem; a limpeza periódica (2 s) ainda não rodou; B volta.
    connect event1 $A; connect event2 $B; connect event3 $C
    disconnect event1; disconnect event2
    connect event4 $B
    check "B reconectado entra como nova chegada (menor slot livre)" 1 "$(slot_of $B)"
    check "C mantém o slot 3" 3 "$(slot_of $C)"
}

t_mesmo_controle_ainda_presente_mantem_slot() {
    # Troca BT -> USB: o mesmo MAC aparece em outro evento enquanto o antigo existe.
    connect event1 $A; connect event2 $B
    connect event5 $B
    check "B (ainda presente) mantém o slot 2" 2 "$(slot_of $B)"
    check "não cria linha duplicada para B" 1 "$(grep -c "^$B" "$slots_file")"
}

for t in t_ordem_de_chegada t_slot_liberado_vai_para_quem_chega \
         t_reconexao_com_linha_antiga_nao_limpa t_mesmo_controle_ainda_presente_mantem_slot; do
    printf '# %s\n' "$t"; run "$t"
done
printf '\n%s falha(s)\n' "$fails"
exit "$fails"
