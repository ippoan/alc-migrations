-- 点呼の自己再開 (キオスク) で行った本人確認の方法を記録する列を足す (自己点検表 業務前 十三)
--
-- 中断した点呼をキオスクで続けるとき (`POST /api/tenko/sessions/{id}/self-resume`)、これまでサーバーは
-- キオスクの鍵だけで受けていた。今後は照合で決まった社員と方法を受け、点呼の乗務員と一致するときだけ
-- 再開させる (alc-measurements-worker)。その方法をここに残す。
--
-- resume_identity_method の値:
--   'vein' = 指静脈の照合
--   'face' = 顔認証 (デモの端末だけ)
--   NULL   = 記録なし (この列より前の再開、管理者による再開、または再開していない点呼)
--
-- 足すだけ (expand)。既存の行は NULL のまま (backfill しない)。古い worker は余剰の列を読まず、
-- INSERT / UPDATE でこの列を指定しないので、この migration だけ先に入っても動く。
-- RLS のポリシーは行単位なので変えない。GRANT は表単位で既に付いているので足さない。
-- IF NOT EXISTS は付けない (同名で形の違う列が既に在ったら、ここで落とす)。
SET LOCAL lock_timeout = '10s';

ALTER TABLE alc_api.tenko_sessions
    ADD COLUMN resume_identity_method TEXT
        CHECK (resume_identity_method IS NULL OR resume_identity_method IN ('vein', 'face'));

COMMENT ON COLUMN alc_api.tenko_sessions.resume_identity_method IS
    'キオスクで自己再開したときの本人確認の方法。vein = 指静脈の照合 / face = 顔認証 (デモの端末) / NULL = 記録なし';
