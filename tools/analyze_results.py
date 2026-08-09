#!/usr/bin/env python3
"""Analiza results/benchmark.csv y genera las tablas y graficas del informe.

Produce exactamente los dos formatos de tabla que muestra el PDF del profesor
(seccion 3.3.4.d):

  Tabla 1 - "escenario x variable" para UNA metrica, ordenada por dificultad.
  Tabla 2 - por escenario, una fila por valor de variable y una columna por
            metrica.

Ademas grafica las curvas de convergencia de cada configuracion.

Uso:
    python tools/analyze_results.py
    python tools/analyze_results.py --results results --metric tasa_exito
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    import pandas as pd
except ImportError:  # pragma: no cover
    raise SystemExit("Falta pandas. Instalalo con:  pip install pandas matplotlib")

try:
    import matplotlib
    matplotlib.use("Agg")  # sin ventana: solo escribe archivos
    import matplotlib.pyplot as plt
    HAS_PLOTS = True
except ImportError:
    HAS_PLOTS = False
    print("[aviso] matplotlib no esta instalado; se generaran tablas pero no graficas.")


# Metricas de la seccion 3.3.4.b del PDF.
METRICS = {
    "tasa_exito": "Tasa de exito",
    "tiempo_vida_agente_s": "Tiempo de vida (s)",
    "dps_agente": "Dano por segundo",
    "victoria_agente": "Ratio de victorias",
}

# Escenarios ordenados por dificultad creciente, como sugiere el PDF.
SCENARIO_ORDER = [
    "s01_A_1v1", "s02_B_1v1", "s03_C_1v1", "s04_humano_1v1",
    "s05_A_varios", "s06_B_varios", "s07_C_varios",
    "s08_mixto_1agente", "s09_mixto_varios", "s10_humano_varios",
]


def load(results_dir: Path) -> pd.DataFrame:
    csv_path = results_dir / "benchmark.csv"
    if not csv_path.exists():
        raise SystemExit(
            f"No existe {csv_path}.\n"
            "Corre primero el benchmark:\n"
            '  godot --headless --path . res://game/benchmark_runner.tscn -- --repeats 5'
        )
    df = pd.read_csv(csv_path)
    # Metrica derivada: el CSV guarda el ganador como texto.
    df["victoria_agente"] = (df["ganador"] == "agente").astype(float)
    return df


def config_label(df: pd.DataFrame) -> pd.Series:
    """Etiqueta legible de la configuracion: 'variable=valor'."""
    return df["variable_barrida"].astype(str) + "=" + df["valor_variable"].astype(str)


def table_scenario_by_variable(df: pd.DataFrame, metric: str) -> pd.DataFrame:
    """Tabla 1: filas = configuracion, columnas = escenario, celdas = metrica."""
    df = df.copy()
    df["config"] = config_label(df)
    pivot = df.pivot_table(
        index="config", columns="escenario", values=metric, aggfunc="mean"
    )
    cols = [c for c in SCENARIO_ORDER if c in pivot.columns]
    cols += [c for c in pivot.columns if c not in cols]
    return pivot[cols].round(3)


def table_per_scenario(df: pd.DataFrame) -> pd.DataFrame:
    """Tabla 2: filas = (escenario, configuracion), columnas = las 4 metricas."""
    df = df.copy()
    df["config"] = config_label(df)
    grouped = df.groupby(["escenario", "config"]).agg(
        corridas=("ganador", "size"),
        ratio_victorias=("victoria_agente", "mean"),
        tiempo_vida_s=("tiempo_vida_agente_s", "mean"),
        dps=("dps_agente", "mean"),
        tasa_exito=("tasa_exito", "mean"),
    )
    return grouped.round(3)


def table_variable_effect(df: pd.DataFrame) -> pd.DataFrame:
    """Efecto marginal de cada variable, promediando sobre los 10 escenarios.

    Es la lectura que hace util un barrido OFAT: cuanto mueve cada variable la
    aguja respecto a la configuracion base.
    """
    df = df.copy()
    df["config"] = config_label(df)
    agg = df.groupby(["variable_barrida", "valor_variable"]).agg(
        ratio_victorias=("victoria_agente", "mean"),
        tasa_exito=("tasa_exito", "mean"),
        dps=("dps_agente", "mean"),
        tiempo_vida_s=("tiempo_vida_agente_s", "mean"),
        fitness=("fitness", "mean"),
    ).round(3)
    return agg.sort_values("tasa_exito", ascending=False)


def plot_convergence(results_dir: Path, out_dir: Path) -> None:
    if not HAS_PLOTS or not results_dir.exists():
        return
    files = sorted(results_dir.glob("convergencia_*.json"))
    if not files:
        return
    fig, ax = plt.subplots(figsize=(11, 6))
    for f in files:
        try:
            rows = json.loads(f.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            continue
        if not rows:
            continue
        # Las generaciones se reinician en cada etapa del curriculum; se
        # concatenan en un eje continuo para ver el progreso completo.
        best = [r["mejor"] for r in rows]
        label = f.stem.replace("convergencia_", "")
        ax.plot(range(len(best)), best, label=label, linewidth=1.4)
    ax.set_xlabel("Generacion acumulada (todas las etapas del curriculum)")
    ax.set_ylabel("Fitness del mejor individuo")
    ax.set_title("Convergencia por configuracion")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8, ncol=2)
    fig.tight_layout()
    path = out_dir / "convergencia.png"
    fig.savefig(path, dpi=140)
    plt.close(fig)
    print(f"  grafica: {path}")


def plot_metric_by_scenario(df: pd.DataFrame, metric: str, out_dir: Path) -> None:
    if not HAS_PLOTS:
        return
    pivot = table_scenario_by_variable(df, metric)
    fig, ax = plt.subplots(figsize=(12, 6))
    pivot.T.plot(ax=ax, marker="o", linewidth=1.3)
    ax.set_xlabel("Escenario (dificultad creciente)")
    ax.set_ylabel(METRICS.get(metric, metric))
    ax.set_title(f"{METRICS.get(metric, metric)} por escenario y configuracion")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=8, ncol=2, title="Configuracion")
    plt.setp(ax.get_xticklabels(), rotation=30, ha="right")
    fig.tight_layout()
    path = out_dir / f"{metric}_por_escenario.png"
    fig.savefig(path, dpi=140)
    plt.close(fig)
    print(f"  grafica: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", default="results", help="carpeta de resultados")
    parser.add_argument("--metric", default="tasa_exito", choices=list(METRICS),
                        help="metrica de la tabla escenario x variable")
    args = parser.parse_args()

    results_dir = Path(args.results)
    out_dir = results_dir          # todo plano en results/, sin subcarpetas
    out_dir.mkdir(parents=True, exist_ok=True)

    df = load(results_dir)
    print(f"Cargadas {len(df)} corridas de {results_dir/'benchmark.csv'}\n")

    t1 = table_scenario_by_variable(df, args.metric)
    t2 = table_per_scenario(df)
    t3 = table_variable_effect(df)

    for name, table in (("tabla_escenario_x_variable", t1),
                        ("tabla_por_escenario", t2),
                        ("tabla_efecto_variables", t3)):
        csv_path = out_dir / f"{name}.csv"
        table.to_csv(csv_path)
        md_path = out_dir / f"{name}.md"
        md_path.write_text(table.to_markdown(), encoding="utf-8")
        print(f"  tabla: {csv_path}")

    print(f"\n--- {METRICS[args.metric]} por escenario y configuracion ---")
    print(t1.to_string())
    print("\n--- Efecto marginal de cada variable ---")
    print(t3.to_string())

    plot_convergence(results_dir, out_dir)
    for metric in ("tasa_exito", "victoria_agente"):
        plot_metric_by_scenario(df, metric, out_dir)

    print(f"\nTodo escrito en {out_dir}")


if __name__ == "__main__":
    main()
