# Arquitetura

## Fluxo

```text
drivers Linux / Bluetooth / USB
          |
          v
  joystickmanager.service ---- joycond (opcional)
          |
          +--> numeração global
          +--> LEDs e bateria
          +--> idle timeout Bluetooth
          +--> filtro de duplicidade USB/Bluetooth
          v
      jogos / Steam
```

## Decisões

1. A identidade de jogador é atribuída pela ordem de conexão e não pelo MAC.
2. O limite lógico inicial é de oito jogadores; os LEDs de quatro posições usam máscaras para os jogadores 5–8.
3. O estado de jogadores é efêmero e deve ser limpo quando o dispositivo desaparece.
4. O `joycond` cria o par virtual; o gerenciador coordena a numeração e sincroniza a apresentação dos dois Joy-Cons.
5. A bateria só será exibida quando o kernel ou o driver fornecer uma fonte confiável.
6. O Xbox 360 participa da numeração, mas não terá medição de bateria.
7. Interfaces USB que pertençam ao mesmo controle Bluetooth serão tratadas como carregamento quando a identidade puder ser confirmada.
8. No Switch Pro Controller, um cabo USB de dados pode fazer o firmware trocar do Bluetooth para USB. Para manter Bluetooth durante a carga, o cabo deve ser somente de carga ou estar ligado a uma fonte que não exponha dados ao computador.
9. O Steam Input não deve criar um segundo dispositivo para os Joy-Cons combinados.

## Limites

O serviço não pode forçar um firmware a manter Bluetooth quando a inserção do cabo muda fisicamente o modo do controle. Também não pode garantir que um clone de Joy-Con implemente o protocolo esperado pelo `joycond`. Com `joycond`, LEDs piscando podem indicar pareamento lógico pendente; Pro Controllers devem receber **L + R**, e um par virtual combinado de Joy-Cons deve receber **+ e -**.

## Extensões futuras não testadas

- Xbox 360, Xbox One e Xbox Series X/S.
- DualShock 4 e DualSense.
- Nintendo Switch 2 Pro Controller.
- Nintendo Switch 2 Joy-Con.
- Controles 8BitDo.
- Controles GameSir.

Esses modelos só serão marcados como suportados após testes com hardware real e confirmação dos caminhos de bateria, LEDs, entrada e conexão.

O mesmo critério vale para cada modelo específico dentro das marcas 8BitDo e GameSir. Modos XInput, DInput, Switch, Bluetooth, USB e receptores proprietários devem ser validados separadamente.
