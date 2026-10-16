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
8. No Switch Pro Controller, um cabo USB de dados faz o firmware trocar do Bluetooth para USB. Para manter Bluetooth durante a carga, use um cabo somente de carga, ou desautorize o dispositivo USB (`echo 0 > /sys/bus/usb/devices/<porta>/authorized`): validado à mão no hardware, o controle ficou em Bluetooth e `Charging`. A regra udev opt-in em `udev/` automatiza isso, mas **não foi testada** e desliga o uso com fio.
9. O Steam Input não deve criar um segundo dispositivo para os Joy-Cons combinados.
10. Os controles reconhecidos vêm de `controllers.tsv` (nome do input, fabricante, driver esperado, estado). Só o estado `validated` é ativo por padrão; sem a tabela, o serviço usa uma lista fixa dos controles validados.
11. O adaptador Bluetooth precisa estar `connectable` para controles como o Pro Controller reconectarem por HOME; o serviço reafirma o modo periodicamente porque o `bluetoothd` pode desligá-lo ao reiniciar.
12. Os LEDs são reaplicados a cada `JOYMANAGER_LED_REFRESH` s (padrão 10), não a cada ciclo de 2 s: cada escrita é um subcomando HID, e reescrever tudo a cada ciclo derrubava o Pro Controller por timeout. Mudanças reais (carga, bateria) são escritas na hora.

## Limites

O serviço sozinho não impede que o firmware troque para USB quando o cabo de dados entra; isso só se evita desautorizando o dispositivo USB ou usando um cabo de carga. Também não pode garantir que um clone de Joy-Con implemente o protocolo esperado pelo `joycond`. Com `joycond`, LEDs piscando podem indicar pareamento lógico pendente; Pro Controllers devem receber **L + R**, e um par virtual combinado de Joy-Cons deve receber **+ e -**.

## Extensões futuras não testadas

- Xbox 360, Xbox One e Xbox Series X/S.
- DualShock 4 e DualSense.
- Nintendo Switch 2 Pro Controller.
- Nintendo Switch 2 Joy-Con.
- Controles 8BitDo.
- Controles GameSir.

Esses modelos só serão marcados como suportados após testes com hardware real e confirmação dos caminhos de bateria, LEDs, entrada e conexão.

O mesmo critério vale para cada modelo específico dentro das marcas 8BitDo e GameSir. Modos XInput, DInput, Switch, Bluetooth, USB e receptores proprietários devem ser validados separadamente.
