-- 指静脈の認証ログに、撮影したときに照合の相手にした本人の記録を残す (足すだけ。Refs ippoan/alc-app-s3#352)
--
-- 照合が通ると端末はその撮影で本人の記録を入れ替える (rotate) ので、後から今の記録で判定し直すと、
-- 撮影が自分自身と照合されて甘く出る。判定し直しは、ここに残した撮影したときの記録を本人の相手にする
-- (閾値と計算の違いだけを比べるため)。worker が撮影と同じ鍵で暗号化してから書く。
-- 202 の行 (この列が入る前に保存した撮影) は NULL で、worker は今の記録で判定する。
ALTER TABLE alc_api.vein_auth_shots ADD COLUMN enroll_encrypted TEXT NULL;
