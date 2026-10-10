-- 勤怠申請の個人宛ての警告・テスト送信で使う LINE WORKS の bot を選べるようにする列。
--
-- 個人 (notify_recipient_id) 宛ての送信は、送信側が「tenant の有効な LINE WORKS bot のうち名前順の最初」を
-- 使うため、tenant に bot が複数あると勤怠用ではない bot から届く。勤怠の設定に使う bot を持たせ、
-- 送信の body に載せる。NULL = 指定なし (今までどおり)。
-- bot が消えたら NULL に戻す (notify_recipient_id と同じ ON DELETE SET NULL)。
-- bot は個人宛てのときだけ意味を持つので、notify_recipient_id が NULL のまま bot だけ入る行を CHECK で防ぐ。
-- 既存行は notify_bot_config_id がすべて NULL なので CHECK を通る。
-- 行が LINE WORKS の bot か・有効かは表をまたぐので CHECK にせず、送信側 (alc-lineworks-worker) が見る。
-- leave_enabled_tenants (164) の返す列は変えない (Refs ohishi-exp/rust-leave-worker#1)。
ALTER TABLE alc_api.leave_settings
    ADD COLUMN notify_bot_config_id UUID REFERENCES alc_api.bot_configs(id) ON DELETE SET NULL;
ALTER TABLE alc_api.leave_settings
    ADD CONSTRAINT leave_settings_bot_needs_recipient
    CHECK (notify_bot_config_id IS NULL OR notify_recipient_id IS NOT NULL);
