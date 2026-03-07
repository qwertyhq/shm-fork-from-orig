{{# Шаблон активации промокода: начисление бонусов #}}
{{ RETURN IF !promo }}
{{ RETURN IF !promo.settings }}

{{ amount = promo.settings.amount }}
{{ RETURN IF !amount || amount == 0 }}

{{ result = user.add_bonus( amount, 'Зачисление бонусов по промокоду: ' _ promo.id ) }}
{{ IF result }}
Промокод {{ promo.id }} активирован. Начислено {{ amount }} руб.
{{ END }}