-- 指静脈テンプレートに管理者の承認の列を足す (足すだけ)
-- Refs ippoan/alc-app#436
--
-- 登録したテンプレートは、管理者が承認するまで照合に使わない。approved_at が NULL = 承認待ち。
-- DEFAULT now() で、既存の行と、この migration から worker の切り替えまでに旧 worker が入れる行は
-- 承認済みになる (UPDATE は書かない)。新しい worker は INSERT / UPSERT で NULL を明示して待ちにする。
-- RLS・UNIQUE・GRANT は変えない (表単位の GRANT は列に継承される)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (理由は 154 の冒頭)。SET LOCAL なので、この migration の中だけに効く。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.vein_templates ADD COLUMN approved_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE alc_api.vein_templates ADD COLUMN approved_by UUID;
