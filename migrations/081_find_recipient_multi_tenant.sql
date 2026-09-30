-- find_recipient_by_line_user_id を複数テナント対応に変更 (LIMIT 1 を除去)
-- 同じ LINE user_id が複数テナントの recipient にいる場合にすべて返す

CREATE OR REPLACE FUNCTION alc_api.find_recipient_by_line_user_id(p_line_user_id TEXT)
RETURNS TABLE(tenant_id UUID, recipient_name TEXT)
LANGUAGE sql SECURITY DEFINER SET search_path = alc_api AS $$
  SELECT r.tenant_id, r.name
  FROM alc_api.notify_recipients r
  JOIN alc_api.tenants t ON t.id = r.tenant_id
  WHERE r.line_user_id = p_line_user_id AND r.enabled = TRUE;
$$;
