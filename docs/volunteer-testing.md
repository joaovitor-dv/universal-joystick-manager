# Programa de testes voluntários

O projeto precisa de pessoas com controles que não estão disponíveis para validação local. O objetivo é testar detecção, entrada, numeração, bateria, LEDs, Bluetooth, USB e receptores sem fio sem exigir acesso remoto ao computador do voluntário.

## Famílias procuradas

- 8BitDo: Ultimate, Pro 2, SN30, SN30 Pro, M30, Zero, Lite e outros modelos.
- GameSir: T4, T4 Pro, T4 Kaleid, Nova, G7, Cyclone e outros modelos.
- Xbox 360, Xbox One e Xbox Series X/S.
- DualShock 4 e DualSense.
- Nintendo Switch 2 Pro Controller e Joy-Con 2.

## O que o voluntário precisa informar

- distribuição e versão do kernel;
- modelo exato e revisão, se disponível;
- conexão usada: USB, Bluetooth ou receptor;
- se o controle aparece como XInput, DInput, Switch ou outro modo;
- se há LEDs de jogador, RGB, indicador de bateria ou nenhum deles;
- se o controle possui pilhas, bateria interna ou bateria removível.

Não publique endereço MAC completo, número de série, nome de usuário, caminho pessoal ou logs que contenham esses dados. Substitua identificadores por `XX` antes de enviar.

## Coleta segura

Execute os comandos abaixo com o controle conectado:

```text
uname -a
cat /proc/bus/input/devices
lsusb
bluetoothctl devices Connected
```

Para testar a entrada, use `evtest` apenas no `/dev/input/eventN` correspondente ao controle. Não envie o conteúdo de outros dispositivos.

## Resultado esperado

O voluntário deve informar:

1. se o controle foi detectado;
2. qual nome e modo apareceram;
3. quais botões e eixos funcionaram;
4. se o controle recebeu um jogador de 1 a 8;
5. se a bateria apareceu;
6. se LEDs ou RGB responderam;
7. se houve duplicação entre USB/Bluetooth, Steam Input ou receptor.

Um modelo só será promovido de experimental para validado depois de pelo menos um teste reproduzível e documentado.
