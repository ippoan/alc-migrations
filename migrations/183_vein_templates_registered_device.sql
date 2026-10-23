-- 指静脈テンプレートに、登録した端末の id の列を足す (足すだけ)
-- Refs ippoan/alc-app#436
--
-- registered_device_id は、記録を登録・更新した端末の id (端末の token の sub)。
-- 端末の画面の一覧と管理画面の一覧で「どの端末で登録した記録か」を見分けて調べるため。
-- 利用者 (管理者) の token で登録した行と、既存の行は NULL (= 分からない)。UPDATE は書かない。
-- 登録した時刻は既存の updated_at (登録・更新のたびに進む) を使う。
-- RLS・UNIQUE・GRANT は変えない (表単位の GRANT は列に継承される)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (理由は 154 の冒頭)。SET LOCAL なので、この migration の中だけに効く。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.vein_templates
    ADD COLUMN registered_device_id TEXT;
