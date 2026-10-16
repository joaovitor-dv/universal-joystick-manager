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

t_pro_controller_usb_e_registrado() {
    # Via USB o kernel nomeia o dispositivo com o prefixo do fabricante e há um nó IMU.
    local d="$T/dev/0003:057E:2009.0016"
    mkdir -p "$d" "$sys_input/event7" "$sys_input/event8"
    printf '%s\n' $A >"$d/uniq"
    printf 'Nintendo Co., Ltd. Pro Controller\n' >"$d/name"
    ln -sfn "$d" "$sys_input/event7/device"
    printf 'Nintendo Co., Ltd. Pro Controller (IMU)\n' >"$d/name_imu"
    mkdir -p "$T/dev/imu"; printf '%s\n' $A >"$T/dev/imu/uniq"
    printf 'Nintendo Co., Ltd. Pro Controller (IMU)\n' >"$T/dev/imu/name"
    mv "$T/dev/imu" "$T/dev/0003:057E:2009.0016-imu"
    ln -sfn "$T/dev/0003:057E:2009.0016-imu" "$sys_input/event8/device"
    register_event event7; register_event event8
    check "Pro Controller USB recebe slot 1" 1 "$(slot_of $A)"
    check "IMU não cria linha extra" 1 "$(wc -l <"$slots_file")"
}

t_connectable_e_reafirmado() {
    # btmgmt falso no PATH: ensure_connectable deve chamá-lo com "connectable on".
    mkdir -p "$T/bin"
    printf '#!/bin/sh\necho "$@" >>"%s/btmgmt.log"\n' "$T" >"$T/bin/btmgmt"; chmod +x "$T/bin/btmgmt"
    PATH="$T/bin:$PATH" ensure_connectable; PATH="$T/bin:$PATH" ensure_connectable
    check "btmgmt connectable on chamado a cada reafirmação" "connectable on connectable on" "$(tr '\n' ' ' <"$T/btmgmt.log" | sed 's/ $//')"
}

for t in t_ordem_de_chegada t_slot_liberado_vai_para_quem_chega \
         t_reconexao_com_linha_antiga_nao_limpa t_mesmo_controle_ainda_presente_mantem_slot \
         t_pro_controller_usb_e_registrado \
         t_connectable_e_reafirmado; do
    printf '# %s\n' "$t"; run "$t"
done
printf '\n%s falha(s)\n' "$fails"
exit "$fails"
