# joystickmanager

Serviço Linux para gerenciamento unificado de controles de jogos no Arch Linux/CachyOS.

## Escopo aprovado

- Numeração global por ordem de conexão, até oito jogadores.
- Implementação inicial/testável: DS3 original, Switch Pro original e Joy-Con original/third-party.
- Suporte planejado para Xbox 360, Xbox One, Xbox Series X/S, DualShock 4 e DualSense.
- Suporte futuro planejado para Nintendo Switch 2 Pro Controller e Joy-Con 2.
- Controles USB e Bluetooth, com Joy-Con exclusivamente via Bluetooth.
- `joycond` como componente opcional para combinar um par de Joy-Cons em um único dispositivo virtual.
- LEDs de jogador, indicação de bateria quando o driver expuser o recurso e desligamento automático apenas para Bluetooth.
- Bluetooth mantido quando o mesmo controle também for conectado por USB para carregamento, quando o firmware permitir.
- Integração sem duplicação com Steam Input.

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

## Instalação prevista

A instalação será documentada depois da validação do suporte a cada família. Não instale os serviços individuais e o serviço unificado simultaneamente.

## Licença

MIT. Consulte `LICENSE`.
