-- 指静脈テンプレートの承認に、承認した運行管理者 (社員) の列を足す (足すだけ)
-- Refs ippoan/alc-app#436
--
-- 端末の画面で、運行管理者が自分の指静脈で照合してから承認できるようにする。
-- そのときの承認者は利用者 (users) ではなく社員なので、approved_by (利用者の id) とは別の列に持つ。
-- 管理画面からの承認と既存の行は NULL。UPDATE は書かない。
-- 外部キーはテナントを含める (172 の規約)。社員を消したら承認者の記録だけ外す (承認は残す)。
-- RLS・GRANT は変えない (表単位の GRANT は列に継承される)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (理由は 154 の冒頭)。SET LOCAL なので、この migration の中だけに効く。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.vein_templates
    ADD COLUMN approved_by_employee_id UUID;
ALTER TABLE alc_api.vein_templates
    ADD CONSTRAINT vein_templates_approved_by_employee_id_fkey FOREIGN KEY (tenant_id, approved_by_employee_id)
    REFERENCES alc_api.employees (tenant_id, id) ON DELETE SET NULL (approved_by_employee_id);
