{{
IF request.params.login AND request.params.format == 'json' AND request.params.secret == 'zRL33es2dB4Q';
  ret = ref(user.list_for_api('admin',1,'limit',0,'filter',{"login"=request.params.login}));
  IF (ret.size > 0);
    u = user.id(ret.first.user_id);

    servicesUser = ref(u.services.list_for_api('limit',0));
    servicesShort = [];
    FOR svc IN servicesUser;
      servicesShort.push({
        'expire'=svc.expire,
        'name'=svc.name,
        'next'=svc.next,
        'period'=svc.period,
        'cost'=svc.cost,
        'status'=svc.status,
        'user_service_id'=svc.user_service_id
      });
    END;

    paysRaw = ref(u.pays.list_for_api('limit',3));
    paysLast = [];
    cntLast = 0;
    FOR p IN paysRaw;
      payDesc = NULL;
      externalId = NULL;
      paymentType = NULL;
      IF p.comment AND p.comment.object;
        IF p.comment.object.description; payDesc = p.comment.object.description; END;
        IF p.comment.object.id; externalId = p.comment.object.id; END;
        IF p.comment.object.payment_method AND p.comment.object.payment_method.type;
          paymentType = p.comment.object.payment_method.type;
        END;
      END;
      cleanPay = {
        'id'=p.id,
        'date'=p.date,
        'money'=p.money,
        'pay_system_id'=p.pay_system_id,
        'description'=payDesc,
        'external_id'=externalId,
        'payment_type'=paymentType
      };
      IF cntLast < 3; paysLast.push(cleanPay); cntLast = cntLast + 1; END;
    END;

    remnaData = [];
    FOR svc IN servicesUser;
      svcStorage = u.storage.read('name', config.remna.storage_prefix _ svc.user_service_id);
      item = {
        'user_service_id'=svc.user_service_id,
        'service_name'=svc.name
      };
      IF svcStorage;
        subUrl = NULL;
        IF svcStorage.subscription_url; subUrl = svcStorage.subscription_url; END;
        IF svcStorage.subscriptionUrl; subUrl = svcStorage.subscriptionUrl; END;
        item.subscription_url = subUrl;
        shortUuid = svcStorage.shortUuid;
        IF shortUuid AND config.remna.url AND config.remna.api_token;
          HOST = config.remna.url;
          TOKEN = config.remna.api_token;
          headers = {'Authorization'="Bearer $TOKEN"};
          URL = HOST _ '/api/users/by-short-uuid/' _ shortUuid;
          result = http.get(URL,'headers',headers);
          item.http_status = result.status;
          item.used_traffic_bytes = result.response.usedTrafficBytes;
          item.traffic_limit_bytes = result.response.trafficLimitBytes;
          lastConn = NULL; lastServer = NULL;
          IF result.response.lastConnectedNode;
            lastConn = result.response.lastConnectedNode.connectedAt;
            lastServer = result.response.lastConnectedNode.nodeName;
          END;
          IF NOT lastConn AND result.response.onlineAt; lastConn = result.response.onlineAt; END;
          item.last_connection = lastConn;
          item.last_server = lastServer;
          item.user_agent = result.response.subLastUserAgent;
        END;
      END;
      remnaData.push(item);
    END;

    user_settings = {}; user_telegram = {};
    IF ret.first.settings;
      user_settings = ret.first.settings;
      IF ret.first.settings.telegram;
        user_telegram = {
          'chat_id'=ret.first.settings.telegram.chat_id,
          'first_name'=ret.first.settings.telegram.first_name,
          'last_name'=ret.first.settings.telegram.last_name,
          'login'=ret.first.settings.telegram.login
        };
      END;
    END;

    withdrawsRaw = ref(u.withdraws.list_for_api('limit',3));
    withdrawsShort = [];
    FOR w IN withdrawsRaw;
      withdrawsShort.push({
        'bonus'=w.bonus,
        'cost'=w.cost,
        'discount'=w.discount,
        'withdraw_date'=w.withdraw_date,
        'name'=w.name,
        'total'=w.total,
        'user_service_id'=w.user_service_id,
        'withdraw_id'=w.withdraw_id
      });
    END;

    response = toJson(
      'user'={
        'balance'=ret.first.balance,
        'block'=ret.first.block,
        'bonus'=ret.first.bonus,
        'comment'=ret.first.comment,
        'credit'=ret.first.credit,
        'discount'=ret.first.discount,
        'full_name'=ret.first.full_name,
        'login'=ret.first.login,
        'partner_id'=ret.first.partner_id,
        'user_id'=ret.first.user_id,
        'settings'=user_settings,
        'telegram'=user_telegram
      },
      'services'=servicesShort,
      'payments'={'last'=paysLast},
      'withdraws'=withdrawsShort,
      'remna'=remnaData
    );
    response;
  ELSE;
    toJson('response'='No data');
  END;
ELSE;
  toJson('response'='No data or bad secret');
END;
}}