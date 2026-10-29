-- 191 (bot_configs の NO FORCE ROW LEVEL SECURITY) を戻し、tenant をまたぐ webhook の bot 引き当ての関数を消す
--
-- 191 は、102 の SECURITY DEFINER 関数 `lookup_bot_config_for_webhook(bot_id)` (tenant が決まる前の LINE WORKS の webhook が
-- bot_id から tenant と bot_secret を引く) が FORCE の下で 0 行になるのを直すため、表の所有者に RLS を掛けないようにした。
-- その後 LINE WORKS の callback URL を tenant 付きの識別子 (auth-worker の `/lineworks/hook/{識別子}`) に切り替え、
-- alc-notify-worker は tenant の transaction の中で RLS のまま bot を引くようになった (ippoan/auth-worker#715・
-- ippoan/alc-notify-worker#19)。この関数の呼び手は無くなったので消し、bot_configs を 049 の FORCE に戻す
-- (所有者として動く関数が tenant をまたいで bot_secret を読めないようにする)。
ALTER TABLE alc_api.bot_configs FORCE ROW LEVEL SECURITY;

DROP FUNCTION alc_api.lookup_bot_config_for_webhook(TEXT);
