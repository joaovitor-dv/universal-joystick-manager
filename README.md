# joystickmanager

Serviço Linux para gerenciamento unificado de controles de jogos no Arch Linux/CachyOS.

## Escopo aprovado

- Numeração global por ordem de conexão, até oito jogadores.
- Implementação inicial/testável: DS3 original, Switch Pro original e Joy-Con original/third-party.
- Suporte planejado para Xbox 360, Xbox One, Xbox Series X/S, DualShock 4 e DualSense.
- Suporte futuro planejado para Nintendo Switch 2 Pro Controller e Joy-Con 2.
- Suporte experimental planejado para controles 8BitDo e GameSir.
- Controles USB e Bluetooth, com Joy-Con exclusivamente via Bluetooth.
- `joycond` como componente opcional para combinar um par de Joy-Cons em um único dispositivo virtual.
- LEDs de jogador, indicação de bateria quando o driver expuser o recurso e desligamento automático apenas para Bluetooth.
- O desligamento automático fica configurado inicialmente para 30 minutos (`JOYMANAGER_IDLE_TIMEOUT=1800`) durante a fase de testes.
- Os LEDs são reaplicados a cada 10 s (`JOYMANAGER_LED_REFRESH=10`; `0` reaplica a cada ciclo de 2 s). Cada escrita de LED é um subcomando HID, e reescrever tudo a cada 2 s sobrecarregava o Pro Controller (erros `exceeded max attempts` e quedas por `timeout waiting for input report`). Mudanças reais, como começar a carregar, são escritas na hora.
- Bluetooth mantido quando o mesmo controle também for conectado por USB para carregamento, quando o firmware permitir.

### Pro Controller: USB e Bluetooth

O Switch Pro Controller pode trocar do Bluetooth para USB quando um cabo de
dados é conectado ao computador. Nesse caso, o firmware pode desconectar o
Bluetooth — o `joystickmanager` não consegue impedir essa troca. Para carregar
sem substituir o transporte Bluetooth, use um cabo somente para carga, um
adaptador sem linhas de dados ou um carregador/hub que não exponha USB ao
computador.

Quando o `joycond` estiver ativo, os LEDs de jogador podem piscar enquanto o
controle aguarda o pareamento lógico. Pressione **L + R** simultaneamente em
cada Pro Controller para concluir esse pareamento; para um dispositivo virtual
de Joy-Cons combinados, use **+ e -**.
- Integração sem duplicação com Steam Input.
- Compatibilidade planejada entre distribuições por meio de uma matriz explícita de dependências.

## Carregar o Pro Controller sem perder o Bluetooth

Ligar o Pro Controller por um cabo **de dados** faz o firmware abandonar o Bluetooth. O serviço sozinho não impede isso. O que funcionou à mão no hardware foi desautorizar o dispositivo USB (`echo 0 | sudo tee /sys/bus/usb/devices/<porta>/authorized`): o controle voltou ao Bluetooth e continuou carregando. A regra opcional [`udev/99-joystickmanager-procontroller-charge-only.rules`](udev/99-joystickmanager-procontroller-charge-only.rules) faz isso automaticamente, com `sudo ./install.sh --pro-charge-only`.

Limitações: com a regra o controle **não funciona com fio**; o kernel já enumerou o dispositivo quando o udev roda, então o controle pode sair do Bluetooth por instantes ao plugar o cabo; a regra em si ainda não foi testada no hardware. Um cabo somente de carga continua sendo a solução sem ressalvas.

## Estado atual

O serviço unificado inicial está em `joystickmanager.sh` e `joystickmanager.service`. Os demais scripts são a implementação histórica por modelo e permanecem até que a versão unificada seja validada com hardware real.

## Matriz de teste disponível

| Hardware | Quantidade | Conexões disponíveis |
|---|---:|---|
| DualShock 3 original | 1 | Bluetooth e USB |
| Switch Pro original | 2 | Bluetooth e USB |
| Joy-Con original | 1 par | Bluetooth |
| Joy-Con third-party | 1 par | Bluetooth |

Xbox, DualShock 4, DualSense e controles Switch 2 ficam documentados como alterações futuras e não serão declarados compatíveis sem hardware para validação.

8BitDo, GameSir, Logitech, Razer, Redragon e clones XInput entram neste branch experimental como famílias de suporte não validado, descritas em [`controllers.tsv`](controllers.tsv). Elas só ficam ativas com `JOYMANAGER_EXPERIMENTAL=1`; `joystickmanager-doctor` mostra os drivers do kernel e o que cada controle conectado casou. A compatibilidade dependerá do modelo, modo de conexão e driver apresentado ao Linux; não será assumida apenas pela marca.

## Instalação prevista

A instalação será documentada depois da validação do suporte a cada família. Não instale os serviços individuais e o serviço unificado simultaneamente.

As dependências por distribuição estão em [`docs/dependencies.md`](docs/dependencies.md). A primeira versão do serviço tem como alvo distribuições com systemd, udev, D-Bus e BlueZ; `joycond`, `upower` e ferramentas de teste são opcionais conforme o uso.

Há também um instalador comum em `install.sh` e metadados iniciais em `packaging/arch`, `packaging/debian` e `packaging/fedora`. O instalador não instala drivers externos ou `joycond` automaticamente.

Para participar dos testes de controles ainda não disponíveis, consulte [`docs/volunteer-testing.md`](docs/volunteer-testing.md).

## Licença

MIT. Consulte `LICENSE`.
