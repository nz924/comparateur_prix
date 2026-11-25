"""Exécute Strix sur Glovo Tunisie.

À n'utiliser que dans le cadre d'un test autorisé (autorisation écrite
obtenue du propriétaire du site). Ne pas lancer sans cette autorisation.

Pré-requis avant de lancer :
  - Docker en cours d'exécution
  - strix installé (pipx install strix-agent)
  - Variables d'environnement du modèle LLM définies :
        export STRIX_LLM="openai/gpt-4o"
        export LLM_API_KEY="sk-...ta_clé_openai..."

Lancement :
    python3 Python/STRIX_glovo.py
"""

import subprocess

TARGET = "https://glovoapp.com/tn/"

CMD = [
    "strix",
    "--target", TARGET,
    "--scan-mode", "standard",   # quick | standard | deep
    "--non-interactive",         # pas de TUI, s'arrête à la fin
    "--max-budget", "5",         # plafond de coût LLM en USD
]

subprocess.run(CMD, check=True)
