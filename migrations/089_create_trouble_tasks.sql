-- タスク (対応活動の管理単位)
CREATE TABLE alc_api.trouble_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES alc_api.tenants(id),
    ticket_id UUID NOT NULL REFERENCES alc_api.trouble_tickets(id) ON DELETE CASCADE,
    task_type TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'done')),
    assigned_to UUID,
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_by UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_trouble_tasks_ticket ON alc_api.trouble_tasks(ticket_id);
CREATE INDEX idx_trouble_tasks_ticket_status ON alc_api.trouble_tasks(ticket_id, status);

-- trouble_files にタスク紐づけカラム追加
ALTER TABLE alc_api.trouble_files
  ADD COLUMN task_id UUID REFERENCES alc_api.trouble_tasks(id) ON DELETE CASCADE;

CREATE INDEX idx_trouble_files_task ON alc_api.trouble_files(task_id) WHERE task_id IS NOT NULL;

-- RLS
ALTER TABLE alc_api.trouble_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON alc_api.trouble_tasks
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

-- GRANT
GRANT SELECT, INSERT, UPDATE, DELETE ON alc_api.trouble_tasks TO alc_api_app;
