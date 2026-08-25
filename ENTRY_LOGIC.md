# Логика входа

Схема соответствует `OnTick()` в `SMC_PinSweep_EA.mq5` — порядок проверок и
причины отказа именно такие, как в коде (и как попадают в `SIGNAL_REJECTED`
в CSV-логе).

```mermaid
flowchart TD
    A[Новый закрытый бар H1] --> B{Пятница, час >= InpFridayCloseHour?}
    B -- да --> B1[Закрыть всё, выйти]
    B -- нет --> C[ExpirePendingOrders]
    C --> D[Обновить структуру D1 и H1]
    D --> E{Позиций + лимиток < InpMaxPositions?}
    E -- нет --> X0[Выход]
    E -- да --> F{Пятница, час >= InpFridayNoNewHour?}
    F -- да --> X0
    F -- нет --> G{Тренд D1 == тренд H1, оба != NONE?}
    G -- нет --> X0
    G -- да --> H{Спред <= InpMaxSpreadPoints?}
    H -- нет --> X0
    H -- да --> I{Диапазон свечи >= InpMinRangeATR * ATR?}
    I -- нет --> R1[reason=pinbar_range]
    I -- да --> J{Доминирующий хвост >= InpMinTailRatio?}
    J -- нет --> R2[reason=pinbar_tail]
    J -- да --> K{Направление пинбара == тренду?}
    K -- нет --> X0
    K -- да --> L{Новостное окно активно?}
    L -- да --> R3["reason=news"]
    L -- нет --> M{Есть неснятый свинг напротив входа?}
    M -- нет --> R4[нет неснятого свинг-лоу/хая]
    M -- да --> N{Хвост снял уровень, close вернулся внутрь?}
    N -- нет --> X0
    N -- да --> O{InpUsePremiumFilter: откат >= InpMinRetracement?}
    O -- нет --> R5[reason=откат < InpMinRetracement]
    O -- да --> P[PlaceLimitOrder]
    P --> Q{Цена/стопы прошли проверки STOPS_LEVEL, лот > 0?}
    Q -- нет --> X0
    Q -- да --> S[BuyLimit / SellLimit,\nуровень помечается swept]

    R1 & R2 & R3 & R4 & R5 --> X0
```

## Геометрия входа (пинбар BULL)

![Пример входа BUY: снятие свинг-лоу пинбаром](ENTRY_EXAMPLE.svg)


```
        high ──┐
                │  верхний хвост (upperTail)
     bodyTop ───┤
        Open/   │  тело свечи
       Close  ──┤
   bodyBottom ───┤
                │
        entry ──┤  ← min(Open,Close) − InpEntryRetrace * lowerTail
                │
                │  lowerTail (в него и идёт откат для входа)
                │
           sl ──┤  ← low − InpSLBufferPoints
         low  ──┘

  tp = entry + (entry − sl) * InpRiskRewardRatio
```

Для BEAR-пинбара всё зеркально: вход внутрь верхнего хвоста, стоп над
high + буфер, тейк вниз от входа на `InpRiskRewardRatio` от риска.

`InpEntryRetrace = 0` — вход от края тела (сразу на границе тела и хвоста),
чем больше значение, тем глубже внутрь хвоста и тем реже цена доходит
до уровня за `InpPendingLifeBars` баров.
