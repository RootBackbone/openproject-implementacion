#!/bin/bash

##############################################
# Script de Backup OpenProject
# Realiza backup de base de datos y configuraciones
##############################################

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}[Backup]${NC} Iniciando backup de OpenProject..."

# Configuración
BACKUP_DIR="backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="openproject_backup_${DATE}"
RETENTION_DAYS=7

# Crear directorio de backups
mkdir -p "$BACKUP_DIR/$BACKUP_NAME"

cd config 2>/dev/null || cd ..

# 1. BACKUP DE BASE DE DATOS
echo -e "${BLUE}[Backup]${NC} Respaldando base de datos PostgreSQL..."

docker exec openproject-db pg_dump -U openproject openproject > "$BACKUP_DIR/$BACKUP_NAME/database.sql"

if [ -f "$BACKUP_DIR/$BACKUP_NAME/database.sql" ]; then
    SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME/database.sql" | cut -f1)
    echo -e "${GREEN}[✓]${NC} Base de datos respaldada ($SIZE)"
else
    echo -e "${RED}[✗]${NC} Error al respaldar base de datos"
    exit 1
fi

# 2. BACKUP DE CONFIGURACIÓN
echo -e "${BLUE}[Backup]${NC} Respaldando configuraciones..."

# Copiar .env (sin contraseñas sensibles en logs)
if [ -f "config/.env" ]; then
    cp config/.env "$BACKUP_DIR/$BACKUP_NAME/env_backup"
    echo -e "${GREEN}[✓]${NC} Archivo .env respaldado"
fi

# Copiar docker-compose.yml
if [ -f "config/docker-compose.yml" ]; then
    cp config/docker-compose.yml "$BACKUP_DIR/$BACKUP_NAME/"
    echo -e "${GREEN}[✓]${NC} docker-compose.yml respaldado"
fi

# 3. BACKUP DE VOLÚMENES (opcional, tarda más)
echo -e "${BLUE}[Backup]${NC} Respaldando datos de OpenProject..."

docker run --rm \
    -v config_opdata:/data \
    -v $(pwd)/$BACKUP_DIR/$BACKUP_NAME:/backup \
    alpine tar czf /backup/opdata.tar.gz -C /data .

if [ -f "$BACKUP_DIR/$BACKUP_NAME/opdata.tar.gz" ]; then
    SIZE=$(du -h "$BACKUP_DIR/$BACKUP_NAME/opdata.tar.gz" | cut -f1)
    echo -e "${GREEN}[✓]${NC} Datos OpenProject respaldados ($SIZE)"
fi

# 4. COMPRIMIR TODO
echo -e "${BLUE}[Backup]${NC} Comprimiendo backup completo..."

cd "$BACKUP_DIR"
tar -czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

TOTAL_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
echo -e "${GREEN}[✓]${NC} Backup comprimido: ${BACKUP_NAME}.tar.gz ($TOTAL_SIZE)"

# 5. LIMPIAR BACKUPS ANTIGUOS
echo -e "${BLUE}[Backup]${NC} Limpiando backups antiguos (>${RETENTION_DAYS} días)..."

find . -name "openproject_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete

BACKUP_COUNT=$(ls -1 openproject_backup_*.tar.gz 2>/dev/null | wc -l)
echo -e "${GREEN}[✓]${NC} Backups actuales: $BACKUP_COUNT"

cd ..

# RESUMEN
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║              BACKUP COMPLETADO                         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "  Archivo: $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "  Tamaño:  $TOTAL_SIZE"
echo "  Fecha:   $(date)"
echo ""
echo "Para restaurar:"
echo "  1. Detener OpenProject: cd config && docker-compose down"
echo "  2. Extraer backup: tar -xzf $BACKUP_DIR/${BACKUP_NAME}.tar.gz"
echo "  3. Restaurar DB: docker exec -i openproject-db psql -U openproject < database.sql"
echo "  4. Reiniciar: docker-compose up -d"
echo ""
