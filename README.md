# joystickmanager

Serviço Linux para gerenciamento unificado de controles de jogos no Arch Linux/CachyOS.

## Escopo aprovado

- Numeração global por ordem de conexão, até oito jogadores.
- Suporte planejado para DS3, Switch Pro, Joy-Con, Xbox 360, Xbox One, Xbox Series X/S, DualShock 4 e DualSense.
- Controles USB e Bluetooth, com Joy-Con exclusivamente via Bluetooth.
- `joycond` como componente opcional para combinar um par de Joy-Cons em um único dispositivo virtual.
- LEDs de jogador, indicação de bateria quando o driver expuser o recurso e desligamento automático apenas para Bluetooth.
- Bluetooth mantido quando o mesmo controle também for conectado por USB para carregamento, quando o firmware permitir.
- Integração sem duplicação com Steam Input.

## Estado atual

O serviço unificado inicial está em `joystickmanager.sh` e `joystickmanager.service`. Os demais scripts são a implementação histórica por modelo e permanecem até que a versão unificada seja validada com hardware real.

## Instalação prevista

A instalação será documentada depois da validação do suporte a cada família. Não instale os serviços individuais e o serviço unificado simultaneamente.

## Licença

MIT. Consulte `LICENSE`.
