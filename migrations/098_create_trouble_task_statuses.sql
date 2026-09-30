-- trouble_tasks.status を dynamic master 化
-- 既存 trouble_tasks 行は status = 'open' | 'in_progress' | 'done' を使っているため、
-- master table の key にもそれらを seed して後方互換を保つ。

-- 1. master table
CREATE TABLE alc_api.trouble_task_statuses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id) ON DELETE CASCADE,
    key TEXT NOT NULL,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#9CA3AF',
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_done BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, key),
    UNIQUE (tenant_id, name)
);

ALTER TABLE alc_api.trouble_task_statuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON alc_api.trouble_task_statuses
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.trouble_task_statuses TO alc_api_app;

-- 2. relax CHECK constraint on trouble_tasks.status (now free text)
ALTER TABLE alc_api.trouble_tasks
    DROP CONSTRAINT IF EXISTS trouble_tasks_status_check;

-- 3. seed defaults for every existing tenant
INSERT INTO alc_api.trouble_task_statuses (tenant_id, key, name, color, sort_order, is_done)
SELECT t.id, seed.key, seed.name, seed.color, seed.sort_order, seed.is_done
FROM alc_api.tenants t
CROSS JOIN (VALUES
    ('open',        '未着手', '#9CA3AF', 10, false),
    ('in_progress', '進行中', '#3B82F6', 20, false),
    ('waiting',     '待機',   '#F59E0B', 30, false),
    ('done',        '完了',   '#10B981', 40, true)
) AS seed(key, name, color, sort_order, is_done)
WHERE NOT EXISTS (
    SELECT 1 FROM alc_api.trouble_task_statuses s
    WHERE s.tenant_id = t.id AND s.key = seed.key
);
