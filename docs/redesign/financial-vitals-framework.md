# Financial Vitals Framework

## Summary
- Этот слой переносит в finance app лучшие идеи из health/performance apps без копирования их терминологии.
- Базовые метрики:
  - `Readiness`
  - `Pressure`
  - `Reserve`
- Вторичные метрики:
  - `Runway`
  - `Left to pay in 7 days`
  - `Budget stability`

## References
- WHOOP: readiness/recovery + trends
- Oura: daily readiness against personal baseline
- Garmin: readiness zones
- YNAB: singular identity metric like `Age of Money`
- Monarch/Copilot: cash flow and upcoming commitments

## Product Translation
- `Readiness`
  - отвечает на вопрос: насколько безопасно прожить ближайшие дни без кассового стресса
- `Pressure`
  - отражает перегрузку тратами, due items и нестабильностью
- `Reserve`
  - показывает запас прочности и скорость восстановления после тяжёлых дней

## V1 Formula Shape
- `Reserve`
  - runway versus essential daily burn
  - liquid balance versus next 7 days obligations
  - budget stability
- `Pressure`
  - acute flexible spend against recent baseline
  - overspend on flexible budgets
  - due commitments versus liquid balance
  - daily spend volatility
- `Readiness`
  - weighted combination of reserve, inverse pressure and budget stability

## Dashboard Placement
- One compact vitals section directly under hero
- Three primary cards:
  - `Readiness`
  - `Pressure`
  - `Reserve`
- Two detail cards:
  - `Runway`
  - `Left to pay`

## Tone Rules
- Показывать зоны `green / yellow / red`, но не драматизировать.
- Всегда давать интерпретацию:
  - `Pressure elevated`
  - `Runway 12 days`
  - `Left to pay 48 000 ₸ this week`
- Не выдавать систему за науку уровня медицинского сенсора. Формулировка должна быть `data-driven`, а не `medically proven`.
