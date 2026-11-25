"""Importe les restaurants depuis OpenStreetMap (Overpass) dans la table
`restaurant` de la base MySQL `UR`.

Source : OpenStreetMap (données ODbL, libres de réutilisation avec attribution).
Par défaut : zone du Grand Tunis. Modifier BBOX pour une autre zone.

Usage :
    python3 Python/import_osm_restaurants.py

Les identifiants MySQL sont lus depuis l'environnement, avec repli sur la
config locale du projet :
    DB_HOST (localhost) DB_USER (nselmi) DB_PASSWORD (...) DB_NAME (UR)
"""

import json
import os
import urllib.parse
import urllib.request

import pymysql

# --- Zone géographique : sud, ouest, nord, est (Grand Tunis) ---
BBOX = (36.60, 10.10, 36.95, 10.42)

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

DB = dict(
    host=os.getenv("DB_HOST", "localhost"),
    user=os.getenv("DB_USER", "nselmi"),
    password=os.getenv("DB_PASSWORD", ""),  # défini via la variable d'env DB_PASSWORD
    database=os.getenv("DB_NAME", "UR"),
    charset="utf8mb4",
)


def fetch_osm():
    s, w, n, e = BBOX
    query = (
        f'[out:json][timeout:90];'
        f'(nwr["amenity"="restaurant"]({s},{w},{n},{e}););'
        f'out center tags;'
    )
    data = urllib.parse.urlencode({"data": query}).encode()
    last_err = None
    for ep in OVERPASS_ENDPOINTS:
        try:
            req = urllib.request.Request(
                ep, data=data,
                headers={"User-Agent": "comparateur_prix-dev/1.0"},
            )
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.load(r).get("elements", [])
        except Exception as exc:  # noqa: BLE001
            last_err = exc
            print(f"  échec {ep}: {exc}")
    raise RuntimeError(f"Tous les miroirs Overpass ont échoué: {last_err}")


def to_row(el):
    t = el.get("tags", {})
    name = t.get("name")
    if not name:
        return None
    lat = el.get("lat") or (el.get("center") or {}).get("lat")
    lon = el.get("lon") or (el.get("center") or {}).get("lon")
    cuisine = t.get("cuisine")
    if cuisine:
        cuisine = cuisine.replace(";", ", ")
    street = " ".join(x for x in (t.get("addr:housenumber"), t.get("addr:street")) if x)
    ville = t.get("addr:city") or t.get("addr:suburb")
    return {
        "nom": name[:200],
        "type_cuisine": (cuisine or None) and cuisine[:120],
        "adresse": (street or None) and street[:300],
        "ville": (ville or None) and ville[:120],
        "latitude": lat,
        "longitude": lon,
        "image_url": (t.get("image") or None) and t.get("image")[:500],
        "source": "openstreetmap",
        "source_url": f"https://www.openstreetmap.org/{el['type']}/{el['id']}"[:500],
    }


SQL = """
INSERT INTO restaurant
    (nom, type_cuisine, adresse, ville, latitude, longitude,
     image_url, source, source_url)
VALUES
    (%(nom)s, %(type_cuisine)s, %(adresse)s, %(ville)s, %(latitude)s,
     %(longitude)s, %(image_url)s, %(source)s, %(source_url)s)
ON DUPLICATE KEY UPDATE
    type_cuisine = VALUES(type_cuisine),
    adresse      = VALUES(adresse),
    latitude     = VALUES(latitude),
    longitude    = VALUES(longitude),
    image_url    = VALUES(image_url),
    source       = VALUES(source),
    source_url   = VALUES(source_url)
"""


def main():
    print("Récupération depuis OpenStreetMap…")
    elements = fetch_osm()
    rows = [r for r in (to_row(e) for e in elements) if r]
    print(f"  {len(elements)} éléments, {len(rows)} restaurants nommés.")

    conn = pymysql.connect(**DB)
    try:
        with conn.cursor() as cur:
            cur.executemany(SQL, rows)
        conn.commit()
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM restaurant")
            total = cur.fetchone()[0]
        print(f"  Import terminé. Table `restaurant` : {total} lignes.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
