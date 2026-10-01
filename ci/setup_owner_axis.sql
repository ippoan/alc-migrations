-- CI の replay job の「alc_api_app の軸」専用の準備。crate には含めない (scripts/ ではなく ci/ に置く)。
--
-- 本番は、migration を流すロール alc_api_app が alc_api の全表の所有者で、backend は
-- 所有者でない alc_api_rt で繋ぐ。その構成を空の DB に再現するために、init_local_db.sql の後・
-- migration の前に superuser が流す。ここに書いてあるのは、本番で migration の外で
-- 済ませてあること (alc_api_app は CREATEROLE を持たず、schema alc_api の所有者でもない)。
--
--   psql -v ON_ERROR_STOP=1 -v app_password=<CI の使い捨ての値> -f ci/setup_owner_axis.sql

\set ON_ERROR_STOP on

-- migration を流すロール。繋げるようにし、schema に表を作れるようにする。
ALTER ROLE alc_api_app LOGIN PASSWORD :'app_password';
GRANT USAGE, CREATE ON SCHEMA alc_api TO alc_api_app;

-- 実行用ロール。alc_api_app のメンバーにはしない。
CREATE ROLE alc_api_rt LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
GRANT USAGE ON SCHEMA alc_api TO alc_api_rt;
