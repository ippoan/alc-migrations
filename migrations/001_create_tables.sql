-- Tenants (事業所)
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Employees (乗務員)
CREATE TABLE employees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    nfc_id TEXT NOT NULL,
    name TEXT NOT NULL,
    face_photo_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, nfc_id)
);

CREATE INDEX idx_employees_tenant ON employees(tenant_id);
CREATE INDEX idx_employees_nfc ON employees(tenant_id, nfc_id);

-- Measurements (測定結果)
CREATE TABLE measurements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    employee_id UUID NOT NULL REFERENCES employees(id),
    alcohol_level DOUBLE PRECISION NOT NULL,
    result TEXT NOT NULL CHECK (result IN ('pass', 'fail')),
    face_photo_url TEXT,
    measured_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_measurements_tenant ON measurements(tenant_id);
CREATE INDEX idx_measurements_employee ON measurements(employee_id);
CREATE INDEX idx_measurements_measured_at ON measurements(tenant_id, measured_at DESC);
