-- 勤怠 (leave_*) の表が外部キーで指す親の行が、子と同じテナントに在ることを、書き込みのポリシー (WITH CHECK) でも確かめる。
-- 169 と同じ穴: 外部キーの検査は RLS を通らないので、子の tenant_id だけを見る WITH CHECK では、
-- 別のテナントの親の id を指す行を自分のテナントに書けた。アプリの書き方に頼らず、DB の側で塞ぐ。
-- Refs ohishi-exp/rust-leave-worker#1 / ippoan/rust-alc-api#747
--
-- 既存のポリシーを DROP POLICY → CREATE POLICY で作り直す (名前・USING は 163 のまま。WITH CHECK に条件を足すだけ)。
-- WITH CHECK は INSERT と UPDATE の新しい行にだけ効き、既存の行は変えない。
-- NULL を許す外部キーの列は、NULL なら通す (指す親が無い)。
-- 親を消したときの ON DELETE SET NULL は、親の側が所有者 / superuser として動かす参照アクションなので、この WITH CHECK には当たらない。
--
-- 対象:
--   leave_settings.lineworks_channel_id  → lineworks_channels (NULL 可)
--   leave_settings.notify_recipient_id   → notify_recipients (NULL 可。165)
--   leave_settings.notify_bot_config_id  → bot_configs (NULL 可。167)
--   leave_periods.page_id                → leave_pages (NOT NULL)

DROP POLICY leave_settings_tenant ON alc_api.leave_settings;
CREATE POLICY leave_settings_tenant ON alc_api.leave_settings
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND (leave_settings.lineworks_channel_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.lineworks_channels p
            WHERE p.id = leave_settings.lineworks_channel_id AND p.tenant_id = leave_settings.tenant_id
        ))
        AND (leave_settings.notify_recipient_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.notify_recipients p
            WHERE p.id = leave_settings.notify_recipient_id AND p.tenant_id = leave_settings.tenant_id
        ))
        AND (leave_settings.notify_bot_config_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.bot_configs p
            WHERE p.id = leave_settings.notify_bot_config_id AND p.tenant_id = leave_settings.tenant_id
        ))
    );

DROP POLICY leave_periods_tenant ON alc_api.leave_periods;
CREATE POLICY leave_periods_tenant ON alc_api.leave_periods
    USING (tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID)
    WITH CHECK (
        tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
        AND EXISTS (
            SELECT 1 FROM alc_api.leave_pages p
            WHERE p.id = leave_periods.page_id AND p.tenant_id = leave_periods.tenant_id
        )
    );
