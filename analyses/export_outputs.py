"""Compiles every query in analyses/ and saves its result to analyses/outputs/<name>.csv.

Run after `dbt build`:  python analyses/export_outputs.py
"""
import os
import subprocess
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
subprocess.run(["dbt", "compile", "--quiet", "--select", "path:analyses"],
               cwd=ROOT, env={**os.environ, "DBT_PROFILES_DIR": str(ROOT)}, check=True)

con = duckdb.connect(str(ROOT / "casestudy.duckdb"), read_only=True)
out = ROOT / "analyses" / "outputs"
out.mkdir(exist_ok=True)
for sql in sorted((ROOT / "target" / "compiled").rglob("analyses/*.sql")):
    con.sql(sql.read_text()).write_csv(str(out / f"{sql.stem}.csv"))
    print(f"wrote analyses/outputs/{sql.stem}.csv")
