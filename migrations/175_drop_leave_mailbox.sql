-- 休暇申請のメール受信をやめたので、受信アドレス・差出人の列と、それを引く関数を落とす (contract)。
-- 画面・back・送り手はもう使わない。UNIQUE・CHECK は列と一緒に消える。
-- leave_pages / leave_documents の mail_from・subject (過去の行の履歴) は残す。
ALTER TABLE alc_api.leave_settings DROP COLUMN mailbox, DROP COLUMN allowed_senders;
DROP FUNCTION alc_api.leave_resolve_mailbox(text);
