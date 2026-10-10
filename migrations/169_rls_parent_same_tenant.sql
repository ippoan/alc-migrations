-- 子の表が外部キーで指す親の行が、子と同じテナントに在ることを、書き込みのポリシー (WITH CHECK) でも確かめる。
-- 外部キーの検査は RLS を通らないので、これまでの WITH CHECK (子の tenant_id だけ) では、
-- 別のテナントの親の id を指す行を自分のテナントに書けた (例: 別のテナントの recipient_id を自分の group に足す /
-- 別のテナントの ticket_id で trouble_tasks を作る)。アプリの書き方に頼らず、DB の側で塞ぐ。
-- Refs ippoan/rust-alc-api#747
--
-- 既存のポリシーを DROP POLICY → CREATE POLICY で作り直す (名前・USING は変えない。WITH CHECK に条件を足すだけ)。
-- WITH CHECK は INSERT と UPDATE の新しい行にだけ効き、既存の行は変えない。
-- NULL を許す外部キーの列は、NULL なら通す (指す親が無い)。
--
-- 対象 (notify / trouble の表が、外部キーで親を指す組):
--   notify_recipient_groups.recipient_id      → notify_recipients
--   notify_deliveries.document_id             → notify_documents
--   notify_deliveries.recipient_id            → notify_recipients
--   notify_deliveries.triggered_by_user_id    → users
--   trouble_tickets.status_id                 → trouble_workflow_states
--   trouble_tickets.person_id                 → employees
--   trouble_tasks.ticket_id                   → trouble_tickets
--   trouble_files.ticket_id / task_id         → trouble_tickets / trouble_tasks
--   trouble_schedules.ticket_id               → trouble_tickets
--   trouble_status_history.ticket_id          → trouble_tickets
--   trouble_status_history.from_state_id / to_state_id → trouble_workflow_states
--   trouble_workflow_transitions.from_state_id / to_state_id → trouble_workflow_states

-- notify_recipient_groups (tenant_id 列を持たない。テナントは group の側で決まる): recipient も同じテナント
DROP POLICY notify_recipient_groups_insert ON alc_api.notify_recipient_groups;
CREATE POLICY notify_recipient_groups_insert ON alc_api.notify_recipient_groups
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM alc_api.notify_groups g
            WHERE g.id = notify_recipient_groups.group_id
              AND g.tenant_id = current_setting('app.current_tenant_id', true)::UUID
        )
        AND EXISTS (
            SELECT 1 FROM alc_api.notify_recipients r
            WHERE r.id = notify_recipient_groups.recipient_id
              AND r.tenant_id = current_setting('app.current_tenant_id', true)::UUID
        )
    );

-- notify_deliveries: INSERT と UPDATE (UPDATE は WITH CHECK が無く USING を流用していた)
DROP POLICY notify_deliveries_insert ON alc_api.notify_deliveries;
CREATE POLICY notify_deliveries_insert ON alc_api.notify_deliveries
    FOR INSERT WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::UUID
        AND EXISTS (
            SELECT 1 FROM alc_api.notify_documents p
            WHERE p.id = notify_deliveries.document_id AND p.tenant_id = notify_deliveries.tenant_id
        )
        AND (notify_deliveries.recipient_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.notify_recipients p
            WHERE p.id = notify_deliveries.recipient_id AND p.tenant_id = notify_deliveries.tenant_id
        ))
        AND (notify_deliveries.triggered_by_user_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.users p
            WHERE p.id = notify_deliveries.triggered_by_user_id AND p.tenant_id = notify_deliveries.tenant_id
        ))
    );

DROP POLICY notify_deliveries_update ON alc_api.notify_deliveries;
CREATE POLICY notify_deliveries_update ON alc_api.notify_deliveries
    FOR UPDATE USING (tenant_id = current_setting('app.current_tenant_id', true)::UUID)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::UUID
        AND EXISTS (
            SELECT 1 FROM alc_api.notify_documents p
            WHERE p.id = notify_deliveries.document_id AND p.tenant_id = notify_deliveries.tenant_id
        )
        AND (notify_deliveries.recipient_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.notify_recipients p
            WHERE p.id = notify_deliveries.recipient_id AND p.tenant_id = notify_deliveries.tenant_id
        ))
        AND (notify_deliveries.triggered_by_user_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.users p
            WHERE p.id = notify_deliveries.triggered_by_user_id AND p.tenant_id = notify_deliveries.tenant_id
        ))
    );

-- trouble_*: FOR ALL の tenant_isolation (WITH CHECK が INSERT と UPDATE に効く)
DROP POLICY tenant_isolation ON alc_api.trouble_tickets;
CREATE POLICY tenant_isolation ON alc_api.trouble_tickets
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND (trouble_tickets.status_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.trouble_workflow_states p
            WHERE p.id = trouble_tickets.status_id AND p.tenant_id = trouble_tickets.tenant_id
        ))
        AND (trouble_tickets.person_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.employees p
            WHERE p.id = trouble_tickets.person_id AND p.tenant_id = trouble_tickets.tenant_id
        ))
    );

DROP POLICY tenant_isolation ON alc_api.trouble_tasks;
CREATE POLICY tenant_isolation ON alc_api.trouble_tasks
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_tickets p
            WHERE p.id = trouble_tasks.ticket_id AND p.tenant_id = trouble_tasks.tenant_id
        )
    );

DROP POLICY tenant_isolation ON alc_api.trouble_files;
CREATE POLICY tenant_isolation ON alc_api.trouble_files
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_tickets p
            WHERE p.id = trouble_files.ticket_id AND p.tenant_id = trouble_files.tenant_id
        )
        AND (trouble_files.task_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.trouble_tasks p
            WHERE p.id = trouble_files.task_id AND p.tenant_id = trouble_files.tenant_id
        ))
    );

DROP POLICY tenant_isolation ON alc_api.trouble_schedules;
CREATE POLICY tenant_isolation ON alc_api.trouble_schedules
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_tickets p
            WHERE p.id = trouble_schedules.ticket_id AND p.tenant_id = trouble_schedules.tenant_id
        )
    );

DROP POLICY tenant_isolation ON alc_api.trouble_status_history;
CREATE POLICY tenant_isolation ON alc_api.trouble_status_history
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_tickets p
            WHERE p.id = trouble_status_history.ticket_id AND p.tenant_id = trouble_status_history.tenant_id
        )
        AND (trouble_status_history.from_state_id IS NULL OR EXISTS (
            SELECT 1 FROM alc_api.trouble_workflow_states p
            WHERE p.id = trouble_status_history.from_state_id AND p.tenant_id = trouble_status_history.tenant_id
        ))
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_workflow_states p
            WHERE p.id = trouble_status_history.to_state_id AND p.tenant_id = trouble_status_history.tenant_id
        )
    );

DROP POLICY tenant_isolation ON alc_api.trouble_workflow_transitions;
CREATE POLICY tenant_isolation ON alc_api.trouble_workflow_transitions
    FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid)
    WITH CHECK (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_workflow_states p
            WHERE p.id = trouble_workflow_transitions.from_state_id AND p.tenant_id = trouble_workflow_transitions.tenant_id
        )
        AND EXISTS (
            SELECT 1 FROM alc_api.trouble_workflow_states p
            WHERE p.id = trouble_workflow_transitions.to_state_id AND p.tenant_id = trouble_workflow_transitions.tenant_id
        )
    );
