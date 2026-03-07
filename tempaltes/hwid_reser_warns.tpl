{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║                    HWID RESET WARNINGS TEMPLATE                               ║
║         Сброс счётчиков предупреждений и времени уведомлений                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОПИСАНИЕ:
  Сбрасывает hwid_warn_count до 0 и удаляет время последнего уведомления.
  Запустить один раз для полной очистки статистики.
#}}

{{ USE date }}
{{ current_time = date.format(date.now, '%s') }}
{{ reset_flags_count = 0 }}
{{ reset_notify_count = 0 }}
{{ results = [] }}

{{# Перебираем все storage записи #}}
{{ FOREACH st_item IN storage.list }}
    
    {{# Сброс флагов hf_* (warns, exceeded, blocked) #}}
    {{ IF st_item.name.match('^hf_') }}
        {{ flag_data = storage.read('name', st_item.name) }}
        
        {{# Сбрасываем если есть warns или exceeded #}}
        {{ IF flag_data.hwid_warn_count > 0 || flag_data.hwid_exceeded }}
            {{ reset_flags_count = reset_flags_count + 1 }}
            
            {{# Сохраняем с обнулённым счётчиком #}}
            {{ save_result = storage.save(st_item.name, {
                'hwid_exceeded' => 0,
                'hwid_warn_count' => 0,
                'hwid_blocked' => 0,
                'hwid_device_count' => flag_data.hwid_device_count,
                'hwid_device_limit' => flag_data.hwid_device_limit,
                'username' => flag_data.username,
                'remna_uuid' => flag_data.remna_uuid,
                'warns_reset_at' => current_time
            }) }}
            
            {{ results.push({
                'key' => st_item.name,
                'username' => flag_data.username,
                'old_warns' => flag_data.hwid_warn_count,
                'was_blocked' => flag_data.hwid_blocked,
                'action' => 'reset_flags'
            }) }}
        {{ END }}
    {{ END }}
    
    {{# Удаляем время последнего уведомления hn_* #}}
    {{ IF st_item.name.match('^hn_') }}
        {{ reset_notify_count = reset_notify_count + 1 }}
        {{ del_result = storage.del(st_item.name) }}
        {{ results.push({
            'key' => st_item.name,
            'action' => 'deleted_notify_time'
        }) }}
    {{ END }}
    
{{ END }}

{{# === РЕЗУЛЬТАТ === #}}
{
    "status": 1,
    "reset_flags_count": {{ reset_flags_count }},
    "reset_notify_count": {{ reset_notify_count }},
    "results": {{ toJson(results) }}
}
