-- ====================================================================
-- ACTUALIZACIÓN DE BASE DE DATOS: LÍNEA LOS ANDES / ENCOMIENDAS
-- ====================================================================
-- Instrucciones:
-- 1. Ve al panel de control de Supabase (https://supabase.com/dashboard)
-- 2. Selecciona tu proyecto
-- 3. Entra en "SQL Editor" en el menú izquierdo
-- 4. Haz clic en "New Query", pega todo este contenido y presiona "Run"
-- ====================================================================

-- 1. AGREGAR DOMICILIO FISCAL EN LA TABLA PERSONA
-- (Permite guardar el domicilio fiscal tanto de remitentes como destinatarios)
ALTER TABLE persona 
ADD COLUMN IF NOT EXISTS domicilio_fiscal TEXT;

-- 2. CREAR O VERIFICAR TABLA DE CONDUCTORES
CREATE TABLE IF NOT EXISTS conductor (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cedula VARCHAR(50) UNIQUE NOT NULL,
    nombres VARCHAR(100) NOT NULL,
    apellidos VARCHAR(100) NOT NULL,
    licencia VARCHAR(50),
    telefono VARCHAR(50),
    empresa_id UUID,
    activo BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Si la tabla conductor ya existía previamente con empresa_id NOT NULL, relajar la restricción
DO $$
BEGIN
    ALTER TABLE conductor ALTER COLUMN empresa_id DROP NOT NULL;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

-- Asegurar índices para búsqueda rápida por cédula
CREATE INDEX IF NOT EXISTS idx_persona_cedula ON persona(cedula);
CREATE INDEX IF NOT EXISTS idx_conductor_cedula ON conductor(cedula);

-- Habilitar permisos de lectura y escritura en la tabla persona para Supabase
ALTER TABLE persona ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Permitir lectura persona" ON persona;
CREATE POLICY "Permitir lectura persona" ON persona FOR SELECT USING (true);
DROP POLICY IF EXISTS "Permitir insercion persona" ON persona;
CREATE POLICY "Permitir insercion persona" ON persona FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Permitir actualizacion persona" ON persona;
CREATE POLICY "Permitir actualizacion persona" ON persona FOR UPDATE USING (true);
GRANT ALL ON persona TO anon, authenticated, service_role;

-- Habilitar permisos de lectura y escritura en la tabla conductor para Supabase
ALTER TABLE conductor ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir lectura publica conductores" ON conductor;
CREATE POLICY "Permitir lectura publica conductores" 
ON conductor FOR SELECT 
USING (true);

DROP POLICY IF EXISTS "Permitir insercion conductores" ON conductor;
CREATE POLICY "Permitir insercion conductores" 
ON conductor FOR INSERT 
WITH CHECK (true);

DROP POLICY IF EXISTS "Permitir actualizacion conductores" ON conductor;
CREATE POLICY "Permitir actualizacion conductores" 
ON conductor FOR UPDATE 
USING (true);

GRANT ALL ON conductor TO anon, authenticated, service_role;

-- 3. AGREGAR NUEVOS CAMPOS A LA TABLA ENCOMIENDA
-- Datos del Envío: Unidad, Conductor, Hora del Envío y Domicilios Fiscales históricos
ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS unidad VARCHAR(100);

ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS conductor_id UUID;

-- Eliminar la restricción de llave foránea estricta a 'conductor' para que acepte tanto choferes como conductores
DO $$
BEGIN
    ALTER TABLE encomienda DROP CONSTRAINT IF EXISTS encomienda_conductor_id_fkey;
EXCEPTION
    WHEN OTHERS THEN NULL;
END $$;

ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS conductor_cedula VARCHAR(50);

ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS conductor_nombre VARCHAR(150);

ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS hora_envio TIME DEFAULT CURRENT_TIME;

ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS remitente_domicilio_fiscal TEXT;

ALTER TABLE encomienda 
ADD COLUMN IF NOT EXISTS destinatario_domicilio_fiscal TEXT;

CREATE INDEX IF NOT EXISTS idx_encomienda_conductor_cedula ON encomienda(conductor_cedula);
CREATE INDEX IF NOT EXISTS idx_encomienda_unidad ON encomienda(unidad);

-- 4. INSERTAR CONDUCTORES DE PRUEBA (EJEMPLOS DE LÍNEA LOS ANDES)
-- Para que puedas probar inmediatamente la búsqueda de conductor por cédula
DO $$
DECLARE
    v_empresa_id UUID;
BEGIN
    -- Obtener la empresa asociada por defecto si existe en el sistema
    BEGIN
        SELECT id INTO v_empresa_id FROM empresa LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
        v_empresa_id := NULL;
    END;

    INSERT INTO conductor (cedula, nombres, apellidos, telefono, licencia, activo, empresa_id)
    VALUES 
        ('V-12345678', 'José Gregorio', 'Ramírez Peña', '+58 414 123 4567', '5ta-123456', true, v_empresa_id),
        ('V-18765432', 'Carlos Alberto', 'Mendoza Castillo', '+58 412 987 6543', '5ta-654321', true, v_empresa_id),
        ('V-14567890', 'Pedro Antonio', 'Gómez Rivas', '+58 416 555 4321', '5ta-987123', true, v_empresa_id),
        ('V-20123456', 'Luis Eduardo', 'Hernández Mora', '+58 424 333 2211', '5ta-456789', true, v_empresa_id)
    ON CONFLICT (cedula) DO UPDATE 
    SET 
        nombres = EXCLUDED.nombres,
        apellidos = EXCLUDED.apellidos,
        telefono = EXCLUDED.telefono,
        licencia = EXCLUDED.licencia,
        empresa_id = COALESCE(conductor.empresa_id, EXCLUDED.empresa_id);
END $$;

-- 5. ACTUALIZAR LA VISTA v_encomiendas_detalle CON LOS NUEVOS CAMPOS
-- En PostgreSQL se debe eliminar la vista anterior si cambian el orden o nombre de columnas
DROP VIEW IF EXISTS v_encomiendas_detalle CASCADE;

CREATE VIEW v_encomiendas_detalle AS
SELECT 
    e.id,
    e.codigo_rastreo,
    e.viaje_id,
    e.remitente_id,
    e.destinatario_id,
    e.registrado_por,
    e.tipo,
    e.peso_kg,
    e.descripcion,
    e.costo_base,
    e.costo_peso,
    e.total,
    e.estado,
    e.fecha_registro,
    e.fecha_entrega,
    e.observaciones,
    
    -- Datos y Domicilio Fiscal del Remitente
    TRIM(pr.nombres || ' ' || COALESCE(pr.apellidos, '')) AS remitente_nombre,
    pr.cedula AS remitente_cedula,
    pr.telefono AS remitente_telefono,
    COALESCE(e.remitente_domicilio_fiscal, pr.domicilio_fiscal) AS remitente_domicilio_fiscal,
    
    -- Datos y Domicilio Fiscal del Destinatario
    TRIM(pd.nombres || ' ' || COALESCE(pd.apellidos, '')) AS destinatario_nombre,
    pd.cedula AS destinatario_cedula,
    pd.telefono AS destinatario_telefono,
    COALESCE(e.destinatario_domicilio_fiscal, pd.domicilio_fiscal) AS destinatario_domicilio_fiscal,
    
    -- Datos del Envío: Unidad, Conductor y Hora
    COALESCE(e.unidad, b.nombre, b.codigo) AS unidad,
    b.codigo AS bus_codigo,
    b.nombre AS bus_nombre,
    b.placa AS bus_placa,
    
    COALESCE(e.conductor_cedula, c.cedula) AS conductor_cedula,
    COALESCE(e.conductor_nombre, TRIM(c.nombres || ' ' || COALESCE(c.apellidos, ''))) AS conductor_nombre,
    COALESCE(e.hora_envio, e.fecha_registro::time) AS hora_envio,
    
    -- Ruta y terminales
    t_orig.ciudad AS ciudad_origen,
    t_dest.ciudad AS ciudad_destino,
    (t_orig.ciudad || ' → ' || t_dest.ciudad) AS ruta_label,
    
    -- Pago
    p.metodo AS pago_metodo,
    p.estado AS pago_estado
FROM encomienda e
LEFT JOIN persona pr ON pr.id = e.remitente_id
LEFT JOIN persona pd ON pd.id = e.destinatario_id
LEFT JOIN viaje v ON v.id = e.viaje_id
LEFT JOIN bus b ON b.id = v.bus_id
LEFT JOIN ruta r ON r.id = v.ruta_id
LEFT JOIN terminal t_orig ON t_orig.id = r.terminal_origen_id
LEFT JOIN terminal t_dest ON t_dest.id = r.terminal_destino_id
LEFT JOIN conductor c ON c.id = COALESCE(e.conductor_id, v.conductor_id)
LEFT JOIN (
    SELECT DISTINCT ON (encomienda_id) encomienda_id, metodo, estado 
    FROM pago 
    ORDER BY encomienda_id, fecha_pago DESC
) p ON p.encomienda_id = e.id;

-- Permisos sobre la vista
GRANT SELECT ON v_encomiendas_detalle TO anon, authenticated, service_role;

-- 6. RECARGAR EL CACHÉ DE POSTGREST EN SUPABASE
NOTIFY pgrst, 'reload schema';
