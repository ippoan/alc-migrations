-- trouble_tickets.vehicle_number を廃止し、以降 registration_number に一本化する。
-- prod 全チケットで vehicle_number は空文字、modern な機能 (車検証 lookup / 半角正規化 / q 検索) は
-- 全て registration_number 側に実装済み。
ALTER TABLE alc_api.trouble_tickets DROP COLUMN IF EXISTS vehicle_number;
