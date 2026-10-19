-- notify_recipients: provider に 'email' (メールだけの宛先) を足す。
-- LINE / LINE WORKS の ID を持たず、メールアドレスだけを持つ人をアルコール検知メールの受け取り手にするため
-- (Refs ippoan/alc-app#436)。CHECK を緩めるだけで、既存の行は全部新しい制約を満たす。

-- 069 の provider の CHECK は名前なしの列制約 (自動名 notify_recipients_provider_check)
ALTER TABLE alc_api.notify_recipients DROP CONSTRAINT IF EXISTS notify_recipients_provider_check;
ALTER TABLE alc_api.notify_recipients ADD CONSTRAINT notify_recipients_provider_check
    CHECK (provider IN ('lineworks', 'line', 'email'));

ALTER TABLE alc_api.notify_recipients DROP CONSTRAINT IF EXISTS at_least_one_messaging_id;
ALTER TABLE alc_api.notify_recipients ADD CONSTRAINT at_least_one_messaging_id
    CHECK (
        lineworks_user_id IS NOT NULL
        OR line_user_id IS NOT NULL
        OR (provider = 'email' AND email IS NOT NULL AND btrim(email) <> '')
    );
