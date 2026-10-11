-- テナントを持つ表どうしの外部キーを、tenant_id を含む複合にする (ci/fk_tenant_composite_allowlist.txt の todo 39 本)
-- Refs ippoan/rust-alc-api#747
--
-- 外部キーの検査は RLS を通らないので、子の外部キーが親の id だけを指していると、別のテナントの親の行を
-- 指す行を作れる。親に UNIQUE (tenant_id, <キー>) を足し、子の外部キーを
-- FOREIGN KEY (tenant_id, <列>) REFERENCES <親> (tenant_id, <キー>) に付け替えて、DB がそれを拒否するようにする。
--
-- * 制約名は変えない (名前を見ているコードを壊さないため)。ON DELETE は元のものを引き継ぐ
-- * ON DELETE SET NULL は列を指定する (SET NULL (<列>)。tenant_id まで NULL にしないため。PG15+)
-- * NOT VALID は使わない (対象の表は小さく、別のテナントの親を指す既存の行が無いことを確かめてある)。
--   その場で全行を検査する
-- * 親の UNIQUE を全部先に足してから外部キーを付け替える (自己参照の items・guidance_records と、
--   tenko_sessions と tenko_schedules の相互参照のため)
-- * device_registration_requests.device_id は直さない (子の tenant_id が NULL 可で、複合にすると
--   tenant_id が NULL の行で参照の検査ごと消えるため。許可リストに nullable-tenant として残す)
-- * access_requests.user_id は直さない (別のテナントの利用者が、このテナントへの参加を申請する行。
--   利用者は申請先とは別のテナントに属する。許可リストに cross-tenant として残す)
-- * 書き込みのポリシーで塞いだ組 (policy) と、tenants を指す外部キーは触らない

SET LOCAL lock_timeout = '10s';

-- 親: UNIQUE (tenant_id, <キー>)。キーは files だけ uuid
ALTER TABLE alc_api.bot_configs ADD CONSTRAINT bot_configs_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.cameras ADD CONSTRAINT cameras_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.car_inspection ADD CONSTRAINT car_inspection_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.dtako_offices ADD CONSTRAINT dtako_offices_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.dtako_vehicles ADD CONSTRAINT dtako_vehicles_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.employees ADD CONSTRAINT employees_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.files ADD CONSTRAINT files_tenant_id_uuid_key UNIQUE (tenant_id, uuid);
ALTER TABLE alc_api.guidance_records ADD CONSTRAINT guidance_records_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.items ADD CONSTRAINT items_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.maintenance_categories ADD CONSTRAINT maintenance_categories_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.maintenance_records ADD CONSTRAINT maintenance_records_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.maintenance_vehicles ADD CONSTRAINT maintenance_vehicles_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.measurements ADD CONSTRAINT measurements_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.tenko_schedules ADD CONSTRAINT tenko_schedules_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.tenko_sessions ADD CONSTRAINT tenko_sessions_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.trouble_offices ADD CONSTRAINT trouble_offices_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.trouble_tickets ADD CONSTRAINT trouble_tickets_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.users ADD CONSTRAINT users_tenant_id_id_key UNIQUE (tenant_id, id);
ALTER TABLE alc_api.webhook_configs ADD CONSTRAINT webhook_configs_tenant_id_id_key UNIQUE (tenant_id, id);

-- 外部キーを足すときの既存行の検査は、表の所有者として 1 本の SELECT で流れ、FORCE ROW LEVEL SECURITY の表では
-- 所有者にもポリシーが掛かる (本番は所有者が migration を流す)。tenant context が無いので、行が 0 に絞られて
-- 検査が空振りするか、current_setting で落ちる。関わる FORCE の表 (子と親) だけ、この transaction の間 FORCE を外し、
-- 付け替えの後に戻す (終わった時点の RLS の状態は変わらない)
ALTER TABLE alc_api.bot_configs NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.car_inspection NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.car_inspection_deregistration_files NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.car_inspection_nfc_tags NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.dtako_daily_recalc_pending NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.file_access_logs NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.files NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.files_append NO FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.lineworks_channels NO FORCE ROW LEVEL SECURITY;

-- 子: 同じ制約名のまま (tenant_id, <列>) の複合に付け替える
ALTER TABLE alc_api.camera_health_logs
    DROP CONSTRAINT camera_health_logs_camera_id_fkey,
    ADD CONSTRAINT camera_health_logs_camera_id_fkey FOREIGN KEY (tenant_id, camera_id) REFERENCES alc_api.cameras (tenant_id, id) ON DELETE CASCADE;
ALTER TABLE alc_api.cameras
    DROP CONSTRAINT cameras_active_down_ticket_id_fkey,
    ADD CONSTRAINT cameras_active_down_ticket_id_fkey FOREIGN KEY (tenant_id, active_down_ticket_id) REFERENCES alc_api.trouble_tickets (tenant_id, id);
ALTER TABLE alc_api.cameras
    DROP CONSTRAINT cameras_office_id_fkey,
    ADD CONSTRAINT cameras_office_id_fkey FOREIGN KEY (tenant_id, office_id) REFERENCES alc_api.trouble_offices (tenant_id, id);
ALTER TABLE alc_api.car_inspection_deregistration_files
    DROP CONSTRAINT car_inspection_deregistration_files_file_uuid_fkey,
    ADD CONSTRAINT car_inspection_deregistration_files_file_uuid_fkey FOREIGN KEY (tenant_id, file_uuid) REFERENCES alc_api.files (tenant_id, uuid);
ALTER TABLE alc_api.car_inspection_nfc_tags
    DROP CONSTRAINT car_inspection_nfc_tags_car_inspection_id_fkey,
    ADD CONSTRAINT car_inspection_nfc_tags_car_inspection_id_fkey FOREIGN KEY (tenant_id, car_inspection_id) REFERENCES alc_api.car_inspection (tenant_id, id) ON DELETE CASCADE;
ALTER TABLE alc_api.communication_items
    DROP CONSTRAINT communication_items_target_employee_id_fkey,
    ADD CONSTRAINT communication_items_target_employee_id_fkey FOREIGN KEY (tenant_id, target_employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.devices
    DROP CONSTRAINT devices_approved_by_fkey,
    ADD CONSTRAINT devices_approved_by_fkey FOREIGN KEY (tenant_id, approved_by) REFERENCES alc_api.users (tenant_id, id);
ALTER TABLE alc_api.devices
    DROP CONSTRAINT devices_last_login_employee_id_fkey,
    ADD CONSTRAINT devices_last_login_employee_id_fkey FOREIGN KEY (tenant_id, last_login_employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.devices
    DROP CONSTRAINT devices_user_id_fkey,
    ADD CONSTRAINT devices_user_id_fkey FOREIGN KEY (tenant_id, user_id) REFERENCES alc_api.users (tenant_id, id);
ALTER TABLE alc_api.dtako_daily_recalc_pending
    DROP CONSTRAINT dtako_daily_recalc_pending_driver_id_fkey,
    ADD CONSTRAINT dtako_daily_recalc_pending_driver_id_fkey FOREIGN KEY (tenant_id, driver_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.dtako_daily_work_hours
    DROP CONSTRAINT dtako_daily_work_hours_driver_id_fkey,
    ADD CONSTRAINT dtako_daily_work_hours_driver_id_fkey FOREIGN KEY (tenant_id, driver_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.dtako_daily_work_segments
    DROP CONSTRAINT dtako_daily_work_segments_driver_id_fkey,
    ADD CONSTRAINT dtako_daily_work_segments_driver_id_fkey FOREIGN KEY (tenant_id, driver_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.dtako_operations
    DROP CONSTRAINT dtako_operations_driver_id_fkey,
    ADD CONSTRAINT dtako_operations_driver_id_fkey FOREIGN KEY (tenant_id, driver_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.dtako_operations
    DROP CONSTRAINT dtako_operations_office_id_fkey,
    ADD CONSTRAINT dtako_operations_office_id_fkey FOREIGN KEY (tenant_id, office_id) REFERENCES alc_api.dtako_offices (tenant_id, id);
ALTER TABLE alc_api.dtako_operations
    DROP CONSTRAINT dtako_operations_vehicle_id_fkey,
    ADD CONSTRAINT dtako_operations_vehicle_id_fkey FOREIGN KEY (tenant_id, vehicle_id) REFERENCES alc_api.dtako_vehicles (tenant_id, id);
ALTER TABLE alc_api.dtako_upload_history
    DROP CONSTRAINT dtako_upload_history_uploaded_by_fkey,
    ADD CONSTRAINT dtako_upload_history_uploaded_by_fkey FOREIGN KEY (tenant_id, uploaded_by) REFERENCES alc_api.users (tenant_id, id);
ALTER TABLE alc_api.employee_health_baselines
    DROP CONSTRAINT employee_health_baselines_employee_id_fkey,
    ADD CONSTRAINT employee_health_baselines_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.equipment_failures
    DROP CONSTRAINT equipment_failures_session_id_fkey,
    ADD CONSTRAINT equipment_failures_session_id_fkey FOREIGN KEY (tenant_id, session_id) REFERENCES alc_api.tenko_sessions (tenant_id, id);
ALTER TABLE alc_api.file_access_logs
    DROP CONSTRAINT file_access_logs_file_uuid_fkey,
    ADD CONSTRAINT file_access_logs_file_uuid_fkey FOREIGN KEY (tenant_id, file_uuid) REFERENCES alc_api.files (tenant_id, uuid) ON DELETE CASCADE;
ALTER TABLE alc_api.files_append
    DROP CONSTRAINT files_append_file_uuid_fkey,
    ADD CONSTRAINT files_append_file_uuid_fkey FOREIGN KEY (tenant_id, file_uuid) REFERENCES alc_api.files (tenant_id, uuid);
ALTER TABLE alc_api.guidance_records
    DROP CONSTRAINT guidance_records_employee_id_fkey,
    ADD CONSTRAINT guidance_records_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.guidance_records
    DROP CONSTRAINT guidance_records_parent_id_fkey,
    ADD CONSTRAINT guidance_records_parent_id_fkey FOREIGN KEY (tenant_id, parent_id) REFERENCES alc_api.guidance_records (tenant_id, id);
ALTER TABLE alc_api.items
    DROP CONSTRAINT items_parent_id_fkey,
    ADD CONSTRAINT items_parent_id_fkey FOREIGN KEY (tenant_id, parent_id) REFERENCES alc_api.items (tenant_id, id) ON DELETE CASCADE;
ALTER TABLE alc_api.lineworks_channels
    DROP CONSTRAINT lineworks_channels_bot_config_id_fkey,
    ADD CONSTRAINT lineworks_channels_bot_config_id_fkey FOREIGN KEY (tenant_id, bot_config_id) REFERENCES alc_api.bot_configs (tenant_id, id) ON DELETE CASCADE;
ALTER TABLE alc_api.maintenance_files
    DROP CONSTRAINT maintenance_files_record_id_fkey,
    ADD CONSTRAINT maintenance_files_record_id_fkey FOREIGN KEY (tenant_id, record_id) REFERENCES alc_api.maintenance_records (tenant_id, id) ON DELETE CASCADE;
ALTER TABLE alc_api.maintenance_records
    DROP CONSTRAINT maintenance_records_category_id_fkey,
    ADD CONSTRAINT maintenance_records_category_id_fkey FOREIGN KEY (tenant_id, category_id) REFERENCES alc_api.maintenance_categories (tenant_id, id);
ALTER TABLE alc_api.maintenance_records
    DROP CONSTRAINT maintenance_records_vehicle_id_fkey,
    ADD CONSTRAINT maintenance_records_vehicle_id_fkey FOREIGN KEY (tenant_id, vehicle_id) REFERENCES alc_api.maintenance_vehicles (tenant_id, id);
ALTER TABLE alc_api.measurements
    DROP CONSTRAINT measurements_employee_id_fkey,
    ADD CONSTRAINT measurements_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.tenko_records
    DROP CONSTRAINT tenko_records_employee_id_fkey,
    ADD CONSTRAINT tenko_records_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.tenko_records
    DROP CONSTRAINT tenko_records_session_id_fkey,
    ADD CONSTRAINT tenko_records_session_id_fkey FOREIGN KEY (tenant_id, session_id) REFERENCES alc_api.tenko_sessions (tenant_id, id);
ALTER TABLE alc_api.tenko_schedules
    DROP CONSTRAINT fk_consumed_by_session,
    ADD CONSTRAINT fk_consumed_by_session FOREIGN KEY (tenant_id, consumed_by_session_id) REFERENCES alc_api.tenko_sessions (tenant_id, id);
ALTER TABLE alc_api.tenko_schedules
    DROP CONSTRAINT tenko_schedules_employee_id_fkey,
    ADD CONSTRAINT tenko_schedules_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.tenko_sessions
    DROP CONSTRAINT tenko_sessions_employee_id_fkey,
    ADD CONSTRAINT tenko_sessions_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.tenko_sessions
    DROP CONSTRAINT tenko_sessions_manager_judgment_by_fkey,
    ADD CONSTRAINT tenko_sessions_manager_judgment_by_fkey FOREIGN KEY (tenant_id, manager_judgment_by) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.tenko_sessions
    DROP CONSTRAINT tenko_sessions_measurement_id_fkey,
    ADD CONSTRAINT tenko_sessions_measurement_id_fkey FOREIGN KEY (tenant_id, measurement_id) REFERENCES alc_api.measurements (tenant_id, id);
ALTER TABLE alc_api.tenko_sessions
    DROP CONSTRAINT tenko_sessions_schedule_id_fkey,
    ADD CONSTRAINT tenko_sessions_schedule_id_fkey FOREIGN KEY (tenant_id, schedule_id) REFERENCES alc_api.tenko_schedules (tenant_id, id) ON DELETE SET NULL (schedule_id);
ALTER TABLE alc_api.timecard_cards
    DROP CONSTRAINT timecard_cards_employee_id_fkey,
    ADD CONSTRAINT timecard_cards_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.vein_templates
    DROP CONSTRAINT vein_templates_employee_id_fkey,
    ADD CONSTRAINT vein_templates_employee_id_fkey FOREIGN KEY (tenant_id, employee_id) REFERENCES alc_api.employees (tenant_id, id);
ALTER TABLE alc_api.webhook_deliveries
    DROP CONSTRAINT webhook_deliveries_config_id_fkey,
    ADD CONSTRAINT webhook_deliveries_config_id_fkey FOREIGN KEY (tenant_id, config_id) REFERENCES alc_api.webhook_configs (tenant_id, id);

ALTER TABLE alc_api.bot_configs FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.car_inspection FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.car_inspection_deregistration_files FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.car_inspection_nfc_tags FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.dtako_daily_recalc_pending FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.file_access_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.files FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.files_append FORCE ROW LEVEL SECURITY;
ALTER TABLE alc_api.lineworks_channels FORCE ROW LEVEL SECURITY;
