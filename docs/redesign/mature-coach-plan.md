# Mature Coach Redesign Plan

## Summary
- Этот документ фиксирует переход от game-like слоя к спокойному `progress + coach`.
- Базовая логика остаётся локальной и rule-based: без чат-бота, без облачной зависимости, без случайных советов.
- Главный мотиватор продукта: доверие, ясность, поступательное движение, а не игровая стимуляция.

## Product Tone
- Визуальный тон: premium fintech, спокойный контраст, короткие статусы, минимум декоративной “игры”.
- Язык: взрослый, поддерживающий, объяснимый.
- Помощник не даёт общих советов вроде “просто экономь”. Он предлагает безопасную альтернативу и указывает, почему она уместна.

## UX Principles
- `Dashboard` показывает один главный coach insight, а не набор игровых сигналов.
- `Coach & Progress` hub заменяет hero/game persona и концентрируется на:
  - `This Week`
  - `Progress`
  - `Milestones`
  - `Advice History`
- Live Activity и Dynamic Island держат в фокусе бюджет дня. Дополнительные celebrations допустимы только для финансово значимых событий и должны быть короткими.

## Data Rules
- `GamificationEngine` сохраняется как внутренний расчётный слой для consistency и milestones.
- Front-facing UI не использует `XP`, `Level`, `Legend`, `Money Mage` и подобную лексику как главный мотиватор.
- `AchievementStore` остаётся каталогом milestones, но все формулировки становятся finance-neutral.
- `Category` получает `CategoryAdviceRole`:
  - `essential`
  - `fixed`
  - `flexible`
  - `income`

## Advice Rules
- Каждый совет обязан включать:
  - короткий headline
  - message
  - reason
  - safer alternative
  - CTA
- Правила по ролям:
  - `essential`: optimize / substitute, но не “убирай совсем”
  - `fixed`: renegotiate / reschedule / prepare
  - `flexible`: reduce / pause / swap
  - `income`: не использовать как цель сокращения
- Если категория связана с едой или другой essential-зоной, совет должен предлагать замену или перенос экономии на flexible spend.

## UI Delivery
- `Dashboard`
  - coach card replaces game teaser
  - secondary progress strip показывает consistency, active plans, budget stability
  - commitments остаются отдельным блоком
- `Coach & Progress`
  - без emoji-avatar как главного центра экрана
  - без trophy-wall
  - milestones отображаются как understated accomplishments
- `Live Activity / Dynamic Island`
  - главный сигнал: budget status
  - короткие celebration states: `goalReached`, `debtPaidOff`
  - без XP progress strip, streak badge и level callouts

## Acceptance Criteria
- В `Dashboard`, profile hub, notifications и Live Activity нет детской или аркадной лексики.
- Essential spending never gets blunt-cut advice.
- Food advice предлагает safer alternatives, а не “не ешь”.
- Budget progress остаётся главным сигналом в ActivityKit.
- Мотивация чувствуется как спокойный coaching layer, а не как мини-игра.
