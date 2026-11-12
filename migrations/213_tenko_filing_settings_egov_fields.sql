-- 点呼の届出の「書き込む値」に、e-Gov の申請データと突き合わせる欄を足す (足すだけ。Refs ippoan/alc-app#676)
--
-- 管理画面 (alc-app の「点呼の届出」) は、e-Gov の申請データ (一時保存・申請済みの控えの zip) を読んで、
-- 保存した値と食い違いが無いかを確かめる。e-Gov の構成情報 (kousei.xml) の申請者情報・連絡先情報と、
-- 受委託の許可申請の委託者・受託者に入る値のうち、今の表 (201) に無いものを足す。
-- 読み書きは alc-tenko-worker (`/api/tenko/filing-settings`、admin だけ)。
--
-- * operator_kana: 届け出る事業者の名称のフリガナ。operator_address_kana: 住所のフリガナ
-- * operator_postal_code: 郵便番号 (半角数字 7 桁、ハイフンなし)。operator_phone: 事業者の電話番号
-- * operator_corporate_number: 法人番号 (半角数字 13 桁)
-- * operator_representative_kana / operator_representative_title: 代表者氏名のフリガナと役職
-- * operator_contact_kana / operator_contact_dept: 担当者氏名のフリガナと部門名
-- * operator_contact_postal_code / operator_contact_address: 担当者の郵便番号と住所 (事業者と違うときだけ入れる)
-- * partners: 受委託の相手の会社の配列。要素は {name, address, representative, offices: [{name, address}]}
--   (事業者間遠隔点呼の受委託の許可申請の委託者・受託者)。要素の形は worker が検める
--
-- 列を足すだけなので RLS・権限は 201 のまま。
ALTER TABLE alc_api.tenko_filing_settings
    ADD COLUMN operator_kana TEXT NULL,
    ADD COLUMN operator_address_kana TEXT NULL,
    ADD COLUMN operator_postal_code TEXT NULL CHECK (operator_postal_code ~ '^[0-9]{7}$'),
    ADD COLUMN operator_phone TEXT NULL,
    ADD COLUMN operator_corporate_number TEXT NULL CHECK (operator_corporate_number ~ '^[0-9]{13}$'),
    ADD COLUMN operator_representative_kana TEXT NULL,
    ADD COLUMN operator_representative_title TEXT NULL,
    ADD COLUMN operator_contact_kana TEXT NULL,
    ADD COLUMN operator_contact_dept TEXT NULL,
    ADD COLUMN operator_contact_postal_code TEXT NULL CHECK (operator_contact_postal_code ~ '^[0-9]{7}$'),
    ADD COLUMN operator_contact_address TEXT NULL,
    ADD COLUMN partners JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(partners) = 'array');
