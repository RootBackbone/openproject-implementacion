#!/bin/bash

##############################################
# Script de Instalación OpenProject
# Proyecto: Calidad de Software - UTP
# Autor: Equipo de Desarrollo
##############################################

set -e  # Detener si hay errores

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
print_message() {
    echo -e "${BLUE}[OpenProject]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║   INSTALACIÓN DE OPENPROJECT                           ║"
echo "║   Universidad Tecnológica del Perú                     ║"
echo "║   Curso: Calidad de Software                           ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Verificar si se ejecuta como root (no recomendado)
if [ "$EUID" -eq 0 ]; then 
    print_warning "No se recomienda ejecutar como root. Continuando..."
fi

# 1. VERIFICAR REQUISITOS
print_message "Paso 1/7: Verificando requisitos del sistema..."

# Verificar Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker no está instalado"
    echo ""
    echo "Por favor instala Docker primero:"
    echo "  - Linux: https://docs.docker.com/engine/install/"
    echo "  - Mac: https://docs.docker.com/desktop/mac/install/"
    echo "  - Windows: https://docs.docker.com/desktop/windows/install/"
    exit 1
fi
print_success "Docker instalado: $(docker --version)"

# Verificar Docker Compose
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose no está instalado"
    exit 1
fi
print_success "Docker Compose disponible"

# Verificar Docker está corriendo
if ! docker info &> /dev/null; then
    print_error "Docker no está corriendo. Inicia Docker Desktop primero."
    exit 1
fi
print_success "Docker está corriendo"

# Verificar puertos disponibles
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":8080 "; then
    print_error "El puerto 8080 ya está en uso"
    echo "Por favor detén el servicio que usa el puerto 8080"
    exit 1
fi
print_success "Puerto 8080 disponible"

# 2. CREAR ESTRUCTURA DE DIRECTORIOS
print_message "Paso 2/7: Creando estructura de directorios..."

INSTALL_DIR="$PWD"
mkdir -p config backups logs data
print_success "Directorios creados"

# 3. VERIFICAR ARCHIVO .env
print_message "Paso 3/7: Verificando configuración..."

if [ ! -f "config/.env" ]; then
    print_warning "Archivo .env no encontrado, creando uno por defecto..."
    
    cat > config/.env << 'EOF'
# Configuración OpenProject
OPENPROJECT_HOST=localhost:8080
DB_PASSWORD=openproject_pass_2026
ADMIN_PASSWORD=Admin2026!
ADMIN_EMAIL=admin@ejemplo.com

# Email (opcional)
EMAIL_METHOD=
SMTP_ADDRESS=
SMTP_PORT=
SMTP_USER=
SMTP_PASS=

# GitHub (configurar después)
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
EOF
    
    print_success "Archivo .env creado. Por favor revísalo y modifícalo si es necesario."
    print_warning "Presiona Enter para continuar..."
    read
fi

# 4. DESCARGAR IMÁGENES DOCKER
print_message "Paso 4/7: Descargando imágenes Docker..."
print_warning "Esto puede tardar varios minutos dependiendo de tu conexión..."

cd config
docker-compose pull
print_success "Imágenes descargadas"

# 5. INICIAR SERVICIOS
print_message "Paso 5/7: Iniciando servicios..."
print_warning "Primera vez puede tardar 5-10 minutos en inicializar..."

docker-compose up -d

# 6. ESPERAR A QUE OPENPROJECT ESTÉ LISTO
print_message "Paso 6/7: Esperando a que OpenProject esté listo..."

max_attempts=60
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if docker-compose ps | grep -q "openproject-app.*Up"; then
        if curl -s http://localhost:8080 > /dev/null 2>&1; then
            print_success "OpenProject está listo!"
            break
        fi
    fi
    
    attempt=$((attempt + 1))
    echo -n "."
    sleep 5
done

echo ""

if [ $attempt -eq $max_attempts ]; then
    print_error "Timeout esperando a OpenProject"
    print_message "Verificando logs..."
    docker-compose logs --tail=50 openproject
    exit 1
fi

# 7. VERIFICACIÓN FINAL
print_message "Paso 7/7: Verificación final..."

# Verificar contenedores
if [ $(docker-compose ps | grep "Up" | wc -l) -eq 3 ]; then
    print_success "Todos los contenedores están corriendo"
else
    print_error "Algunos contenedores no están corriendo"
    docker-compose ps
fi

# Verificar conectividad
if curl -s http://localhost:8080 > /dev/null; then
    print_success "OpenProject es accesible vía web"
else
    print_warning "OpenProject puede tardar unos minutos más en estar disponible"
fi

cd "$INSTALL_DIR"

# RESUMEN FINAL
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║            ✓ INSTALACIÓN COMPLETADA                    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
print_success "OpenProject está corriendo!"
echo ""
echo "📍 Acceso:"
echo "   URL:      http://localhost:8080"
echo "   Usuario:  admin"
echo "   Password: (revisa config/.env)"
echo ""
echo "🔧 Comandos útiles:"
echo "   Ver logs:     cd config && docker-compose logs -f"
echo "   Detener:      cd config && docker-compose stop"
echo "   Reiniciar:    cd config && docker-compose restart"
echo "   Eliminar:     cd config && docker-compose down"
echo ""
echo "📚 Próximos pasos:"
echo "   1. Accede a http://localhost:8080"
echo "   2. Inicia sesión con admin"
echo "   3. Cambia la contraseña"
echo "   4. Crea tu primer proyecto"
echo ""
print_message "¡Instalación exitosa! 🎉"
echo ""
