#!/bin/bash

##############################################
# Script de Verificación OpenProject
# Verifica que todo esté funcionando correctamente
##############################################

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass_count=0
fail_count=0

check_pass() {
    echo -e "${GREEN}[✓]${NC} $1"
    pass_count=$((pass_count + 1))
}

check_fail() {
    echo -e "${RED}[✗]${NC} $1"
    fail_count=$((fail_count + 1))
}

check_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║   VERIFICACIÓN DE INSTALACIÓN OPENPROJECT              ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# 1. VERIFICAR DOCKER
echo "1. Verificando Docker..."
if command -v docker &> /dev/null; then
    check_pass "Docker instalado: $(docker --version)"
else
    check_fail "Docker no instalado"
fi

if docker info &> /dev/null 2>&1; then
    check_pass "Docker está corriendo"
else
    check_fail "Docker no está corriendo"
fi

# 2. VERIFICAR DOCKER COMPOSE
echo ""
echo "2. Verificando Docker Compose..."
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
    check_pass "Docker Compose disponible"
else
    check_fail "Docker Compose no disponible"
fi

# 3. VERIFICAR CONTENEDORES
echo ""
echo "3. Verificando contenedores..."

cd config 2>/dev/null || cd ..

containers=("openproject-db" "openproject-cache" "openproject-app")
for container in "${containers[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        status=$(docker inspect --format='{{.State.Status}}' "$container")
        if [ "$status" == "running" ]; then
            check_pass "Contenedor $container está corriendo"
        else
            check_fail "Contenedor $container existe pero no está corriendo (estado: $status)"
        fi
    else
        check_fail "Contenedor $container no encontrado"
    fi
done

# 4. VERIFICAR PUERTOS
echo ""
echo "4. Verificando puertos..."

if curl -s http://localhost:8080 > /dev/null 2>&1; then
    check_pass "Puerto 8080 responde"
else
    check_fail "Puerto 8080 no responde"
fi

# 5. VERIFICAR SALUD DE SERVICIOS
echo ""
echo "5. Verificando salud de servicios..."

# PostgreSQL
if docker exec openproject-db pg_isready -U openproject &> /dev/null; then
    check_pass "PostgreSQL está saludable"
else
    check_fail "PostgreSQL no responde"
fi

# Redis
if docker exec openproject-cache redis-cli ping &> /dev/null | grep -q "PONG"; then
    check_pass "Redis está saludable"
else
    check_fail "Redis no responde"
fi

# OpenProject
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|302"; then
    check_pass "OpenProject responde HTTP"
else
    check_fail "OpenProject no responde correctamente"
fi

# 6. VERIFICAR VOLUMES
echo ""
echo "6. Verificando volúmenes de datos..."

volumes=("config_pgdata" "config_redis-data" "config_opdata")
for volume in "${volumes[@]}"; do
    if docker volume ls | grep -q "$volume"; then
        check_pass "Volumen $volume existe"
    else
        check_warn "Volumen $volume no encontrado"
    fi
done

# 7. VERIFICAR LOGS DE ERRORES
echo ""
echo "7. Verificando logs..."

if docker-compose logs --tail=100 openproject 2>&1 | grep -qi "error\|failed\|fatal"; then
    check_warn "Se encontraron errores en los logs (revisa con: docker-compose logs openproject)"
else
    check_pass "No se encontraron errores críticos en logs"
fi

# 8. VERIFICAR RECURSOS
echo ""
echo "8. Verificando uso de recursos..."

# Memoria
mem_usage=$(docker stats --no-stream --format "{{.MemUsage}}" openproject-app | cut -d'/' -f1)
check_pass "Uso de memoria OpenProject: $mem_usage"

# Espacio en disco
disk_usage=$(df -h . | awk 'NR==2 {print $5}')
if [ "${disk_usage%\%}" -lt 90 ]; then
    check_pass "Espacio en disco disponible: $disk_usage usado"
else
    check_warn "Poco espacio en disco: $disk_usage usado"
fi

# RESUMEN
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║                    RESUMEN                             ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo -e "  Verificaciones exitosas: ${GREEN}$pass_count${NC}"
echo -e "  Verificaciones fallidas:  ${RED}$fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ Todo está funcionando correctamente!${NC}"
    echo ""
    echo "Acceso a OpenProject:"
    echo "  URL: http://localhost:8080"
    echo "  Usuario: admin"
    echo "  Password: (revisa config/.env)"
    exit 0
else
    echo -e "${RED}✗ Se encontraron $fail_count problemas${NC}"
    echo ""
    echo "Comandos útiles para debugging:"
    echo "  Ver logs:        docker-compose logs -f openproject"
    echo "  Estado:          docker-compose ps"
    echo "  Reintentar:      docker-compose restart"
    echo "  Reconstruir:     docker-compose down && docker-compose up -d"
    exit 1
fi
