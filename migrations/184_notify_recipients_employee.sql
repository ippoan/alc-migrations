-- 通知の宛先に社員を結び付ける列を足す (足すだけ)
-- Refs ippoan/alc-app#436
--
-- employee_id は、この宛先 (LINE WORKS のユーザーなど) が社員マスタのどの社員か。
-- 血圧を測ったときに本人へ LINE WORKS で結果を送るため、測定の employee_id から宛先を引く。
-- 結び付けていない宛先と既存の行は NULL。UPDATE は書かない。
-- 社員を消したら結び付けだけ外す (ON DELETE SET NULL。宛先は残す)。
-- 1 人の社員に結び付く宛先は 1 つだけ (同じ人へ 2 通送らない)。
-- RLS・GRANT は変えない (表単位の GRANT は列に継承される)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (理由は 154 の冒頭)。SET LOCAL なので、この migration の中だけに効く。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.notify_recipients
    ADD COLUMN employee_id UUID REFERENCES alc_api.employees(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX idx_notify_recipients_employee ON alc_api.notify_recipients(tenant_id, employee_id)
    WHERE employee_id IS NOT NULL;
