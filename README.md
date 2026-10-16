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
- Bluetooth mantido quando o mesmo controle também for conectado por USB para carregamento, quando o firmware permitir.
- Integração sem duplicação com Steam Input.
- Compatibilidade planejada entre distribuições por meio de uma matriz explícita de dependências.

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

8BitDo e GameSir entram neste branch experimental como famílias de suporte não validado. A compatibilidade dependerá do modelo, modo de conexão e driver apresentado ao Linux; não será assumida apenas pela marca.

## Instalação prevista

A instalação será documentada depois da validação do suporte a cada família. Não instale os serviços individuais e o serviço unificado simultaneamente.

As dependências por distribuição estão em [`docs/dependencies.md`](docs/dependencies.md). A primeira versão do serviço tem como alvo distribuições com systemd, udev, D-Bus e BlueZ; `joycond`, `upower` e ferramentas de teste são opcionais conforme o uso.

Há também um instalador comum em `install.sh` e metadados iniciais em `packaging/arch`, `packaging/debian` e `packaging/fedora`. O instalador não instala drivers externos ou `joycond` automaticamente.

Para participar dos testes de controles ainda não disponíveis, consulte [`docs/volunteer-testing.md`](docs/volunteer-testing.md).

## Licença

MIT. Consulte `LICENSE`.
