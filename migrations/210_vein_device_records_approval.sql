-- 指静脈の端末ごとの記録に承認を持たせる (Refs ippoan/alc-app-s3#352)
--
-- 196 では「承認は持たない (足したらすぐ使う。オーナー決定 2026-10-31)」としたが、2026-11-07 のオーナー決定で
-- 承認を端末ごとにする。承認済みの記録が 1 つ以上ある乗務員が別の端末で登録したとき、その端末で撮った記録を
-- vein_templates (乗務員 1 人 1 件) に上書きせず、ここに端末ごとの 1 行として預かる。登録した記録の件のうち
-- 4 件以上が、承認済みの記録とサーバーの照合 (chara_verify) で合えば自動で承認し (auto_approved)、合わなければ
-- その端末の行だけ承認待ちにする (ほかの端末では承認済みの記録のまま使える)。
--
-- 2026-11-06 に、別の端末で登録し直すと乗務員の記録が全端末で承認待ちになり、端末の同期がモジュールの記録を
-- 消して指紋互換の部分を失った (同じ記録を書き直しても通りにくくなった)。端末ごとに承認すれば元の記録に触らない。
--
-- 既存の行と、この列を知らない worker が足す行 (「この端末の指を足す」) は承認済みとして扱う
-- (approved_at の DEFAULT now()。既存の行には ADD COLUMN の DEFAULT で migration の時刻が入る)。
-- 承認待ちにするのは、承認待ちを知る worker が NULL を明示して書いたときだけ。
-- 既存の行を登録の時刻へ UPDATE で揃えることはしない (FORCE ROW LEVEL SECURITY の表なので、テナントを
-- 設定しない migration の UPDATE は 0 行になる。106 と同じ理由)。

ALTER TABLE alc_api.vein_device_records
    ADD COLUMN approved_at TIMESTAMPTZ DEFAULT now(),
    -- 運行管理者が端末で照合して承認したときの承認者 (自動承認・既存の行は NULL)
    ADD COLUMN approved_by_employee_id UUID,
    -- 承認済みの記録との照合で自動で承認した
    ADD COLUMN auto_approved BOOLEAN NOT NULL DEFAULT false;
