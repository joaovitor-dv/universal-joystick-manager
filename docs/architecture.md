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
2. O estado de jogadores é efêmero e deve ser limpo quando o dispositivo desaparece.
3. O `joycond` cria o par virtual; o gerenciador coordena a numeração e sincroniza a apresentação dos dois Joy-Cons.
4. A bateria só será exibida quando o kernel ou o driver fornecer uma fonte confiável.
5. O Xbox 360 participa da numeração, mas não terá medição de bateria.
6. Interfaces USB que pertençam ao mesmo controle Bluetooth serão tratadas como carregamento quando a identidade puder ser confirmada.
7. O Steam Input não deve criar um segundo dispositivo para os Joy-Cons combinados.

## Limites

O serviço não pode forçar um firmware a manter Bluetooth quando a inserção do cabo muda fisicamente o modo do controle. Também não pode garantir que um clone de Joy-Con implemente o protocolo esperado pelo `joycond`.
