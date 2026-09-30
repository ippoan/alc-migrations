-- result CHECK制約を拡張: フロントエンドの result_type 値 ('normal','over','error') を受け付ける
ALTER TABLE measurements DROP CONSTRAINT measurements_result_check;
ALTER TABLE measurements ADD CONSTRAINT measurements_result_check
    CHECK (result IN ('pass', 'fail', 'normal', 'over', 'error'));

-- device_use_count カラム追加 (FC-1200 センサ使用回数)
ALTER TABLE measurements ADD COLUMN device_use_count INTEGER NOT NULL DEFAULT 0;
