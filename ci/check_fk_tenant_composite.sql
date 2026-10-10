-- CI の replay job 専用の検査。crate には含めない (scripts/ ではなく ci/ に置く)。
--
-- テナントを持つ表どうしの外部キーが、tenant_id を含む複合になっているかを、カタログ (pg_constraint) だけで確かめる。
-- 外部キーの検査は RLS を通らないので、子の表の外部キーが親の id だけを指していると、別のテナントの親の行を
-- 指す行を作れる。構造で塞ぐ定石は、親に UNIQUE (tenant_id, id)、子に
-- FOREIGN KEY (tenant_id, <列>) REFERENCES <親> (tenant_id, id) の複合の外部キー。
-- 書き込みのポリシーの WITH CHECK に親の tenant_id の一致を足す形 (migration 169・170) は、ポリシーの書き方に頼る次善の策。
-- ポリシーの式は解析しない (ポリシーで塞いだ組は ci/fk_tenant_composite_allowlist.txt に policy として載せ、
-- 実際に塞がっていることは ci/check_rls_parent_tenant.sql が行で確かめる)。Refs ippoan/rust-alc-api#747
--
-- 対象: alc_api スキーマの外部キー (contype = 'f'。分割表の子の写し conparentid <> 0 は除く) のうち、
-- 子と親の両方が tenant_id 列を持つもの。
-- 違反 = tenant_id が組になっていない外部キー: 子の tenant_id が conkey に無い、親の tenant_id が confkey に無い、
-- または両方在っても同じ位置で対になっていない。
--
-- 対象外:
--   * tenants を指す外部キー (tenant_id そのもの)
--   * 親が tenant_id を持たない外部キー (テナントに属さない親)
--   * 子が tenant_id を持たない外部キー (notify_recipient_groups・carrying_item_vehicle_conditions・
--     guidance_record_attachments・tenko_call_logs・tenko_carrying_item_checks など、テナントが親の側で決まる表)。
--     複合にする列が子に無いので、この検査の規則 (複合にする) が当てはまらない。こうした表のテナントは
--     ポリシーが親を引いて決める形で、別のテナントの親を指すかどうかはポリシーの書き方次第 (169 の
--     notify_recipient_groups.recipient_id は ci/check_rls_parent_tenant.sql が行で確かめる)
--
-- 複合になっていない外部キーを 1 行ずつ返す (child, columns, parent, constraint)。合否はこの SQL では決めない —
-- 呼ぶ側 (ci/check_fk_tenant_composite.sh) が許可リスト ci/fk_tenant_composite_allowlist.txt と比べて決める。
-- 何も変更しない 1 文の SELECT。ON_ERROR_STOP を外さない — 無いと SQL のエラーでも出力が空になる。
--
--   psql -v ON_ERROR_STOP=1 -q -At -F ' | ' -f ci/check_fk_tenant_composite.sql
SELECT
    child.relname AS child,
    (
        SELECT string_agg(a.attname, ',' ORDER BY k.ord)
        FROM unnest(c.conkey) WITH ORDINALITY AS k (attnum, ord)
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
    ) AS columns,
    parent.relname AS parent,
    c.conname AS constraint
FROM pg_constraint c
JOIN pg_class child ON child.oid = c.conrelid
JOIN pg_class parent ON parent.oid = c.confrelid
JOIN pg_attribute ct ON ct.attrelid = c.conrelid AND ct.attname = 'tenant_id' AND NOT ct.attisdropped
JOIN pg_attribute pt ON pt.attrelid = c.confrelid AND pt.attname = 'tenant_id' AND NOT pt.attisdropped
WHERE c.contype = 'f'
  AND c.connamespace = 'alc_api'::regnamespace
  AND c.conparentid = 0
  AND c.confrelid <> 'alc_api.tenants'::regclass
  AND (
      array_position(c.conkey, ct.attnum) IS NULL
      OR c.confkey[array_position(c.conkey, ct.attnum)] IS DISTINCT FROM pt.attnum
  )
ORDER BY child.relname, c.conname
