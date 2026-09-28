-- ====================================================================
-- NUEVAS TABLAS: CHOFER Y UNIDAD — LÍNEA LOS ANDES
-- ====================================================================
-- Instrucciones:
-- 1. Ve al panel de control de Supabase (https://supabase.com/dashboard)
-- 2. Selecciona tu proyecto
-- 3. Entra en "SQL Editor" en el menú izquierdo
-- 4. Haz clic en "New Query", pega todo este contenido y presiona "Run"
-- ====================================================================

-- ────────────────────────────────────────────────────────
-- 1. TABLA: chofer
--    Gestión completa de conductores/choferes de la línea
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chofer (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cedula      VARCHAR(50)  UNIQUE NOT NULL,
    nombres     VARCHAR(100) NOT NULL,
    apellidos   VARCHAR(100) NOT NULL,
    telefono    VARCHAR(50),
    correo      VARCHAR(150),
    licencia    VARCHAR(80),
    domicilio   TEXT,
    activo      BOOLEAN DEFAULT true,
    empresa_id  UUID,
    created_at  TIMESTAMPTZ DEFAULT now(),
    updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Relajar NOT NULL en empresa_id si ya existía con esa restricción
DO $$
BEGIN
    ALTER TABLE chofer ALTER COLUMN empresa_id DROP NOT NULL;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Índices
CREATE INDEX IF NOT EXISTS idx_chofer_cedula    ON chofer(cedula);
CREATE INDEX IF NOT EXISTS idx_chofer_apellidos ON chofer(apellidos);
CREATE INDEX IF NOT EXISTS idx_chofer_activo    ON chofer(activo);

-- Trigger para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_chofer_updated_at ON chofer;
CREATE TRIGGER trg_chofer_updated_at
    BEFORE UPDATE ON chofer
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS
ALTER TABLE chofer ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "chofer_select" ON chofer;
CREATE POLICY "chofer_select" ON chofer FOR SELECT USING (true);

DROP POLICY IF EXISTS "chofer_insert" ON chofer;
CREATE POLICY "chofer_insert" ON chofer FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "chofer_update" ON chofer;
CREATE POLICY "chofer_update" ON chofer FOR UPDATE USING (true);

DROP POLICY IF EXISTS "chofer_delete" ON chofer;
CREATE POLICY "chofer_delete" ON chofer FOR DELETE USING (true);

GRANT ALL ON chofer TO anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────
-- 2. TABLA: unidad
--    Gestión completa de vehículos/unidades de la línea
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS unidad (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_unidad  VARCHAR(50)  UNIQUE NOT NULL,
    placa          VARCHAR(20)  UNIQUE NOT NULL,
    tipo           VARCHAR(50)  NOT NULL DEFAULT 'Bus',
    num_puestos    INTEGER,
    prop_cedula    VARCHAR(50),
    prop_nombres   VARCHAR(100),
    prop_apellidos VARCHAR(100),
    prop_telefono  VARCHAR(50),
    activo         BOOLEAN DEFAULT true,
    empresa_id     UUID,
    created_at     TIMESTAMPTZ DEFAULT now(),
    updated_at     TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT chk_unidad_tipo CHECK (tipo IN ('Bus','Minibus','Van','Camion','Otro'))
);

-- Relajar NOT NULL en empresa_id si ya existía con esa restricción
DO $$
BEGIN
    ALTER TABLE unidad ALTER COLUMN empresa_id DROP NOT NULL;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Índices
CREATE INDEX IF NOT EXISTS idx_unidad_numero  ON unidad(numero_unidad);
CREATE INDEX IF NOT EXISTS idx_unidad_placa   ON unidad(placa);
CREATE INDEX IF NOT EXISTS idx_unidad_tipo    ON unidad(tipo);
CREATE INDEX IF NOT EXISTS idx_unidad_activo  ON unidad(activo);

-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_unidad_updated_at ON unidad;
CREATE TRIGGER trg_unidad_updated_at
    BEFORE UPDATE ON unidad
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS
ALTER TABLE unidad ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "unidad_select" ON unidad;
CREATE POLICY "unidad_select" ON unidad FOR SELECT USING (true);

DROP POLICY IF EXISTS "unidad_insert" ON unidad;
CREATE POLICY "unidad_insert" ON unidad FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "unidad_update" ON unidad;
CREATE POLICY "unidad_update" ON unidad FOR UPDATE USING (true);

DROP POLICY IF EXISTS "unidad_delete" ON unidad;
CREATE POLICY "unidad_delete" ON unidad FOR DELETE USING (true);

GRANT ALL ON unidad TO anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────
-- 3. MIGRACIÓN: tabla conductor → tabla chofer
--    Si ya tenías conductores en la tabla "conductor",
--    copia los registros a la nueva tabla "chofer".
-- ────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'conductor' AND table_schema = 'public') THEN
        INSERT INTO chofer (cedula, nombres, apellidos, telefono, licencia, activo, empresa_id, created_at)
        SELECT cedula, nombres, apellidos, telefono, licencia, activo, empresa_id, created_at
        FROM conductor
        ON CONFLICT (cedula) DO UPDATE
        SET
            nombres    = EXCLUDED.nombres,
            apellidos  = EXCLUDED.apellidos,
            telefono   = EXCLUDED.telefono,
            licencia   = EXCLUDED.licencia,
            empresa_id = COALESCE(chofer.empresa_id, EXCLUDED.empresa_id);
        RAISE NOTICE 'Registros de conductor migrados a chofer.';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Tabla conductor no existe o migración no necesaria: %', SQLERRM;
END $$;


-- ────────────────────────────────────────────────────────
-- 4. COMPATIBILIDAD CON TABLA ENCOMIENDA
-- ────────────────────────────────────────────────────────
-- Si encomienda tiene una llave foránea estricta apuntando a 'conductor',
-- la eliminamos para permitir IDs tanto de 'chofer' como 'conductor'.
DO $$
BEGIN
    ALTER TABLE encomienda DROP CONSTRAINT IF EXISTS encomienda_conductor_id_fkey;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Asegurar que la columna unidad exista en encomienda
ALTER TABLE encomienda ADD COLUMN IF NOT EXISTS unidad VARCHAR(100);
ALTER TABLE encomienda ADD COLUMN IF NOT EXISTS conductor_cedula VARCHAR(50);
ALTER TABLE encomienda ADD COLUMN IF NOT EXISTS conductor_nombre VARCHAR(150);


-- ────────────────────────────────────────────────────────
-- 5. RECARGAR CACHÉ DE POSTGREST
-- ────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';

