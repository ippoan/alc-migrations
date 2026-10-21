-- 指静脈テンプレートに記録の形式の列を足す (足すだけ)
-- Refs ippoan/alc-app#436
--
-- template_format は記録の作り方を表す。
--   'chara'  = 今の形 (サーバーが特徴量から作り直した記録)
--   'module' = 端末のモジュールが作った記録全体
-- 既存の行はすべて 'chara' (DEFAULT で埋まる。UPDATE は書かない)。
-- RLS・UNIQUE・GRANT は変えない (表単位の GRANT は列に継承される)。

-- ロックを取れないまま待ち続けると、その後ろに本番の問い合わせが詰まる。10 秒で取れなければ
-- migration を失敗させる (理由は 154 の冒頭)。SET LOCAL なので、この migration の中だけに効く。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.vein_templates
    ADD COLUMN template_format TEXT NOT NULL DEFAULT 'chara'
    CHECK (template_format IN ('chara', 'module'));
