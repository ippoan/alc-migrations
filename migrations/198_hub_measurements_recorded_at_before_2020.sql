-- 端末の時計が合う前に記録された hub_measurements の recorded_at (1970 起点) を NULL にする
--
-- CoreS3 は時計が合う前の記録を 1970 起点の稼働時間で送り、取り込みはそれをそのまま保存していた。
-- 打刻の一覧は COALESCE(recorded_at, created_at) を打刻の時刻にするので、こうした打刻は 1970 年の扱いに
-- なって日付の絞り込みから消えていた。people-worker の取り込みは 2020-01-01 より前の端末の時刻を
-- 捨てて NULL にするようになった (ippoan/alc-people-worker#7)。既存の行も同じ形にそろえる。
--
-- * NULL の行は受信の時刻 (created_at) で読まれ、API は時刻の出どころを `received` と返す
-- * 2020 年より前の値は端末の稼働時間で、実時刻には直せない (起動の時刻を持っていない)
-- * 表の所有者で流すので RLS は効かない (hub_measurements は FORCE でない)。dev の軸の行も対象

SET LOCAL lock_timeout = '10s';

UPDATE alc_api.hub_measurements
   SET recorded_at = NULL
 WHERE recorded_at < TIMESTAMPTZ '2020-01-01 00:00:00+00';
