"""Exécute Strix sur une application locale de test uniquement."""

import subprocess

TARGET = "http://127.0.0.1:8000"

subprocess.run(["strix", "--target", TARGET], check=True)
