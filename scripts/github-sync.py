#!/usr/bin/env python3
"""
Script de Sincronización GitHub <-> OpenProject
Sincroniza Issues de GitHub con Work Packages de OpenProject
"""

import os
import sys
import requests
import json
from datetime import datetime
from typing import Dict, List, Optional

# Configuración
GITHUB_TOKEN = os.getenv('GITHUB_TOKEN', '')
GITHUB_REPO = os.getenv('GITHUB_REPO', '')  # formato: "owner/repo"
OPENPROJECT_URL = os.getenv('OPENPROJECT_URL', 'http://localhost:8080')
OPENPROJECT_API_KEY = os.getenv('OPENPROJECT_API_KEY', '')

# Headers para APIs
GITHUB_HEADERS = {
    'Authorization': f'token {GITHUB_TOKEN}',
    'Accept': 'application/vnd.github.v3+json'
}

OPENPROJECT_HEADERS = {
    'Authorization': f'Basic {OPENPROJECT_API_KEY}',
    'Content-Type': 'application/json'
}


class GitHubSync:
    """Clase para sincronizar GitHub Issues con OpenProject"""
    
    def __init__(self):
        self.github_api = f"https://api.github.com/repos/{GITHUB_REPO}"
        self.op_api = f"{OPENPROJECT_URL}/api/v3"
        self.project_id = None
        
    def validate_config(self) -> bool:
        """Valida que la configuración esté completa"""
        if not GITHUB_TOKEN:
            print("❌ Error: GITHUB_TOKEN no configurado")
            return False
        if not GITHUB_REPO:
            print("❌ Error: GITHUB_REPO no configurado")
            return False
        if not OPENPROJECT_API_KEY:
            print("❌ Error: OPENPROJECT_API_KEY no configurado")
            return False
        return True
    
    def get_github_issues(self) -> List[Dict]:
        """Obtiene todos los issues de GitHub"""
        print(f"📥 Obteniendo issues de {GITHUB_REPO}...")
        
        url = f"{self.github_api}/issues"
        params = {'state': 'all', 'per_page': 100}
        
        try:
            response = requests.get(url, headers=GITHUB_HEADERS, params=params)
            response.raise_for_status()
            issues = response.json()
            print(f"✓ Se encontraron {len(issues)} issues")
            return issues
        except requests.exceptions.RequestException as e:
            print(f"❌ Error al obtener issues: {e}")
            return []
    
    def get_openproject_work_packages(self, project_id: int) -> List[Dict]:
        """Obtiene todos los work packages de OpenProject"""
        print(f"📥 Obteniendo work packages del proyecto {project_id}...")
        
        url = f"{self.op_api}/projects/{project_id}/work_packages"
        
        try:
            response = requests.get(url, headers=OPENPROJECT_HEADERS)
            response.raise_for_status()
            data = response.json()
            packages = data.get('_embedded', {}).get('elements', [])
            print(f"✓ Se encontraron {len(packages)} work packages")
            return packages
        except requests.exceptions.RequestException as e:
            print(f"❌ Error al obtener work packages: {e}")
            return []
    
    def create_work_package(self, project_id: int, issue: Dict) -> Optional[Dict]:
        """Crea un work package desde un issue de GitHub"""
        
        url = f"{self.op_api}/work_packages"
        
        # Mapear estado de GitHub a OpenProject
        status_map = {
            'open': 1,      # New
            'closed': 12    # Closed
        }
        
        payload = {
            "_links": {
                "project": {
                    "href": f"/api/v3/projects/{project_id}"
                },
                "type": {
                    "href": "/api/v3/types/1"  # Task
                },
                "status": {
                    "href": f"/api/v3/statuses/{status_map.get(issue['state'], 1)}"
                }
            },
            "subject": issue['title'],
            "description": {
                "raw": f"{issue['body']}\n\n---\nGitHub Issue: {issue['html_url']}"
            }
        }
        
        try:
            response = requests.post(url, headers=OPENPROJECT_HEADERS, json=payload)
            response.raise_for_status()
            wp = response.json()
            print(f"  ✓ Creado WP #{wp['id']}: {issue['title'][:50]}...")
            return wp
        except requests.exceptions.RequestException as e:
            print(f"  ❌ Error creando WP: {e}")
            if hasattr(e.response, 'text'):
                print(f"     Respuesta: {e.response.text}")
            return None
    
    def sync_issues_to_workpackages(self, project_id: int):
        """Sincroniza issues de GitHub a OpenProject"""
        print("\n🔄 Iniciando sincronización GitHub → OpenProject")
        print("=" * 60)
        
        # Obtener issues de GitHub
        issues = self.get_github_issues()
        if not issues:
            print("No hay issues para sincronizar")
            return
        
        # Obtener work packages existentes
        work_packages = self.get_openproject_work_packages(project_id)
        existing_titles = {wp['subject'] for wp in work_packages}
        
        # Crear work packages para issues nuevos
        created = 0
        skipped = 0
        
        for issue in issues:
            # Ignorar pull requests (GitHub los devuelve como issues)
            if 'pull_request' in issue:
                continue
            
            # Verificar si ya existe
            if issue['title'] in existing_titles:
                skipped += 1
                continue
            
            # Crear work package
            if self.create_work_package(project_id, issue):
                created += 1
        
        print("\n" + "=" * 60)
        print(f"✓ Sincronización completada:")
        print(f"  - Creados: {created}")
        print(f"  - Omitidos (ya existen): {skipped}")
        print(f"  - Total procesados: {len(issues)}")
    
    def setup_webhook(self) -> bool:
        """Configura webhook en GitHub para sincronización automática"""
        print("\n🔗 Configurando webhook en GitHub...")
        
        url = f"{self.github_api}/hooks"
        
        payload = {
            "name": "web",
            "active": True,
            "events": ["issues", "issue_comment"],
            "config": {
                "url": f"{OPENPROJECT_URL}/webhooks/github",
                "content_type": "json",
                "insecure_ssl": "1"
            }
        }
        
        try:
            response = requests.post(url, headers=GITHUB_HEADERS, json=payload)
            response.raise_for_status()
            print("✓ Webhook configurado correctamente")
            return True
        except requests.exceptions.RequestException as e:
            print(f"❌ Error configurando webhook: {e}")
            return False


def main():
    """Función principal"""
    print("\n" + "=" * 60)
    print(" Script de Sincronización GitHub <-> OpenProject")
    print("=" * 60)
    
    # Crear instancia
    sync = GitHubSync()
    
    # Validar configuración
    if not sync.validate_config():
        print("\n📝 Configura las variables de entorno:")
        print("  export GITHUB_TOKEN='tu_token_aqui'")
        print("  export GITHUB_REPO='owner/repo'")
        print("  export OPENPROJECT_API_KEY='tu_api_key_aqui'")
        sys.exit(1)
    
    # Solicitar ID del proyecto
    try:
        project_id = int(input("\n📋 Ingresa el ID del proyecto en OpenProject: "))
    except ValueError:
        print("❌ ID de proyecto inválido")
        sys.exit(1)
    
    # Menú de opciones
    print("\n¿Qué deseas hacer?")
    print("1. Sincronizar issues de GitHub a OpenProject")
    print("2. Configurar webhook automático")
    print("3. Ambas")
    
    choice = input("\nOpción (1-3): ").strip()
    
    if choice in ['1', '3']:
        sync.sync_issues_to_workpackages(project_id)
    
    if choice in ['2', '3']:
        sync.setup_webhook()
    
    print("\n✓ Proceso completado\n")


if __name__ == "__main__":
    main()
