-- 勤怠申請の突合の警告の宛先に、個人 (notify_recipients) を選べるようにする列。
--
-- これまで宛先は LINE WORKS のグループ (lineworks_channel_id) だけだった。宛先はどちらか 1 つなので、
-- 両方が非 NULL にならない CHECK を付ける (どちらも NULL = 送らない、は今までどおり許す)。
-- 既存行は notify_recipient_id がすべて NULL なので CHECK を通る。
-- 宛先の個人が消えたら NULL に戻す (lineworks_channel_id と同じ ON DELETE SET NULL)。
-- LINE WORKS の行 (provider = 'lineworks') かは表をまたぐので CHECK にせず、rust-leave-worker と API が見る。
-- leave_enabled_tenants (164) の返す列は変えない。宛先は rust-leave-worker が tenant_tx の中で
-- leave_settings から読む (Refs ohishi-exp/rust-leave-worker#1)。
ALTER TABLE alc_api.leave_settings
    ADD COLUMN notify_recipient_id UUID REFERENCES alc_api.notify_recipients(id) ON DELETE SET NULL;
ALTER TABLE alc_api.leave_settings
    ADD CONSTRAINT leave_settings_single_destination
    CHECK (lineworks_channel_id IS NULL OR notify_recipient_id IS NULL);
