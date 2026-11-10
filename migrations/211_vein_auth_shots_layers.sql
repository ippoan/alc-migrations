-- 指静脈の認証ログに、モジュールの照合が通した層と規則を残す (足すだけ。Refs ippoan/alc-app-s3#352)
--
-- 2026-11-10 に指静脈の取り違えが起きた。後から検証できるよう、ファームが照合の行に
-- RULE / FV / FP / FVSCORE を出す。静脈の層 (FV) と指紋互換の層 (FP) がそれぞれ当てたモジュールの枠 ID、
-- FV が返した ID と違えばその点数、どの層で通したか (via) と規則 (rule) を、認証のたびに残す。
-- 古い端末は送らないので、どれも NULL。
ALTER TABLE alc_api.vein_auth_shots
    ADD COLUMN module_via TEXT NULL,
    ADD COLUMN module_rule TEXT NULL,
    ADD COLUMN module_fv_slot INT NULL,
    ADD COLUMN module_fp_slot INT NULL,
    ADD COLUMN module_fv_score INT NULL;
