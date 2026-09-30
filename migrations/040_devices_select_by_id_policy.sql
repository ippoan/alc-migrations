-- デバイス設定取得 (認証不要エンドポイント) 用に device_id 指定の SELECT を許可
-- RLS テナントポリシーだけだと set_current_tenant なしではアクセスできない
CREATE POLICY device_select_by_id ON alc_api.devices
    FOR SELECT USING (true);
