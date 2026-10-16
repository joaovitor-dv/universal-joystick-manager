# Dependências por distribuição

## Alvo da primeira versão

A primeira versão suporta distribuições Linux com:

- kernel Linux com `evdev`, `joydev` e os drivers dos controles;
- `udev` para detectar conexão e desconexão;
- `systemd` para executar o serviço;
- `dbus` e BlueZ para Bluetooth;
- `uinput` quando for necessário criar o controle virtual do `joycond`.

Distribuições sem systemd poderão usar o script diretamente, mas não são alvo da unidade `.service` atual.

## Dependências

| Componente | Obrigatório | Função |
|---|---:|---|
| Linux kernel | Sim | Entrada, USB, Bluetooth HID e drivers de controle |
| `udev`/`systemd-udev` | Sim | Eventos de conexão e identificação dos dispositivos |
| `systemd` | Sim na primeira versão | Iniciar e reiniciar o `joystickmanager` |
| `dbus` | Sim para Bluetooth | Comunicação do BlueZ |
| `bluez`/`bluetoothd` | Para Bluetooth | Pareamento, conexão e desconexão |
| `bluez-utils` ou equivalente | Para diagnóstico | `bluetoothctl` e ferramentas auxiliares |
| `joycond` | Opcional | Combinar dois Joy-Cons em um controle virtual |
| `uinput` | Para `joycond` | Criar o controle virtual combinado |
| `evtest` | Apenas teste | Verificar botões e eixos antes dos jogos |
| `jstest-gtk`/`joystick` | Apenas teste | Verificar a API de joystick |
| `upower` | Opcional | Exibir bateria na área de trabalho; não é exigido pelo gerenciador |

## Drivers do kernel

A fonte única de quais controles o serviço reconhece e de qual driver se espera é
[`controllers.tsv`](../controllers.tsv). Para conferir o que o seu sistema tem, rode:

```text
joystickmanager-doctor
```

Ele só lê o sistema: mostra, por família, se cada módulo do kernel está carregado,
disponível ou ausente, e quais controles conectados casaram com um perfil.

| Família | Estado | Módulo esperado |
|---|---|---|
| DualShock 3 | validado | `hid_sony` |
| Switch Pro e Joy-Con | validado | `hid_nintendo` |
| Controle virtual (`joycond`) | validado | `uinput` |
| Xbox 360, One, Series (com fio) | experimental | `xpad` |
| Xbox por Bluetooth | experimental | `hid_microsoft`; `xpadneo` (externo, opcional) |
| Receptor sem fio Xbox | experimental | `xone` (externo, opcional) |
| DualShock 4 e DualSense | experimental | `hid_playstation` |
| 8BitDo, GameSir, Logitech, Razer, Redragon, clones XInput | experimental | `xpad`, `hid_generic` etc., conforme modelo e modo |
| Switch 2 | planejado | sem driver estável |

Só as famílias **validadas** ficam ativas por padrão. As demais exigem
`JOYMANAGER_EXPERIMENTAL=1` no ambiente do serviço. Os módulos acima são o esperado
pelo conhecimento do Linux e **não foram validados em hardware**, exceto os validados.

Drivers externos (`xone`, `xpadneo`) não são instalados pelo `install.sh` nem
incluídos nos pacotes: são código de terceiros, compilado via DKMS, e devem ser
instalados por você a partir do pacote da sua distribuição ou do projeto upstream.

## Arch Linux/CachyOS

Pacotes base:

```text
bluez bluez-utils upower evtest joystick
```

O `joycond` normalmente será instalado pelo AUR ou compilado a partir do projeto upstream. O serviço precisa estar ativo:

```text
bluetooth.service
joycond.service       (somente se o pareamento combinado for usado)
joystickmanager.service
```

## Debian/Ubuntu

Nomes usuais:

```text
bluez evtest joystick upower dbus udev
```

O `joycond` pode exigir compilação a partir do código-fonte, caso não exista pacote mantido pela distribuição. Também é necessário instalar os headers de desenvolvimento do kernel para qualquer driver DKMS futuro.

## Fedora

Nomes usuais:

```text
bluez evtest joystick upower dbus systemd-udev
```

O `joycond` e drivers DKMS adicionais devem ser tratados como componentes opcionais instalados separadamente.

## Xbox em versões futuras

Quando o suporte Xbox for implementado, a escolha dependerá da conexão:

- USB e receptor Xbox 360: `xpad`/`xone`, conforme o modelo;
- Xbox One/Series via Bluetooth: `xpadneo` é o candidato para bateria e mapeamento;
- `dkms` e headers do kernel podem ser necessários para drivers externos.

Esses componentes não devem ser instalados pela primeira versão sem hardware Xbox para validação.

## Verificação automática planejada

O instalador futuro deverá verificar e relatar:

1. distribuição e gerenciador de pacotes;
2. presença de `systemd`, `udev`, `dbus` e `bluetoothctl`;
3. estado de `bluetooth.service`;
4. presença de `/dev/uinput` quando `joycond` for solicitado;
5. módulos `hid-sony` e `hid-nintendo`;
6. disponibilidade de `joycond.service`;
7. ferramentas de diagnóstico opcionais.

O instalador não deve instalar drivers externos automaticamente sem confirmação explícita.

## Artefatos de instalação

- `install.sh`: instala dependências base e a unidade systemd em Arch, Debian/Ubuntu ou Fedora.
- `packaging/arch/PKGBUILD`: pacote nativo para Arch e derivados.
- `packaging/debian/`: esqueleto de pacote `.deb`.
- `packaging/fedora/`: especificação RPM.

Esses artefatos são a primeira camada de portabilidade e ainda precisam ser construídos em cada distribuição antes de uma versão formal do pacote.
