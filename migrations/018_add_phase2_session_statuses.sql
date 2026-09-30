-- Phase 2: 新しいセッション状態を追加
ALTER TABLE tenko_sessions DROP CONSTRAINT IF EXISTS tenko_sessions_status_check;
ALTER TABLE tenko_sessions ADD CONSTRAINT tenko_sessions_status_check
    CHECK (status IN (
        'identity_verified',
        'alcohol_testing',
        'medical_pending',
        'self_declaration_pending',
        'daily_inspection_pending',
        'instruction_pending',
        'report_pending',
        'completed',
        'cancelled',
        'interrupted'
    ));
