-- tenants.short_id : メール ingest や URL で使う 8 文字 hex の短縮 ID
--
-- これまで `tenants.slug` を兼用していたが、Google OAuth 自動サインアップで
-- 作られたテナントは slug が NULL のままで、`tenant-{slug}@notify...` 経路や
-- /auth/me の tenant_slug が機能していなかった。
--
-- short_id は UNIQUE 制約付きで NOT NULL。INSERT 側は衝突したらアプリ側
-- (create_tenant_with_domain) で再生成する。

ALTER TABLE alc_api.tenants
    ADD COLUMN short_id TEXT
    DEFAULT substring(replace(gen_random_uuid()::text, '-', '') FROM 1 FOR 8);

-- 既存テナントを backfill (UNIQUE 制約は後で張るので衝突したら再ループ)。
DO $backfill$
DECLARE
    t RECORD;
    new_short TEXT;
    attempts INT;
BEGIN
    FOR t IN SELECT id FROM alc_api.tenants WHERE short_id IS NULL LOOP
        attempts := 0;
        LOOP
            new_short := substring(replace(gen_random_uuid()::text, '-', '') FROM 1 FOR 8);
            EXIT WHEN NOT EXISTS (
                SELECT 1 FROM alc_api.tenants
                WHERE short_id = new_short AND id <> t.id
            );
            attempts := attempts + 1;
            IF attempts > 100 THEN
                RAISE EXCEPTION 'could not generate unique short_id for tenant %', t.id;
            END IF;
        END LOOP;
        UPDATE alc_api.tenants SET short_id = new_short WHERE id = t.id;
    END LOOP;
END
$backfill$;

ALTER TABLE alc_api.tenants ALTER COLUMN short_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS tenants_short_id_unique
    ON alc_api.tenants (short_id);
