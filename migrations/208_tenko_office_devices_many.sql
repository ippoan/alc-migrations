-- 点呼端末を複数の営業所に所属させる (主キーの作り直し。行は消さない)
--
-- 207 は 1 台 1 営業所 (主キー (tenant_id, device_id)) にしたが、同じ建物で別の会社の営業所が 1 台の点呼端末を
-- 共用する (自社の本社とグループ企業の本社など)。端末は複数の営業所に所属できるようにし、主キーを
-- (tenant_id, office_id, device_id) にする。キオスクの車両番号の候補は、端末が所属するどの営業所の車両も先に出す。
-- 既存の行はそのまま新しい主キーを満たす (旧主キーより細かい)。

SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.tenko_office_devices DROP CONSTRAINT tenko_office_devices_pkey;
ALTER TABLE alc_api.tenko_office_devices ADD PRIMARY KEY (tenant_id, office_id, device_id);
-- 候補の口は端末から営業所を引く
CREATE INDEX idx_tenko_office_devices_device
    ON alc_api.tenko_office_devices (tenant_id, device_id);
