#!/bin/bash

{{#
╔══════════════════════════════════════════════════════════════════════════════╗
║                    REMNAWAVE API v2.3.1 BASH TEMPLATE                        ║
║         Оптимизация для SHM timeout 255s + поддержка External Squad          ║
╚══════════════════════════════════════════════════════════════════════════════╝

ОБЯЗАТЕЛЬНЫЕ НАСТРОЙКИ СЕРВЕРА:
┌─ server.settings.api.*
│  ├─ host   - URL Remnawave API (например: "https://api.example.com")
│  └─ token  - Bearer токен для авторизации
│
├─ server.settings.remnawave_squads - массив UUID Internal Squads для новых пользователей
│  └─ Пример: ["uuid-squad-1", "uuid-squad-2"]
│
├─ config.api.url - URL внутреннего API (SHM) для storage операций
│
└─ config.remnawave.*
   ├─ storage_prefix  - префикс для хранения данных (по умолчанию: "vpn_mrzb_")
   ├─ name_prefix     - префикс для имен пользователей (по умолчанию: "HQVPN_")
   ├─ hwid_limit      - глобальный лимит устройств (по умолчанию: 5)
   └─ debug_mode      - режим отладки для подробного логирования (0/1, по умолчанию: 0)

ОПЦИОНАЛЬНЫЕ НАСТРОЙКИ УСЛУГИ:
├─ us.service.settings.data_limit - лимит трафика в GB (по умолчанию: 500)
├─ us.service.settings.data_limit_reset_strategy - стратегия сброса ("MONTH")
├─ us.service.settings.hwid_limit - лимит устройств для услуги
├─ us.service.settings.squads - Internal Squads для конкретной услуги
└─ us.service.settings.external_squad - UUID External Squad (опционально)

ОПЦИОНАЛЬНЫЕ ГЛОБАЛЬНЫЕ НАСТРОЙКИ:
└─ server.settings.remnawave_external_squad - UUID External Squad для всех пользователей

TELEGRAM ИНТЕГРАЦИЯ:
├─ user.settings.telegram.chat_id - ID чата для записи в telegramId пользователя  
└─ user.settings.telegram.login - логин для включения в description

СИСТЕМНЫЕ ПЕРЕМЕННЫЕ:
├─ event_name - тип события: CREATE, ACTIVATE, BLOCK, REMOVE, PROLONGATE
├─ user.gen_session.id - ID сессии для SHM операций
├─ us.id - ID пользователя в биллинге
├─ us.expire - дата истечения услуги
└─ user.* - данные пользователя (login, full_name, etc.)

КЛЮЧЕВЫЕ ОСОБЕННОСТИ v2.3.1:
┌─ Поддержка External Squad (опционально) - один UUID на пользователя
├─ Оптимизация для SHM timeout 255s - минимизация HTTP запросов
├─ BLOCK: GET до блокировки, используем ответ disable напрямую (без update_user_configs)
├─ ACTIVATE/PROLONGATE: используем ответ PATCH вместо лишнего GET
├─ Использование готовых подписок из API (/api/sub/{shortUuid})
├─ HTTP PATCH операции вместо bulk запросов для эффективности
├─ Интеллектуальная проверка изменений (избегает ненужных API вызовов)
├─ Условное логирование с функциями log_debug/log_info
├─ Объединение обновлений настроек и Internal Squads в один запрос
├─ Fallback система для Internal Squads через API
├─ Сохранение готовых подписок и subscription_url в SHM storage
└─ API v2.3.1: userTraffic объект, externalSquadUuid как строка, числовой id

ПРИОРИТЕТЫ И ЛОГИКА:
- Приоритет HWID лимитов: услуга → глобальная конфигурация → 5
- Приоритет Internal Squads: услуга → глобальная конфигурация → все доступные squads
- Приоритет External Squad: услуга → глобальная конфигурация → не используется
- Fallback для squads: если не настроены, автоматически загружаются все доступные
- API v2.3.1 поддерживает Internal + External Squads
- Обязательна интеграция с SHM storage для сохранения конфигураций
- Логирование: log_info - всегда, log_debug - только при debug_mode=1

ИЗМЕНЕНИЯ v2.3.1 (08.12.2025):
├─ Адаптация под новую структуру API v2.3.1
├─ response.externalSquadUuid теперь строка UUID (не вложенный объект)
├─ Данные трафика переехали в response.userTraffic {usedTrafficBytes, lifetimeUsedTrafficBytes, onlineAt, firstConnectedAt, lastConnectedNodeUuid}
├─ Новое поле response.id (числовой ID пользователя)
└─ Убран response.happ объект

ИЗМЕНЕНИЯ v2.2.1 (04.12.2025):
├─ Добавлена поддержка External Squad (опционально)
├─ Приоритет: us.service.settings.external_squad → server.settings.remnawave_external_squad
└─ External Squad передаётся в CREATE и PATCH запросах

ИЗМЕНЕНИЯ v2.2.0 (04.12.2025):
├─ BLOCK: Получаем данные ДО блокировки, сохраняем ответ disable напрямую в SHM
├─ ACTIVATE: PATCH выполняется всегда (expireAt+status), используем его ответ для SHM
├─ PROLONGATE: Используем ответ PATCH вместо лишнего GET для SHM
└─ Убраны лишние GET запросы после модифицирующих операций
#}}


# Настройка логирования (можно управлять через конфигурацию)
{{ DEBUG_MODE = config.remnawave.debug_mode || 1 }}
DEBUG_MODE={{ DEBUG_MODE }}

# Функция для условного логирования
log_debug() {
  if [ "$DEBUG_MODE" = "1" ]; then
    echo "$@"
  fi
}

log_info() {
  echo "$@"
}

# Переменные из конфигурации и пользовательских данных
EVENT="{{ event_name }}"
SESSION_ID="{{ user.gen_session.id }}"
API_URL="{{ config.api.url }}" # URL для внутреннего API (SHM)
{{ STORAGE_PREFIX = config.remnawave.storage_prefix || "vpn_mrzb_" }}
REMNAWAVE_HOST="{{ server.settings.api.host }}" # URL для Remnawave API
TOKEN="{{ server.settings.api.token }}" # Токен авторизации для Remnawave API

# ГЛОБАЛЬНЫЕ НАСТРОЙКИ УСЛУГИ (для всех операций)
{{ data_limit = us.service.settings.data_limit ? (us.service.settings.data_limit * 1073741824) : 500 * 1073741824 }} # можно заменить на значение в ГБ
{{ reset_strategy = us.service.settings.data_limit_reset_strategy || 'MONTH' }}
{{ NAME_PREFIX = config.remnawave.name_prefix || "HQVPN_" }}

# Приоритет HWID лимита: услуга → глобальная конфигурация → по умолчанию
{{ IF us.service.settings.hwid_limit != '' && us.service.settings.hwid_limit != null }}
  {{ HWID_LIMIT = us.service.settings.hwid_limit + 0 }}
{{ ELSIF config.remnawave.hwid_limit != '' && config.remnawave.hwid_limit != null }}
  {{ HWID_LIMIT = config.remnawave.hwid_limit + 0 }}
{{ ELSE }}
  {{ HWID_LIMIT = 5 }}
{{ END }}

# Определение Internal Squads с приоритетом и fallback
{{ IF us.service.settings.squads && us.service.settings.squads.size > 0 }}
  {{ INTERNAL_SQUADS_JSON = toJson(us.service.settings.squads) }}
{{ ELSIF server.settings.remnawave_squads && server.settings.remnawave_squads.size > 0 }}
  {{ INTERNAL_SQUADS_JSON = toJson(server.settings.remnawave_squads) }}
{{ ELSE }}
  # Fallback: получаем все доступные Internal Squads через API
  log_debug "No squads configured. Getting all available Internal Squads from API..."
  ALL_SQUADS_RESPONSE=$(curl -sk -XGET \
    "$REMNAWAVE_HOST/api/internal-squads" \
    -H "Authorization: Bearer $TOKEN")
  
  if [ "$(echo "$ALL_SQUADS_RESPONSE" | jq -r '.response.internalSquads // empty')" != "" ]; then
    INTERNAL_SQUADS_JSON=$(echo "$ALL_SQUADS_RESPONSE" | jq -c '[.response.internalSquads[].uuid]')
    log_debug "Found squads via API fallback: $INTERNAL_SQUADS_JSON"
  else
    log_info "Warning: No Internal Squads available via API fallback"
    INTERNAL_SQUADS_JSON='[]'
  fi
{{ END }}

{{ IF us.service.settings.squads && us.service.settings.squads.size > 0 || server.settings.remnawave_squads && server.settings.remnawave_squads.size > 0 }}
INTERNAL_SQUADS_JSON='{{ INTERNAL_SQUADS_JSON }}'
{{ END }}
log_debug "Using Internal Squads: $INTERNAL_SQUADS_JSON"

# Определение External Squad (опционально, один UUID)
# Приоритет: услуга → глобальная конфигурация → не используется
{{ IF us.service.settings.external_squad }}
  {{ EXTERNAL_SQUAD = us.service.settings.external_squad }}
{{ ELSIF server.settings.remnawave_external_squad }}
  {{ EXTERNAL_SQUAD = server.settings.remnawave_external_squad }}
{{ ELSE }}
  {{ EXTERNAL_SQUAD = '' }}
{{ END }}
{{ IF EXTERNAL_SQUAD }}
EXTERNAL_SQUAD_UUID="{{ EXTERNAL_SQUAD }}"
log_debug "Using External Squad: $EXTERNAL_SQUAD_UUID"
{{ ELSE }}
EXTERNAL_SQUAD_UUID=""
log_debug "No External Squad configured"
{{ END }}

# Получение UUID пользователя из хранилища
# Предполагается, что эта команда возвращает JSON с полем "uuid"
# или что переменная uuid устанавливается другим способом до выполнения скрипта
{{ IF event_name != 'CREATE' }}
{{ uuid = storage.read('name', STORAGE_PREFIX _ us.id).response.uuid }}
{{ END }}

# Получение chat_id из настроек пользователя
 {{ chat_id = user.settings.telegram.chat_id }}

# Использование модуля date для форматирования даты истечения
 {{ USE date }}
 {{ expire = date.format(us.expire, '%s') + 1260 }}
 {{ new_expire = date.format(expire, '%Y-%m-%dT%H:%M:%S.000Z') }}
# Для тестирования (установите актуальную дату в формате ISO 8601):
# new_expire=$(date -u -d "+21 minutes" +"%Y-%m-%dT%H:%M:%SZ") # Пример: текущее время + 21 минута

log_info "EVENT: $EVENT"
log_debug "USER_ID (us.id): {{ us.id }}" # Для отладки
log_debug "USER_UUID (uuid): $uuid" # Для отладки
log_debug "NEW_EXPIRE_DATE: {{ new_expire }}" # Для отладки
log_debug "DATA_LIMIT: {{ data_limit }} bytes ({{ data_limit / 1073741824 FILTER format("%.2f") }} GB)" # Для отладки
log_debug "RESET_STRATEGY: {{ reset_strategy }}" # Для отладки
log_debug "HWID_LIMIT: {{ HWID_LIMIT }}" # Для отладки

# Функция для обновления конфигов пользователя
update_user_configs() {
  local user_response="$1"
  local user_short_uuid=$(echo "$user_response" | jq -r '.response.shortUuid')
  
  if [ "$user_short_uuid" != "null" ] && [ -n "$user_short_uuid" ]; then
    log_debug "Updating user configs for shortUuid: $user_short_uuid"
    
    # Получаем raw конфигурацию с параметром withDisabledHosts=true для API v2.1.7+
    RAW_CONFIG_RESPONSE=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/sub/$user_short_uuid/raw?withDisabledHosts=true" \
      -H "Authorization: Bearer $TOKEN")
    
    log_debug "Raw config API response: $RAW_CONFIG_RESPONSE"
    
    # Получаем готовую подписку (base64 конфигурация) из API v2.1.7+
    log_debug "Getting subscription configuration..."
    SUBSCRIPTION_CONFIG=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/sub/$user_short_uuid" 2>/dev/null || echo "")
    
    log_debug "Subscription config length: ${#SUBSCRIPTION_CONFIG}"
    
    # Проверяем, что ответ содержит валидные данные и rawHosts не пустой
    RAW_HOSTS_COUNT=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts | length // 0' 2>/dev/null || echo "0")
    if [ "$RAW_HOSTS_COUNT" = "0" ] || [ "$RAW_HOSTS_COUNT" = "null" ]; then
      log_debug "Warning: rawHosts is null or empty (count: $RAW_HOSTS_COUNT). Trying without withDisabledHosts parameter..."
      RAW_CONFIG_RESPONSE=$(curl -sk -XGET \
        "$REMNAWAVE_HOST/api/sub/$user_short_uuid/raw" \
        -H "Authorization: Bearer $TOKEN")
      log_debug "Fallback raw config response: $RAW_CONFIG_RESPONSE"
      RAW_HOSTS_COUNT=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts | length // 0' 2>/dev/null || echo "0")
    fi
    
    # Создаем объект с готовой подпиской и отдельными конфигами
    if [ -n "$SUBSCRIPTION_CONFIG" ] && [ ${#SUBSCRIPTION_CONFIG} -gt 50 ]; then
      log_debug "Using ready subscription config from API"
      # Декодируем base64 подписку для получения отдельных конфигов
      DECODED_CONFIGS=$(echo "$SUBSCRIPTION_CONFIG" | base64 -d 2>/dev/null || echo "$SUBSCRIPTION_CONFIG")
      
      # Парсим отдельные конфиги из подписки
      INDIVIDUAL_CONFIGS='[]'
      if echo "$DECODED_CONFIGS" | grep -q "vless://\|ss://\|trojan://"; then
        # Разбиваем конфиги по строкам и создаем JSON массив
        INDIVIDUAL_CONFIGS=$(echo "$DECODED_CONFIGS" | grep -E "^(vless://|ss://|trojan://)" | \
          jq -R -s 'split("\n") | map(select(length > 0)) | map({name: (split("#")[1] // "Unknown"), protocol: (split("://")[0] // "unknown"), config: .})')
      fi
      
      ALL_CONFIGS="$INDIVIDUAL_CONFIGS"
      log_debug "Generated configs from subscription: $(echo "$ALL_CONFIGS" | jq length)"
    else
      # Fallback: генерируем конфиги из rawHosts как раньше
      log_debug "Generating configs from rawHosts... (count: $RAW_HOSTS_COUNT)"
      if [ "$RAW_HOSTS_COUNT" != "0" ] && [ "$RAW_HOSTS_COUNT" != "null" ]; then
        VLESS_CONFIGS=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts[]? | select(.protocol == "vless") | {name: .remark, protocol: .protocol, config: ("vless://" + .password.vlessPassword + "@" + .address + ":" + (.port|tostring) + "?encryption=none&flow=" + (.flow // "") + "&security=" + .tls + "&sni=" + .sni + "&fp=" + (.fingerprint // "") + "&pbk=" + .publicKey + "&type=" + .network + "&headerType=none#" + (.remark | @uri))}' | jq -s .)
        
        # Генерируем Shadowsocks конфиги с проверкой на количество хостов
        SS_CONFIGS=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts[]? | select(.protocol == "shadowsocks") | {name: .remark, protocol: .protocol, config: ("ss://" + (.protocolOptions.ss.method + ":" + .password.ssPassword | @base64) + "@" + .address + ":" + (.port|tostring) + "#" + (.remark | @uri))}' | jq -s .)
        
        # Объединяем все конфиги
        ALL_CONFIGS=$(echo "$VLESS_CONFIGS $SS_CONFIGS" | jq -s 'add')
      else
        log_debug "No rawHosts available, setting empty configs"
        ALL_CONFIGS='[]'
      fi
    fi
    
    # Создаем обновленные данные с готовой подпиской
    EXTENDED_USER_DATA=$(echo "$user_response" | jq --argjson configs "$ALL_CONFIGS" \
      --argjson raw_config "$RAW_CONFIG_RESPONSE" \
      --arg subscription_config "$SUBSCRIPTION_CONFIG" \
      --arg subscription_url "$(echo "$user_response" | jq -r '.response.subscriptionUrl // ""')" \
      '.configs = $configs | .raw_config = $raw_config | .subscription_config = $subscription_config | .subscription_url = $subscription_url')
    
    # Обновляем SHM storage
    SHM_RESPONSE=$(curl -sk -XPOST \
      -H "session-id: $SESSION_ID" \
      -H "Content-Type: application/json" \
      "$API_URL/shm/v1/storage/manage/{{ STORAGE_PREFIX }}{{ us.id }}" \
      --data-binary "$EXTENDED_USER_DATA")
    
    log_debug "Configs updated in SHM storage"
  else
    # Fallback: обновляем без конфигов
    SHM_RESPONSE=$(curl -sk -XPOST \
      -H "session-id: $SESSION_ID" \
      -H "Content-Type: application/json" \
      "$API_URL/shm/v1/storage/manage/{{ STORAGE_PREFIX }}{{ us.id }}" \
      --data-binary "$user_response")
    
    log_debug "Updated SHM storage without configs (shortUuid not available)"
  fi
}

# Основная логика скрипта на основе события
case $EVENT in

  CREATE)
    log_info "Create user"
    # Описание пользователя для Remnawave
    DESCR="SHM_info- {{ user.login }}, {{ user.full_name }}, https://t.me/{{ user.settings.telegram.login }}, US_ID: {{ user.id }}"
    USER_TAG="SHM"

    log_debug "Using SERVICE hwid_limit: {{ HWID_LIMIT }}"
    
    # Динамическое определение Internal Squads для создания пользователя
    if [ "$INTERNAL_SQUADS_JSON" = "[]" ]; then
      log_info "Warning: No Internal Squads configured - user will be created without squads"
      ACTIVE_SQUADS="[]"
    else
      ACTIVE_SQUADS="$INTERNAL_SQUADS_JSON"
    fi
    log_debug "Creating user with squads: $ACTIVE_SQUADS"
    
    # Тело запроса для создания пользователя (соответствует CreateUserRequestDto v2.2.6)
    # В новом API activeUserInbounds заменено на activeInternalSquads
    # Поле activeInternalSquads ожидает массив UUID Internal Squads
    # Поле externalSquadUuid - опциональный UUID External Squad
    PAYLOAD_CREATE=$(cat <<EOF
{
  "username": "{{ NAME_PREFIX }}{{ us.id }}",
  "status": "ACTIVE",
  "trafficLimitStrategy": "{{ reset_strategy }}",
  "trafficLimitBytes": {{ data_limit }},
  "expireAt": "{{ new_expire }}",
  "hwidDeviceLimit": {{ HWID_LIMIT }},
  "description": "$DESCR",
  {{ IF chat_id }}"telegramId": {{ chat_id }},{{ END }}
  "tag": "$USER_TAG",
  "activeInternalSquads": $ACTIVE_SQUADS{{ IF EXTERNAL_SQUAD }},
  "externalSquadUuid": "{{ EXTERNAL_SQUAD }}"{{ END }}
}
EOF
    )

    log_debug "Create User Payload: $PAYLOAD_CREATE"

    # Вызов API для создания пользователя
    USER_CFG=$(curl -sk -XPOST \
      "$REMNAWAVE_HOST/api/users" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "$PAYLOAD_CREATE")

    log_debug "Create User Response: $USER_CFG"

    # Проверка успешности создания пользователя (проверяем наличие username в ответе)
    # В CreateUserResponseDto есть response.username
    if [ -z "$(echo "$USER_CFG" | jq -r '.response.username')" ] || [ "$(echo "$USER_CFG" | jq -r '.response.username')" = "null" ]; then
      log_info "Error creating user: $USER_CFG"
      exit 1
    fi

    # Получаем uuid созданного пользователя из ответа для дальнейшего использования, если это необходимо
    created_user_uuid=$(echo "$USER_CFG" | jq -r '.response.uuid')
    log_debug "Created User UUID: $created_user_uuid"

    log_info "User created successfully: $(echo "$USER_CFG" | jq .response.username)"

    # Получаем shortUuid созданного пользователя для получения конфигов
    created_user_short_uuid=$(echo "$USER_CFG" | jq -r '.response.shortUuid')
    log_debug "Created User Short UUID: $created_user_short_uuid"

    # Получаем raw конфигурацию пользователя с подключениями
    log_debug "Getting user raw configuration..."
    RAW_CONFIG_RESPONSE=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/sub/$created_user_short_uuid/raw?withDisabledHosts=true" \
      -H "Authorization: Bearer $TOKEN")

    log_debug "Raw config response: $RAW_CONFIG_RESPONSE"
    
    # Получаем готовую подписку (base64 конфигурация) из API v2.1.7+
    log_debug "Getting subscription configuration..."
    SUBSCRIPTION_CONFIG=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/sub/$created_user_short_uuid" 2>/dev/null || echo "")
    
    log_debug "Subscription config length: ${#SUBSCRIPTION_CONFIG}"
    
    # Проверяем, что ответ содержит валидные данные и rawHosts не пустой
    RAW_HOSTS_COUNT=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts | length // 0' 2>/dev/null || echo "0")
    if [ "$RAW_HOSTS_COUNT" = "0" ] || [ "$RAW_HOSTS_COUNT" = "null" ]; then
      log_debug "Warning: rawHosts is null or empty (count: $RAW_HOSTS_COUNT). Trying without withDisabledHosts parameter..."
      RAW_CONFIG_RESPONSE=$(curl -sk -XGET \
        "$REMNAWAVE_HOST/api/sub/$created_user_short_uuid/raw" \
        -H "Authorization: Bearer $TOKEN")
      log_debug "Fallback raw config response: $RAW_CONFIG_RESPONSE"
      RAW_HOSTS_COUNT=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts | length // 0' 2>/dev/null || echo "0")
    fi

    # Создаем объект с готовой подпиской и отдельными конфигами
    if [ -n "$SUBSCRIPTION_CONFIG" ] && [ ${#SUBSCRIPTION_CONFIG} -gt 50 ]; then
      log_debug "Using ready subscription config from API"
      # Декодируем base64 подписку для получения отдельных конфигов
      DECODED_CONFIGS=$(echo "$SUBSCRIPTION_CONFIG" | base64 -d 2>/dev/null || echo "$SUBSCRIPTION_CONFIG")
      
      # Парсим отдельные конфиги из подписки
      INDIVIDUAL_CONFIGS='[]'
      if echo "$DECODED_CONFIGS" | grep -q "vless://\|ss://\|trojan://"; then
        # Разбиваем конфиги по строкам и создаем JSON массив
        INDIVIDUAL_CONFIGS=$(echo "$DECODED_CONFIGS" | grep -E "^(vless://|ss://|trojan://)" | \
          jq -R -s 'split("\n") | map(select(length > 0)) | map({name: (split("#")[1] // "Unknown"), protocol: (split("://")[0] // "unknown"), config: .})')
      fi
      
      ALL_CONFIGS="$INDIVIDUAL_CONFIGS"
      log_debug "Generated configs from subscription: $(echo "$ALL_CONFIGS" | jq length)"
    else
      # Fallback: генерируем конфиги из rawHosts как раньше
      log_debug "Generating VLESS configs array... (rawHosts count: $RAW_HOSTS_COUNT)"
      if [ "$RAW_HOSTS_COUNT" != "0" ] && [ "$RAW_HOSTS_COUNT" != "null" ]; then
        VLESS_CONFIGS=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts[]? | select(.protocol == "vless") | {name: .remark, protocol: .protocol, config: ("vless://" + .password.vlessPassword + "@" + .address + ":" + (.port|tostring) + "?encryption=none&flow=" + (.flow // "") + "&security=" + .tls + "&sni=" + .sni + "&fp=" + (.fingerprint // "") + "&pbk=" + .publicKey + "&type=" + .network + "&headerType=none#" + (.remark | @uri))}' | jq -s .)

        # Генерируем массив Shadowsocks конфигов с проверкой на количество хостов
        log_debug "Generating Shadowsocks configs array..."
        SS_CONFIGS=$(echo "$RAW_CONFIG_RESPONSE" | jq -r '.response.rawHosts[]? | select(.protocol == "shadowsocks") | {name: .remark, protocol: .protocol, config: ("ss://" + (.protocolOptions.ss.method + ":" + .password.ssPassword | @base64) + "@" + .address + ":" + (.port|tostring) + "#" + (.remark | @uri))}' | jq -s .)
        
        # Объединяем все конфиги
        ALL_CONFIGS=$(echo "$VLESS_CONFIGS $SS_CONFIGS" | jq -s 'add')
      else
        log_debug "No rawHosts available, setting empty configs"
        ALL_CONFIGS='[]'
      fi
    fi

    log_debug "Generated configs count: $(echo "$ALL_CONFIGS" | jq length)"
    log_debug "Generated configs: $ALL_CONFIGS"

    # Создаем расширенный JSON с пользователем, конфигами и готовой подпиской
    EXTENDED_USER_DATA=$(echo "$USER_CFG" | jq --argjson configs "$ALL_CONFIGS" \
      --argjson raw_config "$RAW_CONFIG_RESPONSE" \
      --arg subscription_config "$SUBSCRIPTION_CONFIG" \
      --arg subscription_url "$(echo "$USER_CFG" | jq -r '.response.subscriptionUrl // ""')" \
      '.configs = $configs | .raw_config = $raw_config | .subscription_config = $subscription_config | .subscription_url = $subscription_url')

    log_debug "Extended user data created"

    log_debug "Upload extended user config to SHM with configs array"
    # Загрузка расширенной конфигурации пользователя в SHM storage
    SHM_CREATE_RESPONSE=$(curl -sk -XPUT \
      -H "session-id: $SESSION_ID" \
      -H "Content-Type: application/json" \
      "$API_URL/shm/v1/storage/manage/{{ STORAGE_PREFIX }}{{ us.id }}" \
      --data-binary "$EXTENDED_USER_DATA")

    log_debug "SHM create response: $SHM_CREATE_RESPONSE"

    log_info "done (CREATE)"
    ;;

  ACTIVATE)
    log_info "Activate user"
    log_debug "Activating user with UUID: {{ uuid }}"

    log_debug "=== ACTIVATE SETTINGS ==="
    log_debug "Current service data_limit: {{ data_limit }} bytes ({{ data_limit / 1073741824 FILTER format("%.2f") }} GB)"
    log_debug "Current service reset_strategy: {{ reset_strategy }}"
    log_debug "Current service hwid_limit: {{ HWID_LIMIT }}"
    log_debug "========================="

    # 1. Получение текущей информации о пользователе
    GET_USER_RESPONSE=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/users/{{ uuid }}" \
      -H "Authorization: Bearer $TOKEN")

    log_debug "Get User Response (ACTIVATE): $GET_USER_RESPONSE"
    CURRENT_USER_STATUS=$(echo "$GET_USER_RESPONSE" | jq -r '.response.status')

    log_debug "=== CURRENT REMNAWAVE SETTINGS ==="
    log_debug "Status: $CURRENT_USER_STATUS"
    log_debug "================================="

    # 2. Активация пользователя (только если он не активен)
    if [ "$CURRENT_USER_STATUS" != "ACTIVE" ]; then
      log_debug "User status is $CURRENT_USER_STATUS. Attempting to enable..."
      ACTIVE_USER_RESPONSE=$(curl -sk -XPOST \
        "$REMNAWAVE_HOST/api/users/{{ uuid }}/actions/enable" \
        -H "Authorization: Bearer $TOKEN")

      log_debug "Enable User Response: $ACTIVE_USER_RESPONSE"

      # Проверка статуса пользователя после активации
      if [ "$(echo "$ACTIVE_USER_RESPONSE" | jq -r '.response.status')" != "ACTIVE" ]; then
        log_info "Error enabling user: $ACTIVE_USER_RESPONSE"
        exit 1
      fi
      log_debug "User enabled successfully."
    else
      log_debug "User is already active. Skipping activation."
    fi

    # 3. Проверка необходимости обновления и PATCH запрос
    log_debug "Checking if user settings need update..."
    
    # Проверяем текущие настройки
    CURRENT_TRAFFIC_LIMIT=$(echo "$GET_USER_RESPONSE" | jq -r '.response.trafficLimitBytes')
    CURRENT_RESET_STRATEGY=$(echo "$GET_USER_RESPONSE" | jq -r '.response.trafficLimitStrategy')
    CURRENT_HWID_LIMIT=$(echo "$GET_USER_RESPONSE" | jq -r '.response.hwidDeviceLimit')
    CURRENT_EXPIRE=$(echo "$GET_USER_RESPONSE" | jq -r '.response.expireAt')
    
    # Проверяем Internal Squads
    CURRENT_SQUADS=$(echo "$GET_USER_RESPONSE" | jq -c '.response.activeInternalSquads[].uuid' 2>/dev/null || echo "[]")
    EXPECTED_SQUADS=$(echo "$INTERNAL_SQUADS_JSON" | jq -c '.' 2>/dev/null || echo "[]")
    
    # Определяем, нужно ли обновление
    NEEDS_UPDATE=false
    UPDATE_PAYLOAD="{\"uuid\": \"{{ uuid }}\","
    
    if [ "$CURRENT_TRAFFIC_LIMIT" != "{{ data_limit }}" ]; then
      log_debug "Traffic limit needs update: $CURRENT_TRAFFIC_LIMIT -> {{ data_limit }}"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"trafficLimitBytes\": {{ data_limit }},"
      NEEDS_UPDATE=true
    fi
    
    if [ "$CURRENT_RESET_STRATEGY" != "{{ reset_strategy }}" ]; then
      log_debug "Reset strategy needs update: $CURRENT_RESET_STRATEGY -> {{ reset_strategy }}"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"trafficLimitStrategy\": \"{{ reset_strategy }}\","
      NEEDS_UPDATE=true
    fi
    
    if [ "$CURRENT_HWID_LIMIT" != "{{ HWID_LIMIT }}" ]; then
      log_debug "HWID limit needs update: $CURRENT_HWID_LIMIT -> {{ HWID_LIMIT }}"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"hwidDeviceLimit\": {{ HWID_LIMIT }},"
      NEEDS_UPDATE=true
    fi
    
    if [ "$CURRENT_SQUADS" != "$EXPECTED_SQUADS" ] && [ "$INTERNAL_SQUADS_JSON" != "[]" ]; then
      log_debug "Internal squads need update"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"activeInternalSquads\": $INTERNAL_SQUADS_JSON,"
      NEEDS_UPDATE=true
    fi
    
    # Проверяем External Squad (опционально)
    CURRENT_EXTERNAL_SQUAD=$(echo "$GET_USER_RESPONSE" | jq -r '.response.externalSquadUuid // ""')
    if [ -n "$EXTERNAL_SQUAD_UUID" ] && [ "$CURRENT_EXTERNAL_SQUAD" != "$EXTERNAL_SQUAD_UUID" ]; then
      log_debug "External squad needs update: $CURRENT_EXTERNAL_SQUAD -> $EXTERNAL_SQUAD_UUID"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"externalSquadUuid\": \"$EXTERNAL_SQUAD_UUID\","
      NEEDS_UPDATE=true
    fi
    
    # Всегда устанавливаем статус ACTIVE и expireAt
    UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"status\": \"ACTIVE\",\"expireAt\": \"{{ new_expire }}\"}"
    
    # PATCH выполняется ВСЕГДА - как минимум для обновления expireAt и статуса
    if [ "$NEEDS_UPDATE" = true ]; then
      log_debug "Updating user settings with PATCH (settings changed)..."
    else
      log_debug "Updating user with PATCH (only expireAt and status)..."
    fi
    
    log_debug "Update Payload: $UPDATE_PAYLOAD"
    
    UPDATE_USER_RESPONSE=$(curl -sk -XPATCH \
      "$REMNAWAVE_HOST/api/users" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "$UPDATE_PAYLOAD")

    log_info "UPDATE_PAYLOAD: $UPDATE_PAYLOAD"

    log_debug "Update User Response (ACTIVATE): $UPDATE_USER_RESPONSE"
    
    # Проверка успешности обновления
    if [ "$(echo "$UPDATE_USER_RESPONSE" | jq -r '.response.status // empty')" != "ACTIVE" ]; then
      log_info "Error updating user: $UPDATE_USER_RESPONSE"
      exit 1
    fi
    
    if [ "$NEEDS_UPDATE" = true ]; then
      log_info "✅ User settings updated successfully"
    else
      log_info "✅ User expiration and status updated"
    fi

    # 4. Обновление данных в SHM storage с конфигами
    # Используем данные из PATCH ответа (он выполняется всегда)
    log_debug "Updating user config in SHM with configs..."
    
    # PATCH всегда выполняется, поэтому используем его ответ
    FINAL_USER_DATA="$UPDATE_USER_RESPONSE"
    log_debug "Using PATCH response for SHM update"

    # Используем функцию обновления конфигов с уже полученными данными
    update_user_configs "$FINAL_USER_DATA"

    log_info "=== ACTIVATE SUMMARY ==="
    log_info "✅ User status: ACTIVE"
    log_info "✅ Settings synchronized"
    log_info "✅ Storage updated"
    log_info "========================="

    log_info "done (ACTIVATE)"
    ;;

  BLOCK)
    log_info "Block user"
    log_debug "Blocking user with UUID: {{ uuid }}"

    # 1. Сначала получаем текущие данные пользователя (для сохранения конфигов)
    # Это нужно сделать ДО блокировки, чтобы избежать таймаутов в SHM
    log_debug "Getting user data before blocking..."
    USER_DATA_BEFORE_BLOCK=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/users/{{ uuid }}" \
      -H "Authorization: Bearer $TOKEN")
    log_debug "User data before block: $USER_DATA_BEFORE_BLOCK"

    # 2. Вызов API для блокировки пользователя
    # Новый API: POST /api/users/{uuid}/actions/disable (без тела запроса)
    DISABLE_USER_RESPONSE=$(curl -sk -XPOST \
      "$REMNAWAVE_HOST/api/users/{{ uuid }}/actions/disable" \
      -H "Authorization: Bearer $TOKEN")

    log_debug "Disable User Response: $DISABLE_USER_RESPONSE"

    # Проверка статуса пользователя после блокировки
    # DisableUserResponseDto содержит response.status (ожидаем "DISABLED")
    if [ "$(echo "$DISABLE_USER_RESPONSE" | jq -r '.response.status')" != "DISABLED" ]; then
      log_info "Error disabling user: $DISABLE_USER_RESPONSE"
      exit 1
    fi
    log_debug "User disabled successfully."

    # 3. Обновляем SHM storage используя ответ от disable (без лишних GET/update_user_configs)
    # Ответ от disable уже содержит актуальные данные пользователя со статусом DISABLED
    # Избегаем вызова update_user_configs(), который делает лишние запросы к /api/sub/
    log_debug "Updating SHM storage with disabled user data (without fetching configs)..."
    
    # Сохраняем данные пользователя в SHM - конфиги остаются прежними из storage
    SHM_RESPONSE=$(curl -sk -XPOST \
      -H "session-id: $SESSION_ID" \
      -H "Content-Type: application/json" \
      "$API_URL/shm/v1/storage/manage/{{ STORAGE_PREFIX }}{{ us.id }}" \
      --data-binary "$DISABLE_USER_RESPONSE")
    
    log_debug "SHM update response: $SHM_RESPONSE"

    log_info "done (BLOCK)"
    ;;

  REMOVE)
    log_info "Remove user"
    log_debug "Removing user with UUID: {{ uuid }}"

    # Вызов API для удаления пользователя
    # Новый API: DELETE /api/users/{uuid}
    REMOVE_USER_RESPONSE=$(curl -sk -XDELETE \
      "$REMNAWAVE_HOST/api/users/{{ uuid }}" \
      -H "Authorization: Bearer $TOKEN")

    log_debug "Remove User Response: $REMOVE_USER_RESPONSE"

    # Проверка успешности удаления
    # DeleteUserResponseDto содержит response.isDeleted (ожидаем true)
    if [ "$(echo "$REMOVE_USER_RESPONSE" | jq -r '.response.isDeleted')" != "true" ]; then
      log_info "Error removing user: $REMOVE_USER_RESPONSE"
      exit 1
    fi
    log_debug "User removed from Remnawave successfully."

    log_debug "Remove user key from SHM"
    # Удаление конфигурации пользователя из внутреннего хранилища (SHM)
    # Этот вызов остается без изменений
    curl -sk -XDELETE \
      -H "session-id: $SESSION_ID" \
      "$API_URL/shm/v1/storage/manage/{{ STORAGE_PREFIX }}{{ us.id }}"

    log_info "done (REMOVE)"
    ;;

  PROLONGATE)
    log_info "Prolongate user subscription"
    log_debug "User UUID: {{ uuid }}"

    log_debug "=== PROLONGATE SETTINGS ==="
    log_debug "Current service data_limit: {{ data_limit }} bytes ({{ data_limit / 1073741824 FILTER format("%.2f") }} GB)"
    log_debug "Current service reset_strategy: {{ reset_strategy }}"
    log_debug "Current service hwid_limit: {{ HWID_LIMIT }}"
    log_debug "========================="

    # 1. Получение текущей информации о пользователе
    GET_USER_RESPONSE=$(curl -sk -XGET \
      "$REMNAWAVE_HOST/api/users/{{ uuid }}" \
      -H "Authorization: Bearer $TOKEN")

    log_debug "Get User Response (PROLONGATE): $GET_USER_RESPONSE"
    CURRENT_USER_STATUS=$(echo "$GET_USER_RESPONSE" | jq -r '.response.status')

    log_debug "=== CURRENT REMNAWAVE SETTINGS ==="
    log_debug "Status: $CURRENT_USER_STATUS"
    log_debug "================================="

    # 2. Активация пользователя, если он не активен
    if [ "$CURRENT_USER_STATUS" != "ACTIVE" ]; then
      log_debug "User status is $CURRENT_USER_STATUS. Attempting to enable..."
      ENABLE_USER_RESPONSE_PROLONGATE=$(curl -sk -XPOST \
        "$REMNAWAVE_HOST/api/users/{{ uuid }}/actions/enable" \
        -H "Authorization: Bearer $TOKEN")
      log_debug "Enable User Response (PROLONGATE): $ENABLE_USER_RESPONSE_PROLONGATE"
      if [ "$(echo "$ENABLE_USER_RESPONSE_PROLONGATE" | jq -r '.response.status')" != "ACTIVE" ]; then
        log_info "Error enabling user during prolongation: $ENABLE_USER_RESPONSE_PROLONGATE"
      else
        log_debug "User enabled successfully during prolongation."
      fi
    fi

    # 3. Сброс трафика пользователя
    log_debug "Resetting user traffic..."
    RESET_TRAFFIC_RESPONSE=$(curl -sk -XPOST \
      "$REMNAWAVE_HOST/api/users/{{ uuid }}/actions/reset-traffic" \
      -H "Authorization: Bearer $TOKEN")

    log_debug "Reset Traffic Response: $RESET_TRAFFIC_RESPONSE"
    if [ "$(echo "$RESET_TRAFFIC_RESPONSE" | jq -r '.response.status')" != "ACTIVE" ]; then
      log_info "Warning: Traffic reset might have failed. Response: $RESET_TRAFFIC_RESPONSE"
    else
      log_debug "User traffic reset successfully."
    fi

    # 4. Проверка и обновление настроек с помощью PATCH
    log_debug "Checking and updating user settings..."
    
    # Проверяем текущие настройки
    CURRENT_TRAFFIC_LIMIT=$(echo "$GET_USER_RESPONSE" | jq -r '.response.trafficLimitBytes')
    CURRENT_RESET_STRATEGY=$(echo "$GET_USER_RESPONSE" | jq -r '.response.trafficLimitStrategy')
    CURRENT_HWID_LIMIT=$(echo "$GET_USER_RESPONSE" | jq -r '.response.hwidDeviceLimit')
    
    # Проверяем Internal Squads
    CURRENT_SQUADS=$(echo "$GET_USER_RESPONSE" | jq -c '.response.activeInternalSquads[].uuid' 2>/dev/null || echo "[]")
    EXPECTED_SQUADS=$(echo "$INTERNAL_SQUADS_JSON" | jq -c '.' 2>/dev/null || echo "[]")
    
    # Определяем, что нужно обновить
    SETTINGS_CHANGED=false
    UPDATE_PAYLOAD="{\"uuid\": \"{{ uuid }}\","
    UPDATE_FIELDS=""
    
    # Проверка лимита трафика
    if [ "$CURRENT_TRAFFIC_LIMIT" != "{{ data_limit }}" ]; then
      log_debug "Traffic limit changed: $CURRENT_TRAFFIC_LIMIT -> {{ data_limit }}"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"trafficLimitBytes\": {{ data_limit }},"
      UPDATE_FIELDS="$UPDATE_FIELDS, trafficLimitBytes"
      SETTINGS_CHANGED=true
    fi

    # Проверка стратегии сброса
    if [ "$CURRENT_RESET_STRATEGY" != "{{ reset_strategy }}" ]; then
      log_debug "Reset strategy changed: $CURRENT_RESET_STRATEGY -> {{ reset_strategy }}"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"trafficLimitStrategy\": \"{{ reset_strategy }}\","
      UPDATE_FIELDS="$UPDATE_FIELDS, trafficLimitStrategy"
      SETTINGS_CHANGED=true
    fi

    # Проверка HWID лимита
    CURRENT_HWID_NUMERIC=$(echo "$CURRENT_HWID_LIMIT" | sed 's/null/0/')
    if [ "$CURRENT_HWID_NUMERIC" != "{{ HWID_LIMIT }}" ]; then
      log_debug "HWID limit changed: $CURRENT_HWID_LIMIT -> {{ HWID_LIMIT }}"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"hwidDeviceLimit\": {{ HWID_LIMIT }},"
      UPDATE_FIELDS="$UPDATE_FIELDS, hwidDeviceLimit"
      SETTINGS_CHANGED=true
    fi
    
    # Проверка Internal Squads
    if [ "$CURRENT_SQUADS" != "$EXPECTED_SQUADS" ] && [ "$INTERNAL_SQUADS_JSON" != "[]" ]; then
      log_debug "Internal squads changed!"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"activeInternalSquads\": $INTERNAL_SQUADS_JSON,"
      UPDATE_FIELDS="$UPDATE_FIELDS, activeInternalSquads"
      SETTINGS_CHANGED=true
    fi
    
    # Проверка External Squad (опционально)
    CURRENT_EXTERNAL_SQUAD=$(echo "$GET_USER_RESPONSE" | jq -r '.response.externalSquadUuid // ""')
    if [ -n "$EXTERNAL_SQUAD_UUID" ] && [ "$CURRENT_EXTERNAL_SQUAD" != "$EXTERNAL_SQUAD_UUID" ]; then
      log_debug "External squad changed: $CURRENT_EXTERNAL_SQUAD -> $EXTERNAL_SQUAD_UUID"
      UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"externalSquadUuid\": \"$EXTERNAL_SQUAD_UUID\","
      UPDATE_FIELDS="$UPDATE_FIELDS, externalSquad"
      SETTINGS_CHANGED=true
    fi

    # Всегда обновляем дату истечения и статус
    UPDATE_PAYLOAD="$UPDATE_PAYLOAD\"expireAt\": \"{{ new_expire }}\", \"status\": \"ACTIVE\"}"

    if [ "$SETTINGS_CHANGED" = true ]; then
      log_info "Service settings changed. Updating user with new settings..."
      log_debug "Updated fields: $UPDATE_FIELDS"
    else
      log_info "Service settings unchanged. Updating only expiration date..."
    fi

    log_debug "Update User Payload (PROLONGATE): $UPDATE_PAYLOAD"

    UPDATE_USER_RESPONSE_PROLONGATE=$(curl -sk -XPATCH \
      "$REMNAWAVE_HOST/api/users" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "$UPDATE_PAYLOAD")

    log_debug "Update User Response (PROLONGATE): $UPDATE_USER_RESPONSE_PROLONGATE"

    # Проверка успешности обновления
    if [ "$(echo "$UPDATE_USER_RESPONSE_PROLONGATE" | jq -r '.response.status')" != "ACTIVE" ]; then
      log_info "Error updating user during prolongation: $UPDATE_USER_RESPONSE_PROLONGATE"
      exit 1
    fi

    # 5. Обновление данных в SHM storage с конфигами
    # Используем ответ от PATCH вместо лишнего GET запроса
    log_debug "Updating user config in SHM with configs..."
    
    # PATCH ответ уже содержит актуальные данные пользователя
    if [ -n "$UPDATE_USER_RESPONSE_PROLONGATE" ]; then
      FINAL_USER_DATA="$UPDATE_USER_RESPONSE_PROLONGATE"
      log_debug "Using PATCH response for SHM update"
    else
      # Fallback на начальный GET если PATCH не выполнился
      FINAL_USER_DATA="$GET_USER_RESPONSE"
      log_debug "Using initial GET response for SHM update"
    fi

    # Используем функцию обновления конфигов с уже полученными данными
    update_user_configs "$FINAL_USER_DATA"

    log_info "=== PROLONGATE SUMMARY ==="
    log_info "✅ User status: ACTIVE"
    log_info "✅ Traffic reset: completed"
    log_info "✅ Expiration updated: $new_expire"
    if [ "$SETTINGS_CHANGED" = true ]; then
      log_info "✅ Service settings synchronized"
    fi
    log_info "✅ Storage updated"
    log_info "========================="

    log_info "done (PROLONGATE)"
    ;;

  *)
    echo "Unknown event: $EVENT. Exit."
    exit 0
    ;;
esac

exit 0