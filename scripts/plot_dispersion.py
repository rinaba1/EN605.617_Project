#!/usr/bin/env python3
"""Overhead shot dispersion view: fairway, yardage lines, and simulated landings as shot dots.
Dots are colored green (hit) / red (miss)

Usage:
  python plot_dispersion.py --sim-id 9999
"""

import argparse
import json
from typing import Tuple

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Circle, Rectangle


def load_landings_csv(path: str) -> Tuple[np.ndarray, np.ndarray]:
    data = np.loadtxt(path, delimiter=",", skiprows=1)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    if data.shape[1] < 2:
        raise ValueError(f"expected at least 2 columns in {path}")
    return data[:, 0].astype(np.float64), data[:, 1].astype(np.float64)


def load_run_metadata(sim_id: int) -> Tuple[float, float]:
    path = f"output/json/run_sim{sim_id}.json"
    with open(path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    return float(meta["target_dist_yds"]), float(meta["target_radius_yds"])


def _axis_limits(
    x: np.ndarray,
    z: np.ndarray,
    target_dist: float,
    target_radius: float,
    pad_x: float,
    pad_z: float,
) -> Tuple[float, float, float, float]:
    x_min = float(np.min(x))
    x_max = float(np.max(x))
    z_min = float(np.min(z))
    z_max = float(np.max(z))
    # target circle
    x_min = min(x_min, -target_radius)
    x_max = max(x_max, target_radius)
    z_min = min(z_min, target_dist - target_radius)
    z_max = max(z_max, target_dist + target_radius)
    z_min = min(0.0, z_min - pad_z * 0.5)
    x_min -= pad_x
    x_max += pad_x
    z_max += pad_z
    return x_min, x_max, z_min, z_max


def draw_fairway_scene(
    ax: plt.Axes,
    x_min: float,
    x_max: float,
    z_min: float,
    z_max: float,
    target_dist: float,
) -> None:
    """Grass, fairway corridor, yardage ticks (horizontal), center target line."""
    ax.set_facecolor("#2f5233")

    fw_half = max(45.0, (x_max - x_min) * 0.18)
    z_span = z_max - z_min
    fair = Rectangle(
        (-fw_half, z_min),
        2.0 * fw_half,
        z_span,
        facecolor="#4a7c4f",
        edgecolor="#5a9160",
        linewidth=0.8,
        alpha=0.85,
        zorder=0,
    )
    ax.add_patch(fair)

    if x_min < -fw_half:
        ax.add_patch(
            Rectangle(
                (x_min, z_min),
                -fw_half - x_min,
                z_span,
                facecolor="#2a452e",
                edgecolor="none",
                alpha=0.6,
                zorder=0,
            )
        )
    if x_max > fw_half:
        ax.add_patch(
            Rectangle(
                (fw_half, z_min),
                x_max - fw_half,
                z_span,
                facecolor="#2a452e",
                edgecolor="none",
                alpha=0.6,
                zorder=0,
            )
        )

    # yardage reference lines every 25 yd
    z0 = int(z_min // 25) * 25
    for z_line in np.arange(z0, z_max + 25, 25):
        ax.axhline(z_line, color="white", alpha=0.14, linewidth=0.7, zorder=1)
        if z_line >= z_min and z_line <= z_max and z_line % 50 == 0:
            ax.text(
                x_max - 0.02 * (x_max - x_min),
                z_line,
                f"{int(z_line)}",
                va="center",
                ha="right",
                fontsize=8,
                color="white",
                alpha=0.55,
                zorder=2,
            )

    # target line from tee
    ax.axvline(0.0, color="white", alpha=0.22, linewidth=1.1, linestyle="-", zorder=1)
    ax.plot(
        [0],
        [0],
        marker="^",
        markersize=9,
        color="white",
        markeredgecolor="#222",
        zorder=6,
    )
    ax.text(
        0,
        z_min + 0.02 * z_span,
        "TEE",
        ha="center",
        va="bottom",
        fontsize=9,
        color="white",
        alpha=0.7,
    )


def plot_shots(
    ax: plt.Axes,
    x: np.ndarray,
    z: np.ndarray,
    target_dist: float,
    target_radius: float,
) -> Tuple[int, int, float]:
    """Draw target zone and shots. Returns (n, n_inside, mean_carry)."""
    dx = x
    dz = z - target_dist
    dist = np.sqrt(dx * dx + dz * dz)
    inside = dist <= target_radius
    n = int(x.size)
    n_in = int(np.sum(inside))
    mean_carry = float(np.mean(z)) if n else 0.0

    # target zone
    target_fill = Circle(
        (0.0, target_dist),
        target_radius,
        facecolor="#c4d96a",
        edgecolor="#f5f5dc",
        linewidth=2.0,
        alpha=0.45,
        zorder=2,
    )
    ax.add_patch(target_fill)
    target_ring = Circle(
        (0.0, target_dist),
        target_radius,
        facecolor="none",
        edgecolor="#fffacd",
        linewidth=2.2,
        linestyle="-",
        zorder=5,
    )
    ax.add_patch(target_ring)

    ax.scatter(
        x[~inside],
        z[~inside],
        c="#e85d4c",
        s=10.0,
        alpha=0.72,
        linewidths=0.35,
        edgecolors="#3d1510",
        label="Miss",
        zorder=5,
    )
    ax.scatter(
        x[inside],
        z[inside],
        c="#7cb342",
        s=10.0,
        alpha=0.87,
        linewidths=0.35,
        edgecolors="#1e3d14",
        label="Hit",
        zorder=5,
    )

    return n, n_in, mean_carry


def main() -> None:
    p = argparse.ArgumentParser(
        description="Shot dispersion plot from results_sim<ID>.csv"
    )
    p.add_argument(
        "--sim-id",
        type=int,
        required=True,
        help="Simulation ID for this run (loads results_sim<ID>.csv)",
    )
    p.add_argument("--no-save", action="store_true")
    p.add_argument("--show", action="store_true")
    args = p.parse_args()

    csv_path = f"output/csv/results_sim{args.sim_id}.csv"
    target_dist, target_radius = load_run_metadata(args.sim_id)

    out_path = f"output/plots/dispersion_sim{args.sim_id}.png"

    x, z = load_landings_csv(csv_path)
    pad_x = max(15.0, 0.08 * (float(np.max(x)) - float(np.min(x)) + 1.0))
    pad_z = max(20.0, 0.06 * (float(np.max(z)) - float(np.min(z)) + 1.0))
    x_min, x_max, z_min, z_max = _axis_limits(
        x, z, target_dist, target_radius, pad_x, pad_z
    )

    plt.rcParams["font.family"] = "DejaVu Sans"
    fig, ax = plt.subplots(figsize=(10, 8))
    fig.patch.set_facecolor("#1e2a1f")

    draw_fairway_scene(ax, x_min, x_max, z_min, z_max, target_dist)

    n, n_in, mean_carry = plot_shots(
        ax,
        x,
        z,
        target_dist,
        target_radius,
    )
    pct = 100.0 * n_in / n if n else 0.0

    ax.set_xlim(x_min, x_max)
    ax.set_ylim(z_min, z_max)
    ax.set_xlabel("Lateral (yds)", fontsize=11, color="#f0f0f0", fontweight="600")
    ax.set_ylabel("Distance (yds)", fontsize=11, color="#f0f0f0", fontweight="600")
    fig.suptitle(
        "Shot dispersion", fontsize=15, color="white", fontweight="700", y=0.98
    )
    ax.set_title(
        f"{n:,} shots  •  avg carry {mean_carry:.1f} yd  •  {pct:.1f}% in target",
        fontsize=10,
        color="#c8e6c9",
        pad=10,
    )
    ax.tick_params(colors="#d0d0d0", labelsize=9)
    for spine in ax.spines.values():
        spine.set_edgecolor("#4a6b4e")
        spine.set_linewidth(1.0)
    ax.set_aspect("equal", adjustable="box")

    handles, _ = ax.get_legend_handles_labels()
    if handles:
        ax.legend(
            loc="lower left",
            framealpha=0.92,
            facecolor="#2a3d2c",
            edgecolor="#5a7c5e",
            labelcolor="#f0f0f0",
            fontsize=9,
        )
    fig.tight_layout(rect=[0, 0, 1, 0.95])

    if not args.no_save:
        import os

        os.makedirs("output/plots", exist_ok=True)
        fig.savefig(
            out_path, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor()
        )
        print(f"Wrote {out_path}")
    if args.show or args.no_save:
        plt.show()


if __name__ == "__main__":
    main()
