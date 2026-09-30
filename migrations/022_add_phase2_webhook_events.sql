-- Phase 2: Webhook イベントタイプ追加
ALTER TABLE webhook_configs DROP CONSTRAINT IF EXISTS webhook_configs_event_type_check;
ALTER TABLE webhook_configs ADD CONSTRAINT webhook_configs_event_type_check
    CHECK (event_type IN (
        'alcohol_detected',
        'tenko_overdue',
        'tenko_completed',
        'tenko_cancelled',
        'tenko_interrupted',
        'inspection_ng',
        'safety_judgment_fail',
        'equipment_failure'
    ));
